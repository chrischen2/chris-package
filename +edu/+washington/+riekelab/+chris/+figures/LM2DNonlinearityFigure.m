classdef LM2DNonlinearityFigure < symphonyui.core.FigureHandler
    % LM2DNonlinearityFigure
    %
    % 2D linear-nonlinear analysis matching Turner et al. 2018 (eLife),
    % Figs. 4-5, restricted to L vs. M cone axes.
    %
    % METHOD (mirrors Turner18 Materials and Methods, "Data analysis and
    % modeling"):
    %
    %   1. From LNoise (L-isolated) epochs, accumulate the L-cone noise
    %      trace and response, and update an L linear filter via reverse
    %      correlation. (Turner18 Fig 4A, left column.)
    %
    %   2. From MNoise (M-isolated) epochs, accumulate the M-cone noise
    %      trace and response, and update an M linear filter the same way.
    %      (Turner18 Fig 4A, middle column.)
    %
    %   3. From LMNoise (joint) epochs, accumulate L noise, M noise, and
    %      response. The filters from (1) and (2) -- "trials in which the
    %      center or surround was stimulated in isolation" -- are convolved
    %      with these joint stimuli to produce L and M linear predictions.
    %      Click the toolbar button to bin the joint (L_pred, M_pred) plane
    %      and render the mean response as a contour surface
    %      (Turner18 Fig 5A, generalised from RGC RF subregions to cone class).
    %
    % Constructor parameters (passed by LMConeNoise.prepareRun):
    %   recordingType        - 'extracellular' | 'exc' | 'inh'
    %   preTime, stimTime    - ms, must match protocol
    %   frameDwell           - frames per noise update, must match protocol
    %   lNoiseStdv, mNoiseStdv - L/M contrasts (must match protocol)
    %   lSeedID, mSeedID     - epoch.parameters() keys for L and M seeds
    %   stimulusKey          - epoch parameter that names the stim type
    %                          ('LNoise' | 'MNoise' | 'LMNoise');
    %                          default 'currentStimulus'
    %   figureTitle          - window title

    properties (SetAccess = private)
        ampDevice
        frameMonitor
        stageDevice
        recordingType
        preTime
        stimTime
        frameDwell
        lNoiseStdv
        mNoiseStdv
        lSeedID
        mSeedID
        stimulusKey
        figureTitle
    end

    properties (Access = private)
        axesFilters
        axes2D
        cbHandle
        % Independent-channel accumulators (for filter estimation)
        lAloneStimuli       % from LNoise epochs
        lAloneResponses
        mAloneStimuli       % from MNoise epochs
        mAloneResponses
        % Joint accumulators (for 2D nonlinearity)
        jointLStimuli       % from LMNoise epochs
        jointMStimuli
        jointResponses
        lFilter
        mFilter
        updateRate
    end

    methods

        function obj = LM2DNonlinearityFigure(ampDevice, frameMonitor, stageDevice, varargin)
            obj.ampDevice    = ampDevice;
            obj.frameMonitor = frameMonitor;
            obj.stageDevice  = stageDevice;

            ip = inputParser();
            ip.addParameter('recordingType', [],            @(x)ischar(x));
            ip.addParameter('preTime',       [],            @(x)isvector(x));
            ip.addParameter('stimTime',      [],            @(x)isvector(x));
            ip.addParameter('frameDwell',    [],            @(x)isvector(x));
            ip.addParameter('lNoiseStdv',    0.3,           @(x)isvector(x));
            ip.addParameter('mNoiseStdv',    0.3,           @(x)isvector(x));
            ip.addParameter('lSeedID',       'lNoiseSeed',  @(x)ischar(x));
            ip.addParameter('mSeedID',       'mNoiseSeed',  @(x)ischar(x));
            ip.addParameter('stimulusKey',   'currentStimulus', @(x)ischar(x));
            ip.addParameter('figureTitle',   'L+M 2D nonlinearity', @(x)ischar(x));
            ip.parse(varargin{:});

            obj.recordingType = ip.Results.recordingType;
            obj.preTime       = ip.Results.preTime;
            obj.stimTime      = ip.Results.stimTime;
            obj.frameDwell    = ip.Results.frameDwell;
            obj.lNoiseStdv    = ip.Results.lNoiseStdv;
            obj.mNoiseStdv    = ip.Results.mNoiseStdv;
            obj.lSeedID       = ip.Results.lSeedID;
            obj.mSeedID       = ip.Results.mSeedID;
            obj.stimulusKey   = ip.Results.stimulusKey;
            obj.figureTitle   = ip.Results.figureTitle;

            obj.lAloneStimuli   = [];
            obj.lAloneResponses = [];
            obj.mAloneStimuli   = [];
            obj.mAloneResponses = [];
            obj.jointLStimuli   = [];
            obj.jointMStimuli   = [];
            obj.jointResponses  = [];

            obj.createUi();
        end

        function createUi(obj)
            import appbox.*;
            toolbar = findall(obj.figureHandle, 'Type', 'uitoolbar');
            compute2DButton = uipushtool('Parent', toolbar, ...
                'TooltipString', 'Compute 2D nonlinearity (Turner18 Fig 5)', ...
                'Separator', 'on', ...
                'ClickedCallback', @obj.onCompute2D);
            try
                iconDir = [fileparts(fileparts(mfilename('fullpath'))), filesep, '+utils', filesep, '+icons', filesep];
                setIconImage(compute2DButton, [iconDir, 'exp.png']);
            catch
            end

            obj.axesFilters = subplot(1, 2, 1, 'Parent', obj.figureHandle);
            xlabel(obj.axesFilters, 'Time (ms)');
            ylabel(obj.axesFilters, 'Filter');
            title(obj.axesFilters, 'L (red) / M (green) filters [from isolated epochs]');

            obj.axes2D = subplot(1, 2, 2, 'Parent', obj.figureHandle);
            xlabel(obj.axes2D, 'L linear prediction');
            ylabel(obj.axes2D, 'M linear prediction');
            title(obj.axes2D, '2D nonlinearity (click toolbar to compute)');

            obj.figureHandle.Name = obj.figureTitle;
        end

        function handleEpoch(obj, epoch)
            % Branch on stim type. Different epoch classes feed different accumulators.
            stimType = epoch.parameters(obj.stimulusKey);

            % Common preprocessing: response trace, frame timing, response on update grid
            [respUpd, frameRate, ok] = obj.extractEpochResponseOnUpdateGrid(epoch);
            if ~ok; return; end
            obj.updateRate = frameRate / obj.frameDwell;

            switch stimType
                case 'LNoise'
                    lNoise = obj.reconstructNoise(epoch.parameters(obj.lSeedID), ...
                                                   obj.lNoiseStdv, length(respUpd));
                    obj.lAloneStimuli   = cat(1, obj.lAloneStimuli,   lNoise);
                    obj.lAloneResponses = cat(1, obj.lAloneResponses, respUpd);
                    obj.updateLFilter();

                case 'MNoise'
                    mNoise = obj.reconstructNoise(epoch.parameters(obj.mSeedID), ...
                                                   obj.mNoiseStdv, length(respUpd));
                    obj.mAloneStimuli   = cat(1, obj.mAloneStimuli,   mNoise);
                    obj.mAloneResponses = cat(1, obj.mAloneResponses, respUpd);
                    obj.updateMFilter();

                case 'LMNoise'
                    lNoise = obj.reconstructNoise(epoch.parameters(obj.lSeedID), ...
                                                   obj.lNoiseStdv, length(respUpd));
                    mNoise = obj.reconstructNoise(epoch.parameters(obj.mSeedID), ...
                                                   obj.mNoiseStdv, length(respUpd));
                    obj.jointLStimuli  = cat(1, obj.jointLStimuli,  lNoise);
                    obj.jointMStimuli  = cat(1, obj.jointMStimuli,  mNoise);
                    obj.jointResponses = cat(1, obj.jointResponses, respUpd);
            end

            obj.refreshFilterPlot();
        end

    end

    methods (Access = private)

        function [respUpd, frameRate, ok] = extractEpochResponseOnUpdateGrid(obj, epoch)
            % Returns the response trace re-binned onto the noise-update grid,
            % the monitor frame rate, and a success flag. Mirrors the
            % preprocessing in LinearFilterFigure.handleEpoch.
            ok = false; respUpd = []; frameRate = NaN;
            try
                response = epoch.getResponse(obj.ampDevice);
            catch
                return;
            end
            epochResponseTrace = response.getData();
            sampleRate = response.sampleRate.quantityInBaseUnits;
            prePts = sampleRate * obj.preTime / 1000;

            if strcmp(obj.recordingType, 'extracellular')
                newResponse = zeros(size(epochResponseTrace));
                S = edu.washington.riekelab.turner.utils.spikeDetectorOnline(epochResponseTrace);
                newResponse(S.sp) = 1;
            else
                epochResponseTrace = epochResponseTrace - mean(epochResponseTrace(1:prePts));
                if strcmp(obj.recordingType, 'exc')
                    polarity = -1;
                else
                    polarity = 1;
                end
                newResponse = polarity * epochResponseTrace;
            end

            if isa(obj.stageDevice, 'edu.washington.riekelab.devices.LightCrafterDevice')
                lightCrafterFlag = 1;
            else
                lightCrafterFlag = 0;
            end
            frameRate = obj.stageDevice.getMonitorRefreshRate();
            FMresponse = epoch.getResponse(obj.frameMonitor);
            FMdata = FMresponse.getData();
            frameTimes = edu.washington.riekelab.turner.utils.getFrameTiming(FMdata, lightCrafterFlag);
            preFrames = frameRate * (obj.preTime / 1000);
            firstStimFrameFlip = frameTimes(preFrames + 1);
            newResponse = newResponse(firstStimFrameFlip:end);

            stimFrames = round(frameRate * (obj.stimTime / 1e3));
            nUpdates = floor(stimFrames / obj.frameDwell);
            chunkLen = obj.frameDwell * mean(diff(frameTimes));
            respUpd = zeros(1, nUpdates);
            for ii = 1:nUpdates
                idx0 = round((ii-1) * chunkLen + 1);
                idx1 = min(round(ii * chunkLen), length(newResponse));
                if idx0 > length(newResponse); break; end
                respUpd(ii) = mean(newResponse(idx0:idx1));
            end
            ok = true;
        end

        function noise = reconstructNoise(~, seed, stdv, nUpdates)
            % Replays a single epoch's noise trace from its stored seed.
            % Matches the runtime call pattern: one randn per update window,
            % scaled by the contrast (stdv).
            stream = RandStream('mt19937ar', 'Seed', seed);
            noise = zeros(1, nUpdates);
            for ii = 1:nUpdates
                noise(ii) = stdv * stream.randn;
            end
        end

        function updateLFilter(obj)
            if isempty(obj.lAloneResponses); return; end
            obj.lFilter = edu.washington.riekelab.turner.utils.getLinearFilterOnline( ...
                obj.lAloneStimuli, obj.lAloneResponses, ...
                obj.updateRate, obj.updateRate);
        end

        function updateMFilter(obj)
            if isempty(obj.mAloneResponses); return; end
            obj.mFilter = edu.washington.riekelab.turner.utils.getLinearFilterOnline( ...
                obj.mAloneStimuli, obj.mAloneResponses, ...
                obj.updateRate, obj.updateRate);
        end

        function refreshFilterPlot(obj)
            if isempty(obj.updateRate); return; end
            filterLen = 800;  % ms
            filterPts = round((filterLen / 1000) * obj.updateRate);
            filterTimes = linspace(0, filterLen, filterPts);

            cla(obj.axesFilters);
            hold(obj.axesFilters, 'on');
            line([filterTimes(1), filterTimes(end)], [0 0], 'Parent', obj.axesFilters, ...
                'Color', 'k', 'LineStyle', '--');
            if ~isempty(obj.lFilter)
                lf = obj.lFilter(1:min(filterPts, length(obj.lFilter)));
                line(filterTimes(1:length(lf)), lf, 'Parent', obj.axesFilters, ...
                    'Color', 'r', 'LineWidth', 2);
            end
            if ~isempty(obj.mFilter)
                mf = obj.mFilter(1:min(filterPts, length(obj.mFilter)));
                line(filterTimes(1:length(mf)), mf, 'Parent', obj.axesFilters, ...
                    'Color', 'g', 'LineWidth', 2);
            end
            hold(obj.axesFilters, 'off');
            xlabel(obj.axesFilters, 'Time (ms)');
            ylabel(obj.axesFilters, 'Filter');
            nL = size(obj.lAloneResponses, 1);
            nM = size(obj.mAloneResponses, 1);
            nJ = size(obj.jointResponses, 1);
            title(obj.axesFilters, sprintf('L/M filters (n_L=%d, n_M=%d isolated; n_{LM}=%d joint)', nL, nM, nJ));
            try; legend(obj.axesFilters, {'zero', 'L', 'M'}, 'Location', 'best'); catch; end
        end

        function onCompute2D(obj, ~, ~)
            % Compute the 2D mean-response surface on the joint epochs,
            % using filters fit from the isolated epochs (Turner18 method).
            if isempty(obj.lFilter) || isempty(obj.mFilter)
                title(obj.axes2D, 'Need at least one LNoise and one MNoise epoch first');
                return;
            end
            if isempty(obj.jointResponses)
                title(obj.axes2D, 'Need at least one LMNoise epoch first');
                return;
            end

            lStim = reshape(obj.jointLStimuli', 1, numel(obj.jointLStimuli));
            mStim = reshape(obj.jointMStimuli', 1, numel(obj.jointMStimuli));
            resp  = reshape(obj.jointResponses', 1, numel(obj.jointResponses));

            lPred = conv(lStim, obj.lFilter);  lPred = lPred(1:length(lStim));
            mPred = conv(mStim, obj.mFilter);  mPred = mPred(1:length(mStim));

            % Bin joint linear predictions; use 2nd-98th percentile edges so
            % outliers do not dominate the grid.
            nBins = 12;
            lEdges = linspace(quantile(lPred, 0.02), quantile(lPred, 0.98), nBins + 1);
            mEdges = linspace(quantile(mPred, 0.02), quantile(mPred, 0.98), nBins + 1);
            lCtr = (lEdges(1:end-1) + lEdges(2:end)) / 2;
            mCtr = (mEdges(1:end-1) + mEdges(2:end)) / 2;

            meanResp = nan(nBins, nBins);   % rows = M, cols = L
            counts   = zeros(nBins, nBins);
            for li = 1:nBins
                inL = lPred >= lEdges(li) & lPred < lEdges(li+1);
                for mi = 1:nBins
                    inM = mPred >= mEdges(mi) & mPred < mEdges(mi+1);
                    sel = inL & inM;
                    n = sum(sel);
                    if n >= 5
                        meanResp(mi, li) = mean(resp(sel));
                        counts(mi, li) = n;
                    end
                end
            end

            cla(obj.axes2D);
            contourf(obj.axes2D, lCtr, mCtr, meanResp, 12, 'LineStyle', 'none');
            hold(obj.axes2D, 'on');
            contour(obj.axes2D, lCtr, mCtr, meanResp, 8, 'Color', [1 1 1 0.5], 'LineWidth', 0.75);
            xl = [lCtr(1), lCtr(end)];
            yl = [mCtr(1), mCtr(end)];
            line([0, 0], yl, 'Parent', obj.axes2D, 'Color', 'w', 'LineStyle', '--');
            line(xl, [0, 0], 'Parent', obj.axes2D, 'Color', 'w', 'LineStyle', '--');
            hold(obj.axes2D, 'off');
            axis(obj.axes2D, 'tight');
            colormap(obj.axes2D, 'parula');
            if isempty(obj.cbHandle) || ~isvalid(obj.cbHandle)
                obj.cbHandle = colorbar('peer', obj.axes2D);
            end
            xlabel(obj.axes2D, 'L linear prediction');
            ylabel(obj.axes2D, 'M linear prediction');
            title(obj.axes2D, sprintf('2D NL: mean resp (n=%d updates from %d LMNoise epochs)', ...
                length(resp), size(obj.jointResponses, 1)));
        end
    end
end
