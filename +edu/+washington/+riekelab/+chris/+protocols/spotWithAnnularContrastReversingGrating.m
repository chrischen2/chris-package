classdef spotWithAnnularContrastReversingGrating < edu.washington.riekelab.protocols.RiekeLabStageProtocol
    properties
        apertureDiameter = 300   % um (center spot)
        annulusInnerDiameter = 400  % um
        annulusOuterDiameter = 800  % um
        barWidth = [30 60]  % um

        backgroundIntensity = 0.15  % 0-1, background and gap intensity
        spotIntensity = 0.05  % 0-1, intensity of center spot
        brightBarContrast = [0.9]  % peak contrast amplitude for bright bars
        darkBarContrast = [-0.25 -0.5 -0.75 -1.0]  % peak contrast amplitude for dark bars
        temporalFrequency = [2 4]  % Hz, temporal frequency of contrast reversal

        preTime = 1000   % ms
        stimTime = 2000  % ms
        tailTime = 1000  % ms

        onlineAnalysis = 'extracellular'

        downSample = 1
        numberOfAverages = uint16(3)  % number of repeats to queue
        amp
    end

    properties(Hidden)
        ampType
        barWidthType = symphonyui.core.PropertyType('denserealdouble', 'matrix')
        brightBarContrastType = symphonyui.core.PropertyType('denserealdouble', 'matrix')
        darkBarContrastType = symphonyui.core.PropertyType('denserealdouble', 'matrix')
        temporalFrequencyType = symphonyui.core.PropertyType('denserealdouble', 'matrix')
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'exc', 'inh'})
        currentBarWidth
        currentBrightContrast
        currentDarkContrast
        currentTemporalFrequency
        stimSequence
        meanImage
        modulationImage
    end

    methods
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end

        function prepareRun(obj)
            prepareRun@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);

            % Create stimulus sequence combining all parameters
            obj.stimSequence = [];
            for bw = 1:length(obj.barWidth)
                for bc = 1:length(obj.brightBarContrast)
                    for dc = 1:length(obj.darkBarContrast)
                        for tf = 1:length(obj.temporalFrequency)
                            obj.stimSequence = [obj.stimSequence; ...
                                obj.barWidth(bw), obj.brightBarContrast(bc), ...
                                obj.darkBarContrast(dc), obj.temporalFrequency(tf)];
                        end
                    end
                end
            end

            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            obj.showFigure('edu.washington.riekelab.chris.figures.FrameTimingFigure',...
                obj.rig.getDevice('Stage'), obj.rig.getDevice('Frame Monitor'));

            if size(obj.stimSequence, 1) > 1
                colors = edu.washington.riekelab.chris.utils.pmkmp(size(obj.stimSequence, 1),'CubicYF');
            else
                colors = [0 0 0];
            end

            obj.showFigure('edu.washington.riekelab.chris.figures.MeanResponseFigure',...
                obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis',...
                'groupBy',{'currentBarWidth','currentBrightContrast','currentDarkContrast','currentTemporalFrequency'},...
                'sweepColor',colors);
        end

        function prepareEpoch(obj, epoch)
            prepareEpoch@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj, epoch);
            device = obj.rig.getDevice(obj.amp);
            duration = (obj.preTime + obj.stimTime + obj.tailTime) / 1e3;
            epoch.addDirectCurrentStimulus(device, device.background, duration, obj.sampleRate);
            epoch.addResponse(device);

            % Determine current stimulus parameters
            stimIndex = mod(obj.numEpochsCompleted, size(obj.stimSequence, 1)) + 1;
            obj.currentBarWidth = obj.stimSequence(stimIndex, 1);
            obj.currentBrightContrast = obj.stimSequence(stimIndex, 2);
            obj.currentDarkContrast = obj.stimSequence(stimIndex, 3);
            obj.currentTemporalFrequency = obj.stimSequence(stimIndex, 4);

            epoch.addParameter('currentBarWidth', obj.currentBarWidth);
            epoch.addParameter('currentBrightContrast', obj.currentBrightContrast);
            epoch.addParameter('currentDarkContrast', obj.currentDarkContrast);
            epoch.addParameter('currentTemporalFrequency', obj.currentTemporalFrequency);

            % Pre-compute grating matrices for frame-by-frame updates
            obj.precomputeGratingMatrices();
        end

        function p = createPresentation(obj)
            canvasSize = obj.rig.getDevice('Stage').getCanvasSize();
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);

            apertureDiameterPix = obj.rig.getDevice('Stage').um2pix(obj.apertureDiameter);

            % Initial image: mean (background) everywhere — no modulation at t=0
            initialImage = uint8(obj.meanImage * 255);
            scene = stage.builtin.stimuli.Image(initialImage);
            scene.size = canvasSize;
            scene.position = canvasSize/2;
            scene.setMinFunction(GL.LINEAR);
            scene.setMagFunction(GL.LINEAR);
            p.addStimulus(scene);

            % Frame-by-frame imageMatrix controller for contrast reversal
            sceneController = stage.builtin.controllers.PropertyController(scene, 'imageMatrix', ...
                @(state) obj.getGratingFrame(state.time));
            p.addController(sceneController);

            % Control visibility during stimTime only
            sceneVisible = stage.builtin.controllers.PropertyController(scene, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(sceneVisible);

            % Add center spot
            spot = stage.builtin.stimuli.Ellipse();
            spot.position = canvasSize/2;
            spot.radiusX = apertureDiameterPix/2;
            spot.radiusY = apertureDiameterPix/2;
            spot.color = obj.spotIntensity;
            p.addStimulus(spot);

            spotVisible = stage.builtin.controllers.PropertyController(spot, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(spotVisible);
        end

        function precomputeGratingMatrices(obj)
            canvasSize = obj.rig.getDevice('Stage').getCanvasSize();
            currentBarWidthPix = obj.rig.getDevice('Stage').um2pix(obj.currentBarWidth);
            annulusInnerDiameterPix = obj.rig.getDevice('Stage').um2pix(obj.annulusInnerDiameter);
            annulusOuterDiameterPix = obj.rig.getDevice('Stage').um2pix(obj.annulusOuterDiameter);

            % Create coordinate system
            [x, y] = meshgrid(linspace(-canvasSize(1)/2, canvasSize(1)/2, canvasSize(1)/obj.downSample), ...
                              linspace(-canvasSize(2)/2, canvasSize(2)/2, canvasSize(2)/obj.downSample));

            % Create square wave grating spatial pattern
            grating = sign(sin(2*pi*x/currentBarWidthPix));
            brightBars = (grating > 0);
            darkBars = (grating <= 0);

            % Create annular mask
            r = sqrt(x.^2 + y.^2);
            annulusMask = (r >= annulusInnerDiameterPix/2) & (r <= annulusOuterDiameterPix/2);

            % Mean image: background everywhere
            obj.meanImage = obj.backgroundIntensity * ones(size(grating));

            % Modulation image: per-pixel amplitude of sinusoidal modulation
            % Non-zero only within the annulus
            obj.modulationImage = zeros(size(grating));
            obj.modulationImage(brightBars & annulusMask) = obj.backgroundIntensity * obj.currentBrightContrast;
            obj.modulationImage(darkBars & annulusMask) = obj.backgroundIntensity * obj.currentDarkContrast;

            % Warn if peak modulation would produce out-of-range values
            peakMax = max(obj.meanImage(:) + abs(obj.modulationImage(:)));
            peakMin = min(obj.meanImage(:) - abs(obj.modulationImage(:)));
            if peakMax > 1 || peakMin < 0
                warning('Grating intensity may go out of range: peak max = %.3f, peak min = %.3f', ...
                    peakMax, peakMin);
            end
        end

        function imgMat = getGratingFrame(obj, time)
            t = time - obj.preTime * 1e-3;  % time relative to stimulus onset
            modulation = sin(2 * pi * obj.currentTemporalFrequency * t);
            imgMat = obj.meanImage + obj.modulationImage * modulation;
            % Clamp to valid range and convert to uint8
            imgMat = uint8(max(0, min(255, round(imgMat * 255))));
        end

        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages * size(obj.stimSequence, 1);
        end

        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages * size(obj.stimSequence, 1);
        end
    end
end
