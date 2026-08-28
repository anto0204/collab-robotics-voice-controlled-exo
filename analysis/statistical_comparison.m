clear; clc; close all

%% CONFIG
folders = ["0-45","0-90","45-0","90-0"];
labels  = {'0° → 45°','0° → 90°','45° → 0°','90° → 0°'};

% MJ nominal endpoints per folder
targets = [0 45; 0 90; 45 0; 90 0];

% EMPTY reference mapping (folder -> MeanTraj.name in empty_4traj.mat)
refNamesWanted = strings(1,4);
refNamesWanted(1) = "yellow-blue";   % 0-45
refNamesWanted(2) = "yellow-green";  % 0-90
refNamesWanted(3) = "blue-yellow";   % 45-0
refNamesWanted(4) = "green-yellow";  % 90-0

% Common grid for comparison (matches empty_4traj.mat generation)
Ngrid = 200;
sGrid = linspace(0,1,Ngrid)';

xJitter = 0.08;

%% LOAD EMPTY REFERENCE
R = load("empty_4traj.mat");        % contains MeanTraj
MeanEmpty  = R.MeanTraj;
emptyNames = string({MeanEmpty.name});

%% PREALLOC
ERR_MJ     = cell(1,4);   % all per-sample errors vs MJ (stacked)
ERR_EMPTY  = cell(1,4);   % all per-sample errors vs EMPTY mean (stacked)
RMS_EMPTY  = cell(1,4);   % one RMS per trial vs EMPTY
RMS_MJ     = cell(1,4);   % one RMS per trial vs MJ  <-- ADD

%% MAIN (single pass over files per folder)
for k = 1:4
    files = dir(fullfile(folders(k),"*.mat"));

    % MJ endpoints for this folder
    q0 = targets(k,1);
    qF = targets(k,2);
    q_mj_grid = q0 + (qF - q0) .* (10*sGrid.^3 - 15*sGrid.^4 + 6*sGrid.^5);

    % EMPTY reference for this folder
    idxRef = find(emptyNames == refNamesWanted(k), 1);
    mu_empty = MeanEmpty(idxRef).mu(:);   % Ngrid x 1

    e_mj_all    = [];
    e_empty_all = [];

    for i = 1:numel(files)
        S = load(fullfile(files(i).folder, files(i).name));
        exo = S.exo;

        t = exo.raw.time_ms(:) * 1e-3;
        y = exo.smoothed.deg(:);

        [t,ord] = sort(t);
        y = y(ord);

        t = t - t(1);
        T = t(end);
        if T <= 0, continue; end
        s = t / T;

        % interpolate trial to common s grid (so both references match)
        yI = interp1(s, y, sGrid, "pchip", "extrap");

        % errors (stacked point-wise)
        e_mj_all    = [e_mj_all;    (yI(:) - q_mj_grid(:))];
        e_empty_all = [e_empty_all; (yI(:) - mu_empty(:))];

        % RMS per trial
        RMS_EMPTY{k}(end+1,1) = sqrt(mean((yI(:) - mu_empty(:)).^2));
        RMS_MJ{k}(end+1,1)    = sqrt(mean((yI(:) - q_mj_grid(:)).^2));   % <-- ADD
    end

    ERR_MJ{k}    = e_mj_all;
    ERR_EMPTY{k} = e_empty_all;
end

%% MJ REFERENCE (point-wise errors)

% Scatter (MJ)
figure('Color','w'); hold on; grid on; box on;
for k = 1:4
    e = ERR_MJ{k};
    x = k + (rand(size(e))-0.5)*2*xJitter;
    plot(x, e, '.', 'MarkerSize',6);
end
xlim([0.5 4.5]);
xticks(1:4); xticklabels(labels);
ylabel('Error vs MJ reference [deg]');
title('Instantaneous tracking error vs MJ reference (all trials)');
yline(0,'k--','LineWidth',1.2);

% Boxplot (MJ) point-wise
data = vertcat(ERR_MJ{:});
grp  = [];
for k = 1:4
    grp = [grp; k*ones(numel(ERR_MJ{k}),1)];
end

figure('Color','w'); hold on; grid on; box on;
boxplot(data, grp, 'Labels', labels, 'Symbol','');

hBox = plot(nan,nan,'s','MarkerFaceColor',[0 0.447 0.741], ...
                     'MarkerEdgeColor',[0 0.447 0.741]);
