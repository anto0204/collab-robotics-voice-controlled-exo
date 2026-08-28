clear; clc; close all

upFolder   = "0-90";
downFolder = "90-0";
pattern    = "*.mat";

Ngrid = 200;
sGrid = linspace(0,1,Ngrid)';

fsTitle  = 9;
fsLabel  = 15;
fsLegend = 9;
fsTicks  = 15;

%% LOAD + INTERP (measured trials)
[Yup, Tup]     = loadInterpTime(upFolder,   pattern, sGrid);
[Ydown, Tdown] = loadInterpTime(downFolder, pattern, sGrid);

% mean durations + physical time axes
Tup   = sGrid * mean(Tup);
Tdown = sGrid * mean(Tdown);

% measured means
mu_up   = mean(Yup,   2);
mu_down = mean(Ydown, 2);

% close loop by reversing down direction (so both are 0->90 along time)
mu_down_rev = flipud(mu_down);

%% MJ REFERENCE
mj_up   = 0  + (90-0 )*(10*sGrid.^3 - 15*sGrid.^4 + 6*sGrid.^5);
mj_down = 90 + (0 -90)*(10*sGrid.^3 - 15*sGrid.^4 + 6*sGrid.^5);
mj_down_rev = flipud(mj_down);

%% NO-LOAD REFERENCE
R = load("empty_4traj.mat");
MeanEmpty = R.MeanTraj;
names = string({MeanEmpty.name});

idx_up   = find(names == "yellow-green", 1);
idx_down = find(names == "green-yellow", 1);

empty_up   = MeanEmpty(idx_up).mu(:);
empty_down = MeanEmpty(idx_down).mu(:);
empty_down_rev = flipud(empty_down);

%% SCATTER COMPARISON
figure('Color','w'); hold on; grid on; box on;

% MJ reference
hMJ = plot(Tup,   mj_up,        'r-', 'LineWidth',2.4);
plot(Tdown, mj_down_rev,  'r-', 'LineWidth',2.4, 'HandleVisibility','off');

% Scatter (all trials)
cmap_up   = lines(size(Yup,2));
cmap_down = lines(size(Ydown,2));

for i = 1:size(Yup,2)
    scatter(Tup, Yup(:,i), 10, cmap_up(i,:), ...
        'filled','MarkerFaceAlpha',0.25,'MarkerEdgeAlpha',0.25);
end

for i = 1:size(Ydown,2)
    scatter(Tdown, flipud(Ydown(:,i)), 10, cmap_down(i,:), ...
        'filled','MarkerFaceAlpha',0.25,'MarkerEdgeAlpha',0.25);
end

% Measured mean
hM = plot(Tup,   mu_up, 'b-', 'LineWidth',3.0);
hMr = plot(Tdown, mu_down_rev, 'b--', 'LineWidth',3.0, 'HandleVisibility','off');

% Legend
hSc = scatter(nan,nan,10,'filled', ...
    'MarkerFaceColor',[0.5 0.5 0.5], ...
    'MarkerFaceAlpha',0.3, ...
    'MarkerEdgeAlpha',0.3);
xlabel('Time [s]','FontSize',fsLabel);
ylabel('Angle [deg]','FontSize',fsLabel);
title('Hysteresis loop (0°↔90°): all trials', ...
      'FontSize',fsTitle);

lgd = legend([hSc hM hMr hMJ], ...
       {'Individual trials (scatter)', ...
        'Measured mean trajectory (0° → 90°)', ...
        'Measured mean trajectory (90° → 0°)', ...
        'Minimum-jerk reference'}, ...
        'Location','best');
set(lgd,'FontSize',fsLegend);

set(gca,'FontSize',fsTicks);

%% NO-LOAD COMPARISON
figure('Color','w'); hold on; grid on; box on;

% MJ reference
hMJ = plot(Tup,   mj_up,        'r-', 'LineWidth',2.2);
plot(Tdown, mj_down_rev,  'r-','LineWidth',2.2,'HandleVisibility','off');

% No-load reference
hE = plot(Tup,   empty_up,       'g-', 'LineWidth',2.2);
plot(Tdown, empty_down_rev, 'g-','LineWidth',2.2,'HandleVisibility','off');

% Measured mean
hM = plot(Tup,   mu_up,        'b--', 'LineWidth',2.5);
plot(Tdown, mu_down_rev,  'b--','LineWidth',2.5,'HandleVisibility','off');

xlabel('Time [s]','FontSize',fsLabel);
ylabel('Angle [deg]','FontSize',fsLabel);
title('Mean hysteresis loop (0°↔90°)', ...
      'FontSize',fsTitle);

lgd = legend([hMJ hE hM], ...
       {'Minimum-jerk reference', ...
        'No-load mean', ...
        'Measured mean'}, ...
       'Location','best');
set(lgd,'FontSize',fsLegend);

set(gca,'FontSize',fsTicks);


% During upward motion the joint angle is systematically lower than during 
% downward motion because part of the actuator torque is used to counteract 
% gravity.

%% LOCAL FUNCTION
function [Y, Tlist] = loadInterpTime(folder, pattern, sGrid)
    D = dir(fullfile(folder, pattern));
    files = string(fullfile(folder, {D.name}));

    Y = [];
    Tlist = [];

    for i = 1:numel(files)
        S = load(files(i));
        exo = S.exo;

        Asm = exo.pairs_time_ms_deg_smoothed;
        t = Asm(:,1)*1e-3;
        y = Asm(:,2);

        [t,ord] = sort(t); y = y(ord);

        t = t - t(1);
        T = t(end);
        if T <= 0, continue; end

        s = t / T;
        yI = interp1(s, y, sGrid, "pchip", "extrap");

        Y(:,end+1) = yI(:);
        Tlist(end+1,1) = T;
    end
end