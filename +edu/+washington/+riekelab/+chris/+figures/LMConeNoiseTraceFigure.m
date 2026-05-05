classdef LMConeNoiseTraceFigure < symphonyui.core.FigureHandler
    % LMConeNoiseTraceFigure
    %
    % Reconstructs one example epoch per stimulus type from stored seeds.
    % Top row: intended L/M isomerization trajectories.
    % Bottom row: raw red/green gun trajectories plus clipped delivered values.

    properties (SetAccess = private)
        stageDevice
        preTime
        stimTime
        frameDwell
        meanIsom
        LNoiseContrast
        MNoiseContrast
        rgToLm
    end

    properties (Access = private)
        plottedTypes
    end

    methods
        function obj = LMConeNoiseTraceFigure(stageDevice, varargin)
            obj.stageDevice = stageDevice;

            ip = inputParser();
            ip.addParameter('preTime', 500,        @(x)isnumeric(x));
            ip.addParameter('stimTime', 8000,      @(x)isnumeric(x));
            ip.addParameter('frameDwell', 2,       @(x)isnumeric(x));
            ip.addParameter('meanIsom', 15000,     @(x)isnumeric(x));
            ip.addParameter('LNoiseContrast', 0.3, @(x)isnumeric(x));
            ip.addParameter('MNoiseContrast', 0.3, @(x)isnumeric(x));
            ip.addParameter('rgToLm', eye(2),      @(x)isnumeric(x) && isequal(size(x), [2,2]));
            ip.parse(varargin{:});

            obj.preTime        = ip.Results.preTime;
            obj.stimTime       = ip.Results.stimTime;
            obj.frameDwell     = ip.Results.frameDwell;
            obj.meanIsom       = ip.Results.meanIsom;
            obj.LNoiseContrast = ip.Results.LNoiseContrast;
            obj.MNoiseContrast = ip.Results.MNoiseContrast;
            obj.rgToLm         = ip.Results.rgToLm;

            obj.plottedTypes = {};
            obj.figureHandle.Name = 'LM cone noise: stimulus trace sanity check';
        end

        function handleEpoch(obj, epoch)
            stimType = epoch.parameters('currentStimulus');
            if any(strcmp(obj.plottedTypes, stimType))
                return;
            end
            obj.plottedTypes{end+1} = stimType;

            lSeed = epoch.parameters('lNoiseSeed');
            mSeed = epoch.parameters('mNoiseSeed');

            try
                frameRate = obj.stageDevice.getMonitorRefreshRate();
            catch
                frameRate = 60;
            end

            stimFrames = round(frameRate * obj.stimTime / 1e3);
            nUpdates = floor(stimFrames / obj.frameDwell);
            t = (0:nUpdates-1) * obj.frameDwell / frameRate;

            [lIsom, mIsom] = obj.reconstructConeTraces(stimType, lSeed, mSeed, nUpdates);
            lmToRgLocal = inv(obj.rgToLm);
            rgRaw = lmToRgLocal * [lIsom; mIsom];
            rgClip = max(0, min(1, rgRaw));
            clipFrac = mean(rgRaw(:) < 0 | rgRaw(:) > 1);

            allTypes = {'LNoise', 'MNoise', 'LMNoise'};
            col = find(strcmp(allTypes, stimType), 1);
            if isempty(col); col = numel(obj.plottedTypes); end

            axIsom = subplot(2, 3, col, 'Parent', obj.figureHandle);
            cla(axIsom);
            plot(axIsom, t, lIsom, 'r-', t, mIsom, 'g-');
            title(axIsom, sprintf('%s: intended cones', stimType));
            ylabel(axIsom, 'Cone isom (R*/sec)');
            xlabel(axIsom, 'Time (s)');
            xlim(axIsom, [t(1), t(end)]);
            yMargin = max(0.1 * obj.meanIsom, 1.05 * max(abs([lIsom mIsom] - obj.meanIsom)));
            ylim(axIsom, [obj.meanIsom - yMargin, obj.meanIsom + yMargin]);
            legend(axIsom, {'L', 'M'}, 'Location', 'best');

            axGun = subplot(2, 3, col + 3, 'Parent', obj.figureHandle);
            cla(axGun);
            hold(axGun, 'on');
            plot(axGun, t, rgRaw(1,:), 'Color', [1.0 0.6 0.6], 'LineWidth', 0.5);
            plot(axGun, t, rgRaw(2,:), 'Color', [0.6 1.0 0.6], 'LineWidth', 0.5);
            plot(axGun, t, rgClip(1,:), 'r-', 'LineWidth', 1);
            plot(axGun, t, rgClip(2,:), 'g-', 'LineWidth', 1);
            line([t(1) t(end)], [0 0], 'Parent', axGun, 'Color', 'k', 'LineStyle', ':');
            line([t(1) t(end)], [1 1], 'Parent', axGun, 'Color', 'k', 'LineStyle', ':');
            hold(axGun, 'off');
            ylim(axGun, [min(-0.05, min(rgRaw(:)) - 0.05), max(1.05, max(rgRaw(:)) + 0.05)]);
            xlim(axGun, [t(1), t(end)]);
            xlabel(axGun, 'Time (s)');
            ylabel(axGun, 'Gun intensity');
            title(axGun, sprintf('R/G raw + clipped; clipped %.2f%%', 100 * clipFrac));
            legend(axGun, {'R raw','G raw','R delivered','G delivered'}, 'Location', 'best');

            drawnow;
        end
    end

    methods (Access = private)
        function [lIsom, mIsom] = reconstructConeTraces(obj, stimType, lSeed, mSeed, nUpdates)
            lStream = RandStream('mt19937ar', 'Seed', lSeed);
            mStream = RandStream('mt19937ar', 'Seed', mSeed);

            lIsom = zeros(1, nUpdates);
            mIsom = zeros(1, nUpdates);
            for ii = 1:nUpdates
                switch stimType
                    case 'LNoise'
                        lIsom(ii) = obj.meanIsom * (1 + obj.LNoiseContrast * lStream.randn);
                        mIsom(ii) = obj.meanIsom;
                    case 'MNoise'
                        lIsom(ii) = obj.meanIsom;
                        mIsom(ii) = obj.meanIsom * (1 + obj.MNoiseContrast * mStream.randn);
                    case 'LMNoise'
                        lIsom(ii) = obj.meanIsom * (1 + obj.LNoiseContrast * lStream.randn);
                        mIsom(ii) = obj.meanIsom * (1 + obj.MNoiseContrast * mStream.randn);
                    otherwise
                        lIsom(ii) = obj.meanIsom;
                        mIsom(ii) = obj.meanIsom;
                end
            end
        end
    end
end