hMed = plot(nan,nan,'r-','LineWidth',2);
hWhi = plot(nan,nan,'--','Color',[0.6 0.6 0.6],'LineWidth',1);
legend([hBox hMed hWhi], ...
       {'IQR (25–75 percentile)', ...
        'Median (50 percentile)', ...
        'Whiskers (±1.5 IQR)'}, ...
       'Location','best');

ylabel('Error vs MJ reference [deg]');
title('Tracking error distribution vs MJ reference');
yline(0,'k--','LineWidth',1.2,'HandleVisibility','off');

%% MJ REFERENCE (RMSE per trial)  <-- ADD THIS BLOCK

data = vertcat(RMS_MJ{:});
grp  = [];
for k = 1:4
    grp = [grp; k*ones(numel(RMS_MJ{k}),1)];
end

figure('Color','w'); hold on; grid on; box on;
boxplot(data, grp, 'Labels', labels, 'Symbol','');

hBox = plot(nan,nan,'s','MarkerFaceColor',[0 0.447 0.741], ...
                     'MarkerEdgeColor',[0 0.447 0.741]);
hMed = plot(nan,nan,'r-','LineWidth',2);
hWhi = plot(nan,nan,'--','Color',[0.6 0.6 0.6],'LineWidth',1);
legend([hBox hMed hWhi], ...
       {'IQR (25–75 percentile)', ...
        'Median (50 percentile)', ...
        'Whiskers (±1.5 IQR)'}, ...
       'Location','best');

ylabel('RMSE vs MJ reference [deg]');
title('RMSE tracking error vs MJ reference');
yline(0,'k--','LineWidth',1.2,'HandleVisibility','off');

%% NO-LOAD REFERENCE (point-wise + RMSE)

% Scatter (EMPTY)
figure('Color','w'); hold on; grid on; box on;
for k = 1:4
    e = ERR_EMPTY{k};
    x = k + (rand(size(e))-0.5)*2*xJitter;
    plot(x, e, '.', 'MarkerSize',6);
end
xlim([0.5 4.5]);
xticks(1:4); xticklabels(labels);
ylabel('Error vs no-load mean [deg]');
title('Instantaneous tracking error vs no-load reference (all trials)');
yline(0,'k--','LineWidth',1.2);

% Boxplot error (EMPTY)
data = vertcat(ERR_EMPTY{:});
grp  = [];
for k = 1:4
    grp = [grp; k*ones(numel(ERR_EMPTY{k}),1)];
end

figure('Color','w'); hold on; grid on; box on;
boxplot(data, grp, 'Labels', labels, 'Symbol','');

hBox = plot(nan,nan,'s','MarkerFaceColor',[0 0.447 0.741], ...
                     'MarkerEdgeColor',[0 0.447 0.741]);
hMed = plot(nan,nan,'r-','LineWidth',2);
hWhi = plot(nan,nan,'--','Color',[0.6 0.6 0.6],'LineWidth',1);
legend([hBox hMed hWhi], ...
       {'IQR (25–75 percentile)', ...
        'Median (50 percentile)', ...
        'Whiskers (±1.5 IQR)'}, ...
       'Location','best');

ylabel('Error vs no-load mean [deg]');
title('Tracking error distribution vs no-load reference');
yline(0,'k--','LineWidth',1.2,'HandleVisibility','off');

% Boxplot RMS (EMPTY)
data = vertcat(RMS_EMPTY{:});
grp  = [];
for k = 1:4
    grp = [grp; k*ones(numel(RMS_EMPTY{k}),1)];
end

figure('Color','w'); hold on; grid on; box on;
boxplot(data, grp, 'Labels', labels, 'Symbol','');

hBox = plot(nan,nan,'s','MarkerFaceColor',[0 0.447 0.741], ...
                     'MarkerEdgeColor',[0 0.447 0.741]);
hMed = plot(nan,nan,'r-','LineWidth',2);
hWhi = plot(nan,nan,'--','Color',[0.6 0.6 0.6],'LineWidth',1);

legend([hBox hMed hWhi], ...
       {'IQR (25–75 percentile)', ...
        'Median (50 percentile)', ...
        'Whiskers (±1.5 IQR)'}, ...
       'Location','best');

ylabel('RMSE vs no-load mean [deg]');
title('RMSE tracking error vs no-load reference');
yline(0,'k--','LineWidth',1.2,'HandleVisibility','off');
