clear; clc; close all;

%% ===== SUBJECT FILES =====
subjects = struct( ...
    'name', {'Subject 1','Subject 2','Subject 3','Subject 4','Subject 5'}, ...
    'file', {'antonio_4traj.mat','davide_4traj.mat','lorenzo_4traj.mat','matteoP_4traj.mat','matteoR_4traj.mat'} ...
);
nSub = numel(subjects);

%% ===== COMMON GRID =====
Ngrid = 200;
s = linspace(0,1,Ngrid);

%% ===== REQUIRED SUBPLOT ORDER =====
orderNames = {'yellow-blue','yellow-green','blue-yellow','green-yellow'};
posMap = containers.Map(orderNames, [1 2 3 4]);
targets = [0 45; 0 90; 45 0; 90 0];

%% ===== LOAD MeanTraj FOR ALL SUBJECTS =====
Sdata = cell(nSub,1);
for i = 1:nSub
    A = load(subjects(i).file);
    Sdata{i} = A.MeanTraj;
end

%% FIGURES OPTIONS
fig1 = figure('Name','Group mean vs min-jerk (scatter |vel|)'); clf;
% fig2 = figure('Name','Group jerk vs min-jerk jerk'); clf;
fig3 = figure('Name','Subject mean trajectories + group CI'); clf;
fig4 = figure('Name','Subject mean errors + group CI'); clf;

ax1 = gobjects(4,1); ax2 = gobjects(4,1); ax3 = gobjects(4,1); ax4 = gobjects(4,1);

% legend handles
hMean1_ref = []; hMJ_ref     = [];
hJerk_ref  = []; hJerkMJ_ref = [];
hCI_ref    = []; hSub_ref    = []; hMean_ref = [];
hCIe_ref   = []; hE_ref      = []; hErr_ref  = [];

%% LOOP OVER THE 4 REQUIRED TRAJECTORIES

