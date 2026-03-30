classdef spotWithAnnularContrastReversingGrating < edu.washington.riekelab.protocols.RiekeLabStageProtocol
    properties
        apertureDiameter = 300   % um (center spot)
        annulusInnerDiameter = 400  % um
        annulusOuterDiameter = 800  % um
        barWidth = [30 60]  % um

        backgroundIntensity = 0.15  % 0-1, background and gap intensity
        spotIntensity = 0.05  % 0-1, intensity of center spot
        brightBarContrast = [0.9]  % positive peak of asymmetric contrast waveform
        darkBarContrast = [-0.25 -0.5 -0.75 -1.0]  % negative peak of asymmetric contrast waveform
        temporalFrequency = [2 4]  % Hz, temporal frequency of contrast reversal
        temporalClass = 'sinewave'  % temporal waveform: sinewave or squarewave

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
        temporalClassType = symphonyui.core.PropertyType('char', 'row', {'sinewave', 'squarewave'})
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'exc', 'inh'})
        currentBarWidth
        currentBrightContrast
        currentDarkContrast
        currentTemporalFrequency
        stimSequence
        meanImage
        brightMaskScaled
        darkMaskScaled
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

            % Initial image: at t=0 cos=1 (positive), bright bars at bright peak, dark bars at dark trough
            Ap = obj.currentBrightContrast;
            An = abs(obj.currentDarkContrast);
            initImage = obj.meanImage + obj.brightMaskScaled * Ap + obj.darkMaskScaled * (-An);
            initialImage = uint8(max(0, min(255, round(initImage * 255))));
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

            % Asymmetric contrast-reversing grating:
            %
            % Start from a symmetric sinusoid s(t) = cos(2*pi*f*t), then
            % scale the positive half (above background) by brightBarContrast
            % and the negative half (below background) by |darkBarContrast|.
            % Both bars use the same asymmetric waveform, 180 deg out of phase,
            % so both cross through background at the zero-crossings.
            %
            % For bright bars (phase = 0, using s = cos):
            %   s >= 0: intensity = background * (1 + brightBarContrast * s)
            %   s <  0: intensity = background * (1 + |darkBarContrast| * s)
            %
            % For dark bars (phase = 180, using -s):
            %   s >= 0: intensity = background * (1 - |darkBarContrast| * s)
            %   s <  0: intensity = background * (1 - brightBarContrast * s)

            % Mean image: background everywhere
            obj.meanImage = obj.backgroundIntensity * ones(size(grating));

            % Pre-scaled masks: background intensity at bar pixels in annulus
            obj.brightMaskScaled = zeros(size(grating));
            obj.brightMaskScaled(brightBars & annulusMask) = obj.backgroundIntensity;

            obj.darkMaskScaled = zeros(size(grating));
            obj.darkMaskScaled(darkBars & annulusMask) = obj.backgroundIntensity;

            % Warn if peak modulation would produce out-of-range values
            peakHigh = obj.backgroundIntensity * (1 + obj.currentBrightContrast);
            peakLow  = obj.backgroundIntensity * (1 - abs(obj.currentDarkContrast));
            if peakHigh > 1 || peakLow < 0
                warning('Grating intensity out of range: bright peak = %.3f, dark peak = %.3f', ...
                    peakHigh, peakLow);
            end
        end

        function imgMat = getGratingFrame(obj, time)
            t = time - obj.preTime * 1e-3;  % time relative to stimulus onset
            s = cos(2 * pi * obj.currentTemporalFrequency * t);

            % For squarewave: snap to +1 or -1
            if strcmp(obj.temporalClass, 'squarewave')
                s = sign(s);
            end

            Ap = obj.currentBrightContrast;
            An = abs(obj.currentDarkContrast);

            % Asymmetric scaling: positive half scaled by Ap, negative half by An
            % Bright bars use cos (phase 0), dark bars use -cos (phase 180)
            if s >= 0
                imgMat = obj.meanImage ...
                       + obj.brightMaskScaled * (Ap * s) ...
                       + obj.darkMaskScaled * (-An * s);
            else
                imgMat = obj.meanImage ...
                       + obj.brightMaskScaled * (An * s) ...
                       + obj.darkMaskScaled * (-Ap * s);
            end

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
