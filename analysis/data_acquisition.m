clear; clc; close all;

%% SERIAL CONFIGURATION
serial_port = "COM8";     % Serial port (change if needed)
baudrate    = 9600;       % Must match Arduino sketch
idle_stop_s = 1.0;        % Stop acquisition if no data for this time [s]

disp("=== OPEN SERIAL PORT ===");

% Open serial port and configure line terminator
s = serialport(serial_port, baudrate, "Timeout", 0.2);
configureTerminator(s, "LF");
flush(s);

pause(2); % Allow Arduino reset after serial connection

disp("Acquiring lines formatted as: time_ms,deg");

% Buffers for acquired data
t_ms = [];
deg  = [];

% Timer used to detect inactivity (end of trajectory)
tLastRx = tic;

%% ACQUISITION LOOP
while true
    % No data available
    if s.NumBytesAvailable == 0
        % Stop only if data was already received and inactivity timeout expired
        if ~isempty(t_ms) && toc(tLastRx) > idle_stop_s
            break;
        end
        pause(0.01);
        continue;
    end

    % Read one line from serial
    raw = strtrim(readline(s));
    if raw == "", continue; end

    % Expect exactly: time_ms,deg
    parts = split(raw, ",");
    if numel(parts) ~= 2, continue; end

    % Convert to numeric values
    t_val   = str2double(parts{1});
    deg_val = str2double(parts{2});
    if isnan(t_val) || isnan(deg_val), continue; end

    % Append valid sample
    t_ms(end+1,1) = t_val;
    deg(end+1,1)  = deg_val;

    % Reset inactivity timer
    tLastRx = tic;
end

% Close serial port
clear s;
disp("=== SERIAL PORT CLOSED ===");

%% DATA ORDERING & SMOOTHING
% Sort samples by time (safety against out-of-order prints)
[t_ms, idx] = sort(t_ms);
deg = deg(idx);

% Convert time to seconds
t_s = t_ms * 1e-3;

% Smoothing
smooth_win_samples = 7;   % Moving average window (samples)
deg_s = movmean(deg, smooth_win_samples, 'omitnan');

%% SAVE DATA
exo = struct();
exo.serial_port  = serial_port;
exo.baudrate     = baudrate;
exo.time_ms      = t_ms;
exo.time_s       = t_s;
exo.deg_raw      = deg;
exo.deg_smooth   = deg_s;
exo.pairs_raw    = [t_ms, deg];
exo.pairs_smooth = [t_ms, deg_s];

mat_name = "exo_time_deg.mat";
save(mat_name, "exo");
fprintf("Saved file: %s", mat_name);

%% PLOT
figure; hold on; grid on; box on;
plot(t_s, deg,   'LineWidth', 1.0);
plot(t_s, deg_s, 'LineWidth', 1.6);
legend('raw','smoothed','Location','best');
xlabel('Time [s]');
ylabel('Angle [deg]');
title('Trajectory: angle vs time');