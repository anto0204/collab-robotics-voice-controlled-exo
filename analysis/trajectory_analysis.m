%% MAIN.M — BUILD _4traj.mat FOR ALL SUBJECT FOLDERS + PLOTS (COLORBAR + LEGENDS + SGTITLE)
clear; clc; close all;

rootDir = pwd;

%% ===== CONFIG =====
Ngrid = 200;
s = linspace(0,1,Ngrid);

% subplot order/positions (fixed)
orderNames = {'yellow-blue','yellow-green','blue-yellow','green-yellow'};
subplotPos = containers.Map(orderNames, {1,2,3,4});

% fixed MJ targets aligned with orderNames
targets = [0 45;   % yellow-blue
           0 90;   % yellow-green
           45 0;   % blue-yellow
           90 0];  % green-yellow

pattern = 'exo_time_deg_*.mat';
subjectFolders = ["Antonio","Davide","Empty","Lorenzo","MatteoP","MatteoR"];

doPlot = true;

%% ===== LOOP SUBJECTS =====
for sIdx = 1:numel(subjectFolders)

    subjName = subjectFolders(sIdx);
    subjDir  = fullfile(rootDir, subjName);

    if ~isfolder(subjDir)
        warning('Missing folder: %s (skipped)', subjDir);
        continue;
    end

    fprintf('\n=== %s ===\n', subjName);

    MeanTraj = struct('name',{},'t',{},'mu',{},'q_mj',{},'Tmean',{},'nTrials',{});

    %% FIGURES (one set per subject)
    if doPlot
        fig1 = figure('Name',sprintf('%s — Fig1 Mean + MJ',subjName), 'Color','w'); clf;
        % fig2 = figure('Name',sprintf('%s — Fig2 Jerk',subjName),     'Color','w'); clf;
        fig3 = figure('Name',sprintf('%s — Fig3 Mean + CI',subjName),'Color','w'); clf;
        fig4 = figure('Name',sprintf('%s — Fig4 Error + CI',subjName),'Color','w'); clf;

        % legend refs (set once)
        hMean_ref = gobjects(1,1);
        hMJ_ref   = gobjects(1,1);
        hJ_ref    = gobjects(1,1);
        hJMJ_ref  = gobjects(1,1);
        hCI_ref   = gobjects(1,1);
        hErrCI_ref= gobjects(1,1);
        hErr_ref  = gobjects(1,1);

        gotMeanMJ = false;
        gotJerk   = false;
        gotCI     = false;
        gotErrCI  = false;
    end

    %% ===== LOOP TRAJECTORIES =====
    for it = 1:4

        trajName = orderNames{it};
        trajDir  = fullfile(subjDir, trajName);

        if ~isfolder(trajDir)
            warning('%s: missing trajectory folder %s (skipped)', subjName, trajName);
            continue;
        end

        D = dir(fullfile(trajDir, pattern));
        if isempty(D)
            warning('%s: no files in %s (skipped)', subjName, trajDir);
            continue;
        end
        files = string(fullfile(trajDir, {D.name}));

        Ydeg  = [];
        Tlist = [];

        %% --- load trials ---
        for k = 1:numel(files)
            S = load(files(k));
            if ~isfield(S,'exo'), continue; end
            exo = S.exo;

            if isfield(exo,'pairs_time_ms_deg_smoothed')
                Asm = exo.pairs_time_ms_deg_smoothed;
                if size(Asm,2) < 2 || size(Asm,1) < 2, continue; end
                t0 = Asm(:,1)*1e-3;
                y0 = Asm(:,2);

            elseif isfield(exo,'raw') && isfield(exo.raw,'time_ms') && isfield(exo,'smoothed') && isfield(exo.smoothed,'deg')
                t0 = exo.raw.time_ms(:)*1e-3;
                y0 = exo.smoothed.deg(:);

            else
                continue;
            end

            [t0,idx] = sort(t0);
            y0 = y0(idx);

            t0 = t0 - t0(1);
            T  = t0(end);
            if ~(isfinite(T) && T > 0), continue; end

            Tlist(end+1,1) = T;

            yi = interp1(t0/T, y0, s, "pchip", "extrap");
            Ydeg(:,end+1) = yi(:);
        end

        n = size(Ydeg,2);
        if n < 2
            warning('%s: %s has <2 trials (skipped)', subjName, trajName);
            continue;
        end

        %% --- stats ---
        mu = mean(Ydeg,2);
        sd = std(Ydeg,0,2);
        tcrit = tinv(0.975, n-1);
        ci = tcrit*sd/sqrt(n);
        lo = mu-ci; hi = mu+ci;

        Tmean = mean(Tlist);
        t = s*Tmean;

        vel  = gradient(mu,t);
        jerk = gradient(gradient(vel,t),t);

        %% --- minimum jerk (fixed targets) ---
        q0 = targets(it,1);
        qf = targets(it,2);
        q_mj = q0 + (qf-q0).*(10*s.^3 - 15*s.^4 + 6*s.^5);
        jerk_mj = gradient(gradient(gradient(q_mj,t),t),t);

        %% --- error vs MJ ---
        E = Ydeg - q_mj(:);
        err_mu = mean(E,2);
        sd_err = std(E,0,2);
        ci_err = tcrit*sd_err/sqrt(n);
        err_lo = err_mu - ci_err;
        err_hi = err_mu + ci_err;

        %% --- save ---
        MeanTraj(it) = struct( ...
            'name',    trajName, ...
            't',       t(:), ...
            'mu',      mu(:), ...
            'q_mj',    q_mj(:), ...
            'Tmean',   Tmean, ...
            'nTrials', n );

        %% --- plots ---
        if doPlot
            p = subplotPos(trajName);

            % FIG 1 — mean + MJ + scatter colored by |vel|
            figure(fig1);
            ax = subplot(2,2,p); hold(ax,'on'); grid(ax,'on'); box(ax,'on');
            scatter(ax, t, mu, 25, abs(vel), 'filled', 'HandleVisibility','off');
            hMean = plot(ax, t, mu,   'k-', 'LineWidth', 2);
            hMJ   = plot(ax, t, q_mj, 'r-', 'LineWidth', 2);
            xlim(ax,[0 t(end)]);
            title(ax,trajName);
            xlabel(ax,'Time [s]'); ylabel(ax,'Angle [deg]');

            if ~gotMeanMJ
                hMean_ref = hMean;
                hMJ_ref   = hMJ;
                gotMeanMJ = true;
            end

            % % FIG 2 — jerk
            % figure(fig2);
            % ax = subplot(2,2,p); hold(ax,'on'); grid(ax,'on'); box(ax,'on');
            % hJ   = plot(ax, t, jerk,    'b-', 'LineWidth', 1.8);
            % hJMJ = plot(ax, t, jerk_mj, 'r-', 'LineWidth', 1.8);
            % xlim(ax,[0 t(end)]);
            % title(ax,trajName);
            % xlabel(ax,'Time [s]'); ylabel(ax,'Jerk [deg/s^3]');
            % 
            % if ~gotJerk
            %     hJ_ref   = hJ;
            %     hJMJ_ref = hJMJ;
            %     gotJerk  = true;
            % end

            % FIG 3 — mean + CI
            figure(fig3);
            ax = subplot(2,2,p); hold(ax,'on'); grid(ax,'on'); box(ax,'on');
            hCI   = patch(ax, [t fliplr(t)], [lo.' fliplr(hi.')], 'r', ...
                'FaceAlpha',0.25,'EdgeColor','none');
            hMean = plot(ax, t, mu, 'b-', 'LineWidth', 2.2);

            xlim(ax,[0 t(end)]);
            title(ax,trajName);
            xlabel(ax,'Time [s]'); ylabel(ax,'Angle [deg]');

            if ~gotCI
                hCI_ref   = hCI;
                hMeanCI_ref = hMean;
                gotCI = true;
            end

            % FIG 4 — error + CI
            figure(fig4);
            ax = subplot(2,2,p); hold(ax,'on'); grid(ax,'on'); box(ax,'on');
            hErrCI = patch(ax, [t fliplr(t)], [err_lo.' fliplr(err_hi.')], 'r', ...
                           'FaceAlpha',0.25,'EdgeColor','none');
            hErr = plot(ax, t, err_mu, 'b-', 'LineWidth', 2.2);
            yline(ax,0,'k--','LineWidth',1.1,'HandleVisibility','off');
            xlim(ax,[0 t(end)]);
            title(ax,trajName);
            xlabel(ax,'Time [s]'); ylabel(ax,'Error [deg]');

            if ~gotErrCI
                hErrCI_ref = hErrCI;
                hErr_ref   = hErr;
                gotErrCI   = true;
            end
        end
    end

    %% ===== POST-PLOT DECORATIONS (ONCE PER FIGURE) =====
    if doPlot
        % Fig1: ONE shared colorbar + colormap
        figure(fig1);
        colormap(parula);
        cb = colorbar;
        cb.Label.String = '|\omega| [deg/s]';
        sgtitle(sprintf('%s — Mean trajectory vs Minimum-Jerk', subjName));
        if gotMeanMJ
            legend([hMean_ref hMJ_ref], {'Mean trajectory','Minimum-jerk'}, ...
                   'Location','southoutside','Orientation','horizontal');
        end

        % figure(fig2);
        % sgtitle(sprintf('%s — Jerk comparison', subjName));
        % if gotJerk
        %     legend([hJ_ref hJMJ_ref], {'Mean jerk','Minimum-jerk jerk'}, ...
        %            'Location','southoutside','Orientation','horizontal');
        % end

        figure(fig3);
        sgtitle(sprintf('%s — Mean trajectory with 95%% CI', subjName));
        if gotCI
            legend([hMeanCI_ref hCI_ref], ...
                {'Mean trajectory','95% CI'}, ...
                'Location','southoutside','Orientation','horizontal');
        end

        figure(fig4);
        sgtitle(sprintf('%s — Tracking error with 95%% CI', subjName));
        if gotErrCI
            legend([hErrCI_ref hErr_ref], {'95% CI','Mean error'}, ...
                   'Location','southoutside','Orientation','horizontal');
        end
    end

    %% ===== SAVE FILE =====
    outName = lower(char(subjName));
    outName = strrep(outName,' ','');
    outFile = sprintf('%s_41traj.mat', outName);
    save(fullfile(rootDir,outFile), 'MeanTraj');
    fprintf('Saved: %s\n', outFile);
end