for kTraj = 1:numel(orderNames)
    
    % Find trajectory
    trajName = orderNames{kTraj};
    sp = posMap(trajName); % subplot position index (1..4)
    Ysub  = nan(Ngrid, nSub);
    Tlist = nan(nSub,1);

    for i = 1:nSub
        MT = Sdata{i};
        names_i = strings(numel(MT),1);
        
        for j = 1:numel(MT)
            names_i(j) = string(MT(j).name);
        end

        idx = find(strcmpi(names_i, trajName), 1);

        t0 = MT(idx).t;
        y0 = MT(idx).mu;

        T = t0(end);
        Tlist(i) = T;

        sn = t0 / T;
        sn = min(max(sn,0),1);

        Ysub(:,i) = interp1(sn, y0, s, "pchip", "extrap");
    end

    % Group mean + 95% CI
    mu = mean(Ysub, 2, 'omitnan');
    sd = std(Ysub, 0, 2, 'omitnan');

    alpha = 0.05;
    tcrit = tinv(1-alpha/2, nSub-1);
    ci = tcrit * sd / sqrt(nSub);

    lo = mu - ci;
    hi = mu + ci;
    Tmean = mean(Tlist, 'omitnan');
    t = s * Tmean;

    vel  = gradient(mu, t);
    acc  = gradient(vel, t);
    jerk = gradient(acc, t);

    % Min-jerk reference based on group endpoints
    q0 = targets(kTraj,1);
    qf = targets(kTraj,2);
    q_mj = q0 + (qf-q0) .* (10*s.^3 - 15*s.^4 + 6*s.^5);
    jerk_mj = gradient(gradient(gradient(q_mj, t), t), t);

    % Error: subject-wise + group
    E = Ysub - q_mj(:);
    err_mu = mean(E, 2, 'omitnan');
    sd_err = std(E, 0, 2, 'omitnan');
    ci_err = tcrit * sd_err / sqrt(nSub);
    err_lo = err_mu - ci_err;
    err_hi = err_mu + ci_err;

    %% PLOTS
    figure(fig1);
    ax1(sp) = subplot(2,2,sp); hold on; grid on; box on;

    scatter(t, mu, 40, abs(vel), 'filled', 'HandleVisibility','off');
    hMean1 = plot(t, mu,   'k-', 'LineWidth', 2.2);
    hMJ    = plot(t, q_mj, 'r-', 'LineWidth', 2.2);

    colormap(ax1(sp), parula);
    cb = colorbar(ax1(sp));
    cb.Label.String = '|\omega| [deg/s]';

    xlim([t(1) t(end)]);
    xlabel('Time [s]'); ylabel('Angle [deg]');
    title([trajName ' – Mean vs min-jerk']);

    % figure(fig2);
    % ax2(sp) = subplot(2,2,sp); hold on; grid on; box on;
    % 
    % hJerk   = plot(t, jerk,    'b-', 'LineWidth', 2.0);
    % hJerkMJ = plot(t, jerk_mj, 'r-', 'LineWidth', 2.0);
    % 
    % xlim([t(1) t(end)]);
    % xlabel('Time [s]'); ylabel('Jerk [deg/s^3]');
    % title([trajName ' – Jerk']);
    % 
    % if isempty(hJerk_ref),   hJerk_ref   = hJerk;   end
    % if isempty(hJerkMJ_ref), hJerkMJ_ref = hJerkMJ; end

    figure(fig3);
    ax3(sp) = subplot(2,2,sp); hold on; grid on; box on;
    hCI  = patch([t fliplr(t)], [lo.' fliplr(hi.')], ...
                 'r', 'FaceAlpha', 0.25, 'EdgeColor','none');

    hSub = gobjects(nSub,1);
    for i = 1:nSub
        hSub(i) = plot(t, Ysub(:,i), '-', 'LineWidth', 1.3);
    end

    hMean = plot(t, mu, 'k-', 'LineWidth', 2.4);
    xlim([t(1) t(end)]);
    xlabel('Time [s]'); ylabel('Angle [deg]');
    title([trajName ' – Subjects + group CI']);

    figure(fig4);
    ax4(sp) = subplot(2,2,sp); hold on; grid on; box on;

    hCIe = patch([t fliplr(t)], [err_lo.' fliplr(err_hi.')], ...
                 'r', 'FaceAlpha', 0.25, 'EdgeColor','none');

    hE = gobjects(nSub,1);
    for i = 1:nSub
        hE(i) = plot(t, E(:,i), '-', 'LineWidth', 1.2);
    end

    hErr = plot(t, err_mu, 'k-', 'LineWidth', 2.4);
    yline(0,'k--','LineWidth',1.1,'HandleVisibility','off');
    % ±5 deg error bounds
    yline( 5, 'k--', 'LineWidth', 1.2, 'HandleVisibility','off');
    yline(-5, 'k--', 'LineWidth', 1.2, 'HandleVisibility','off');

    xlim([t(1) t(end)]);
    xlabel('Time [s]'); ylabel('Error [deg]');
    title([trajName ' – Error']);

end

%% TITLES AND OPTIONS
figure(fig1); sgtitle('Group mean trajectory vs minimum-jerk (scatter |vel|)');
% figure(fig2); sgtitle('Group jerk vs minimum-jerk jerk');
figure(fig3); sgtitle('Subject mean trajectories + group 95% CI');
figure(fig4); sgtitle('Subject mean errors + group 95% CI');

% One global legend per figure
figure(fig1);
legend([hMean1_ref, hMJ_ref], ...
       {'Group mean','Minimum-jerk'}, ...
       'Location','southoutside','Orientation','horizontal');

% figure(fig2);
% legend([hJerk_ref, hJerkMJ_ref], ...
%        {'Group mean jerk','Min-jerk jerk'}, ...
%        'Location','southoutside','Orientation','horizontal');

figure(fig3);
legend([hCI_ref, hSub_ref.', hMean_ref], ...
       [{'Group 95% CI'}, {subjects.name}, {'Group mean'}], ...
       'Location','southoutside','Orientation','horizontal');

figure(fig4);
legend([hCIe_ref, hE_ref.', hErr_ref], ...
       [{'Group 95% CI'}, {subjects.name}, {'Group mean error'}], ...
       'Location','southoutside','Orientation','horizontal');

