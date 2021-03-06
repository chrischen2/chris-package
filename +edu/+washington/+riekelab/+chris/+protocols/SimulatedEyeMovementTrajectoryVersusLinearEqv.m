classdef SimulatedEyeMovementTrajectoryVersusLinearEqv < edu.washington.riekelab.protocols.RiekeLabStageProtocol
    
    properties
        preTime = 200 % ms
        stimTime = 2000 % ms
        tailTime = 200 % ms
        imageName = '00152' %van hateren image names
        apertureDiameter = 400 % um
        randomSeed = 1 % for eye movement trajectory
        D = 5; % Drift diffusion coefficient, in microns
        onlineAnalysis = 'none'
        meanIntensity=[0.1 0.5];
        numberOfAverages = uint16(5) % number of epochs to queue
        amp % Output amplifier
        linearIntegrationFunction = 'gaussian'    
        patchMean='positive'
        contrastScale=0.7
    end
    
    properties (Hidden)
        ampType
        imageNameType = symphonyui.core.PropertyType('char', 'row', {'00152','00377','00459','00657','01151','01154',...
            '01192','01769','01829','02265','02281','02733','02999','03093',...
            '03347','03447','03584','03758','03760'})
        patchMeanType = symphonyui.core.PropertyType('char', 'row', {'all','negative','positive'})
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'exc', 'inh'})
        backgroundIntensity
        imageMatrix
        currentStimSet
        currentImageSet
        xTraj
        yTraj
        timeTraj
        p0
        xTraj_save
        yTraj_save
        screenSize
        linearIntegrationFunctionType = symphonyui.core.PropertyType('char', 'row', {'gaussian','uniform'})
        eqvLum
        epochIndex
    end
    
    methods
        
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            obj.showFigure('edu.washington.riekelab.chris.figures.MeanResponseFigure',...
                obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis);
            obj.showFigure('edu.washington.riekelab.chris.figures.FrameTimingFigure',...
                obj.rig.getDevice('Stage'), obj.rig.getDevice('Frame Monitor'));
            obj.screenSize = obj.rig.getDevice('Stage').getConfigurationSetting('micronsPerPixel') .* ...
                obj.rig.getDevice('Stage').getCanvasSize(); %microns
            % get current image and stim (library) set:
            resourcesDir = 'C:\Users\Fred Rieke\Documents\chris-package\+edu\+washington\+riekelab\+chris\+resources\';
            obj.currentImageSet = '\VHsubsample_20160105';
            obj.currentStimSet = 'SaccadeLocationsLibrary_20171011';
            load([resourcesDir,obj.currentStimSet,'.mat']);
            fieldName = ['imk', obj.imageName];
            
            %load appropriate image...
            obj.currentStimSet = '\VHsubsample_20160105';
            fileId=fopen([resourcesDir, obj.currentImageSet, '\imk', obj.imageName,'.iml'],'rb','ieee-be');
            img = fread(fileId, [1536,1024], 'uint16');
            img = double(img');
            img = (img./max(img(:))); %rescale s.t. brightest point is maximum monitor level
            img=(img-mean(img(:)))/mean(img(:)); % contrast image
            img=obj.contrastScale*img*obj.meanIntensity(1)+ obj.meanIntensity(1);
            img=img*255;
            obj.imageMatrix.low=img;
            img=(img-mean(img(:)))/mean(img(:)); % contrast image
            img=obj.contrastScale*img*obj.meanIntensity(2)+ obj.meanIntensity(2);
            img=img*255;
            obj.imageMatrix.high=img;
            obj.imageMatrix.low(obj.imageMatrix.low<0)=0;
            obj.imageMatrix.low(obj.imageMatrix.low>255)=255;
            obj.imageMatrix.high(obj.imageMatrix.high<0)=0;
            obj.imageMatrix.high(obj.imageMatrix.high>255)=255;
            obj.imageMatrix.low = uint8(img);  obj.imageMatrix.high = uint8(img);
            %1) restrict to desired patch mean luminance:
            imageMean = imageData.(fieldName).imageMean;
            obj.backgroundIntensity = imageMean;%set the mean to the mean over the image
            locationMean = imageData.(fieldName).patchMean;
            if strcmp(obj.patchMean,'all')
                inds = 1:length(locationMean);
            elseif strcmp(obj.patchMean,'positive')
                inds = find((locationMean-imageMean) > 0);
            elseif strcmp(obj.patchMean,'negative')
                inds = find((locationMean-imageMean) <= 0);
            end
            rng(obj.randomSeed); %set random seed for fixation draw
            drawInd = randsample(inds,1);
            obj.p0(1) = imageData.(fieldName).location(drawInd,1);
            obj.p0(2) = imageData.(fieldName).location(drawInd,2);
            
            %size of the stimulus on the prep:
            %scalingFactor: 3.3 for 1 arcmin/VH pixel (like DOVES), based
            %on 198 um/degree on monkey retina
            
            % make eye movement trajectory.
            rng(obj.randomSeed); %set random seed for fixation draw
            noFrames = obj.rig.getDevice('Stage').getMonitorRefreshRate() * (obj.stimTime/1e3);
            
            %generate random walk out
            tempX_1 = obj.D .* randn(1,round(noFrames/2));
            tempY_1 = obj.D .* randn(1,round(noFrames/2));
            %hold off first step to subtract later
            tempX_1_a = tempX_1(2:end);
            tempY_1_b = tempY_1(2:end);
            %randomize walk back
            tempX_2 = [-tempX_1_a(randperm(length(tempX_1_a))), -tempX_1(1)];
            tempY_2 = [-tempY_1_b(randperm(length(tempY_1_b))), -tempY_1(1)];
            
            %cumulative sum, flip to start at 0
            obj.xTraj = fliplr(cumsum([tempX_1, tempX_2]));
            obj.yTraj = fliplr(cumsum([tempY_1, tempY_2]));
            
            
            
            obj.xTraj_save = obj.xTraj; %still in VH coordinates
            obj.yTraj_save = obj.yTraj;
            
            obj.timeTraj = (0:(length(obj.xTraj)-1)) ./...
                obj.rig.getDevice('Stage').getMonitorRefreshRate(); %sec
            
            %need to make eye trajectories for PRESENTATION relative to the center of the image and
            %flip them across the x axis: to shift scene right, move
            %position left, same for y axis
            obj.xTraj = -(obj.xTraj); %units=VH pixels
            obj.yTraj = -(obj.yTraj);
            %also scale them to canvas pixels
            %canvasPix = (um) / (um/canvasPix)
            obj.xTraj = obj.xTraj ./obj.rig.getDevice('Stage').getConfigurationSetting('micronsPerPixel');
            obj.yTraj = obj.yTraj ./obj.rig.getDevice('Stage').getConfigurationSetting('micronsPerPixel');
            apertureDiameterPix= obj.rig.getDevice('Stage').um2pix(obj.apertureDiameter);
             
            obj.eqvLum.low=obj.getEquivalentIntensityValues(obj.imageMatrix.low,apertureDiameterPix,60);
            obj.eqvLum.high=obj.getEquivalentIntensityValues(obj.imageMatrix.high,apertureDiameterPix,60);

        end
        
        
        function p = createPresentation(obj)
            canvasSize = obj.rig.getDevice('Stage').getCanvasSize();
            apertureDiameterPix = obj.rig.getDevice('Stage').um2pix(obj.apertureDiameter);
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.meanIntensity(1));
            if obj.epochIndex<3
                if obj.epochIndex==1
                    scene = stage.builtin.stimuli.Image(obj.imageMatrix.low);
                else
                    scene = stage.builtin.stimuli.Image(obj.imageMatrix.high);
                end
                %scale up image for canvas. Now image pixels and canvas pixels
                %are the same size. Also image size is in rows (y), cols (x)
                %but stage sizes are in x, y
                %canvasPix = (VHpix) * (um/VHpix)/(um/canvasPix)
                scene.size = [size(obj.imageMatrix.low,2) * (3.3)/obj.rig.getDevice('Stage').getConfigurationSetting('micronsPerPixel'),...
                    size(obj.imageMatrix.high,1) * (3.3)/obj.rig.getDevice('Stage').getConfigurationSetting('micronsPerPixel')];
                
                tempY = obj.p0(2); %swap row/column for y/x
                tempX = obj.p0(1);
                %translate about center, shift to (0,0)
                translatedX = -(tempX - 1536/2);
                translatedY = (tempY - 1024/2);
                translatedLocation = [translatedX, translatedY];
                %scale to canvas pixels
                translatedLocation = translatedLocation .* (3.3)/obj.rig.getDevice('Stage').getConfigurationSetting('micronsPerPixel');
                %re-center on canvas center
                translatedLocation = canvasSize/2 + translatedLocation;
                scene.position = translatedLocation;
                
                % Use linear interpolation when scaling the image.
                scene.setMinFunction(GL.LINEAR);
                scene.setMagFunction(GL.LINEAR);
                
                %apply eye trajectories to move image around
                scenePosition = stage.builtin.controllers.PropertyController(scene,...
                    'position', @(state)getScenePosition(obj, state.time - obj.preTime/1e3, translatedLocation));
                
                
                p.addStimulus(scene);
                p.addController(scenePosition);
                
                sceneVisible = stage.builtin.controllers.PropertyController(scene, 'visible', ...
                    @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
                p.addController(sceneVisible);
            else
               
                if obj.epochIndex==3
                    currentEqvLum=obj.eqvLum.low;
                else
                    currentEqvLum=obj.eqvLum.high;
                end
                 currentEqvLum
                spotDiameterPix = apertureDiameterPix;
                spot = stage.builtin.stimuli.Ellipse();
                spot.radiusX = spotDiameterPix/2;
                spot.radiusY = spotDiameterPix/2;
                spot.position = canvasSize/2;
                p.addStimulus(spot);
                spotMean = stage.builtin.controllers.PropertyController(spot, 'color',...
                    @(state)getSpotMean(obj, state.time-obj.preTime,currentEqvLum));
                p.addController(spotMean); %add the controller

                % make sure turns off at end
                spotVisible = stage.builtin.controllers.PropertyController(spot, 'visible', ...
                    @(state)state.time < (obj.preTime + obj.stimTime + obj.tailTime - 50) * 1e-3);
                p.addController(spotVisible);
    
            end
            if (obj.apertureDiameter > 0) %% Create aperture
                aperture = stage.builtin.stimuli.Rectangle();
                aperture.position = canvasSize/2;
                aperture.color = obj.backgroundIntensity;
                aperture.size = 2.*[max(canvasSize) max(canvasSize)];
                mask = stage.core.Mask.createCircularAperture(apertureDiameterPix/(2*max(canvasSize)), 1024); %circular aperture
                aperture.setMask(mask);
                p.addStimulus(aperture); %add aperture
            end
            function p = getScenePosition(obj, time, p0)
                if time < 0
                    p = p0;
                elseif time > obj.timeTraj(end) %out of eye trajectory, hang on last frame
                    p(1) = p0(1) + obj.xTraj(end);
                    p(2) = p0(2) + obj.yTraj(end);
                else %within eye trajectory and stim time
                    dx = interp1(obj.timeTraj,obj.xTraj,time);
                    dy = interp1(obj.timeTraj,obj.yTraj,time);
                    p(1) = p0(1) + dx;
                    p(2) = p0(2) + dy;
                end
            end

            function m = getSpotMean(obj, time,currentEqvLum)
                if time<0
                    if obj.epochIndex==3
                        m=obj.meanIntensity(1);
                    else
                        m=obj.meanIntensity(2);
                    end
                else
                    m=interp1(obj.timeTraj,currentEqvLum,time);
                end
            end

        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj, epoch);
            
            device = obj.rig.getDevice(obj.amp);
            duration = (obj.preTime + obj.stimTime + obj.tailTime) / 1e3;
            obj.epochIndex=mod(obj.numEpochsPrepared,numel(obj.meanIntensity)*2);
            if obj.epochIndex==0
                obj.epochIndex=numel(obj.meanIntensity)*2;
            end          
            epoch.addDirectCurrentStimulus(device, device.background, duration, obj.sampleRate);
            epoch.addResponse(device);

            epoch.addParameter('randomSeed', obj.randomSeed);
            epoch.addParameter('currentStimSet',obj.currentStimSet);
            epoch.addParameter('currentImageSet',obj.currentImageSet);
            epoch.addParameter('xTraj',obj.xTraj_save);
            epoch.addParameter('yTraj',obj.yTraj_save);
            epoch.addParameter('epochIndex',obj.epochIndex);
        end
        
            
        function allEquivalentContrastValues =  getEquivalentIntensityValues(obj,imageMat,apertureDiameter,RFsigma)
            %outerDiameter is circle in which to integrate. innerDiameter
            %is the size of a circle to mask off before integration.
            %e.g. center RF (Linear equivalent disc): innerDiameter = 0
            %   surround RF (Linear equivalent annulus): innerDiameter > 0
            stimSize_VHpix = obj.screenSize ./ (6.6); %um / (um/pixel) -> pixel
            radX = floor(stimSize_VHpix(1) / 2); %boundaries for fixation draws depend on stimulus size
            radY = floor(stimSize_VHpix(2) / 2);
            % Get the model RF:
            RFsigma = RFsigma ./ 6.6; %microns -> VH pixels
            RF = fspecial('gaussian',2.*[radX radY],RFsigma);
            
            % Get the aperture to apply to the image...
            %   set to 1 = values to be included (i.e. image is shown there)
            [rr, cc] = meshgrid(1:(2*radX),1:(2*radY));
            apertureMatrix = sqrt((rr-radX).^2 + ...
                (cc-radY).^2) < (apertureDiameter/2) ./ 6.6;
            apertureMatrix = apertureMatrix';
        
            if strcmp(obj.linearIntegrationFunction,'gaussian')
                weightingFxn = apertureMatrix .* RF; %set to zero mean gray pixels
            elseif strcmp(obj.linearIntegrationFunction,'uniform')
                weightingFxn = apertureMatrix;
            end
            weightingFxn = weightingFxn ./ sum(weightingFxn(:)); %sum to one
            
            allEquivalentContrastValues = zeros(1,numel(obj.xTraj_save));
            for ff = 1:numel(obj.xTraj_save)
                tempPatch = imageMat(round(obj.xTraj_save(ff)+obj.p0(1)-radX)+1:round(obj.xTraj_save(ff)+obj.p0(1)+radX),...
                    round(obj.yTraj_save(ff)+obj.p0(2)-radY)+1:round(obj.yTraj_save(ff)+obj.p0(2)+radY));
                allEquivalentContrastValues(ff) = sum(sum(weightingFxn .* double(tempPatch)));
            end 
        end      
      

        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages*numel(obj.meanIntensity)*2;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages*numel(obj.meanIntensity)*2;
        end
        
    end

    
end