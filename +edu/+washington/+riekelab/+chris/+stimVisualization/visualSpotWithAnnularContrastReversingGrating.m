%% Verify spotWithAnnularContrastReversingGrating — piecewise asymmetric sinusoid
clear; close all; clc;

%% Parameters
backgroundIntensity = 0.15;
spotIntensity = 0.05;
brightBarContrast = 0.1;    % Ap: scales positive half of sinusoid
darkBarContrast = -0.8;    % An = abs(-0.75): scales negative half
temporalFrequency = 2;      % Hz

apertureDiameter = 300;
annulusInnerDiameter = 400;
annulusOuterDiameter = 800;
barWidth = 60;

preTime = 500;   % ms
stimTime = 2000; % ms
tailTime = 500;  % ms

canvasSize = [800 800];
fps = 60;
totalTime = (preTime + stimTime + tailTime) / 1e3;
dt = 1/fps;
timeVec = 0:dt:totalTime;

Ap = brightBarContrast;
An = abs(darkBarContrast);

%% Build spatial pattern
barWidthPix = barWidth;
innerRadPix = annulusInnerDiameter / 2;
outerRadPix = annulusOuterDiameter / 2;
spotRadPix  = apertureDiameter / 2;

[x, y] = meshgrid(linspace(-canvasSize(1)/2, canvasSize(1)/2, canvasSize(1)), ...
                   linspace(-canvasSize(2)/2, canvasSize(2)/2, canvasSize(2)));
r = sqrt(x.^2 + y.^2);

grating = sign(sin(2*pi*x / barWidthPix));
brightBars = (grating > 0);
darkBars   = (grating <= 0);
annulusMask = (r >= innerRadPix) & (r <= outerRadPix);
spotMask    = (r <= spotRadPix);

% Pre-compute matrices
meanImage = backgroundIntensity * ones(canvasSize);

brightMaskScaled = zeros(canvasSize);
brightMaskScaled(brightBars & annulusMask) = backgroundIntensity;

darkMaskScaled = zeros(canvasSize);
darkMaskScaled(darkBars & annulusMask) = backgroundIntensity;

%% Compute temporal traces using the asymmetric waveform
brightTrace = zeros(size(timeVec));
darkTrace   = zeros(size(timeVec));

for i = 1:length(timeVec)
    t = timeVec(i) - preTime * 1e-3;
    inStim = (timeVec(i) >= preTime*1e-3) && (timeVec(i) < (preTime+stimTime)*1e-3);

    if inStim
        s = cos(2 * pi * temporalFrequency * t);
        % Asymmetric waveform: scale positive half by Ap, negative half by An
        if s >= 0
            brightTrace(i) = backgroundIntensity * (1 + Ap * s);
            darkTrace(i)   = backgroundIntensity * (1 - An * s);
        else
            brightTrace(i) = backgroundIntensity * (1 + An * s);  % s<0, goes below bg
            darkTrace(i)   = backgroundIntensity * (1 - Ap * s);  % -s>0, goes above bg
        end
    else
        brightTrace(i) = backgroundIntensity;
        darkTrace(i)   = backgroundIntensity;
    end
end

%% Animate
fig = figure('Position', [100 100 1200 800], 'Color', 'w');

for i = 1:length(timeVec)
    t = timeVec(i) - preTime * 1e-3;
    inStim = (timeVec(i) >= preTime*1e-3) && (timeVec(i) < (preTime+stimTime)*1e-3);

    % --- Compute current frame ---
    if inStim
        s = cos(2 * pi * temporalFrequency * t);
        if s >= 0
            frame = meanImage ...
                  + brightMaskScaled * (Ap * s) ...
                  + darkMaskScaled * (-An * s);
        else
            frame = meanImage ...
                  + brightMaskScaled * (An * s) ...
                  + darkMaskScaled * (-Ap * s);
        end
        frame(spotMask) = spotIntensity;
    else
        frame = backgroundIntensity * ones(canvasSize);
    end
    frame = max(0, min(1, frame));

    % --- Subplot 1: Full frame ---
    subplot(2, 2, 1);
    imagesc(frame, [0 0.4]);
    colormap(gray); axis image off;
    title(sprintf('Full frame  t = %.3f s', timeVec(i)));

    % --- Subplot 2: Zoomed annulus ---
    subplot(2, 2, 2);
    cropRange = round(canvasSize(1)/2) + (-outerRadPix:outerRadPix);
    cropRange = max(1, min(canvasSize(1), cropRange));
    imagesc(frame(cropRange, cropRange), [0 0.4]);
    colormap(gray); axis image off;
    title('Zoomed annulus');

    % --- Subplot 3: Bright bar trace ---
    subplot(2, 2, 3);
    plot(timeVec(1:i), brightTrace(1:i), 'r-', 'LineWidth', 2); hold on;
    plot(timeVec(i), brightTrace(i), 'ro', 'MarkerSize', 10, 'MarkerFaceColor', 'r');
    yline(backgroundIntensity, 'k--', 'background');
    hold off;
    xlim([0 totalTime]); ylim([0 0.4]);
    xlabel('Time (s)'); ylabel('Intensity');
    title(sprintf('Bright bar (Ap=%.2f, An=%.2f)', Ap, An));
    xline(preTime*1e-3, 'g--'); xline((preTime+stimTime)*1e-3, 'g--');

    % --- Subplot 4: Dark bar trace ---
    subplot(2, 2, 4);
    plot(timeVec(1:i), darkTrace(1:i), 'b-', 'LineWidth', 2); hold on;
    plot(timeVec(i), darkTrace(i), 'bo', 'MarkerSize', 10, 'MarkerFaceColor', 'b');
    yline(backgroundIntensity, 'k--', 'background');
    hold off;
    xlim([0 totalTime]); ylim([0 0.4]);
    xlabel('Time (s)'); ylabel('Intensity');
    title(sprintf('Dark bar (180° out of phase)', An, Ap));
    xline(preTime*1e-3, 'g--'); xline((preTime+stimTime)*1e-3, 'g--');

    drawnow;
end

%% Overlay plot
figure('Position', [200 200 800 400], 'Color', 'w');
plot(timeVec, brightTrace, 'r-', 'LineWidth', 2); hold on;
plot(timeVec, darkTrace, 'b-', 'LineWidth', 2);
yline(backgroundIntensity, 'k--', 'background');
xline(preTime*1e-3, 'g--', 'stim on');
xline((preTime+stimTime)*1e-3, 'g--', 'stim off');
xlabel('Time (s)'); ylabel('Intensity');
title('Bright (red) vs Dark (blue) — asymmetric sinusoid, 180° out of phase');
legend('Bright bar', 'Dark bar', 'Location', 'best');
ylim([0 0.4]); hold off;

fprintf('\n--- Verification ---\n');
fprintf('Ap (brightBarContrast) = %.2f\n', Ap);
fprintf('An (|darkBarContrast|) = %.2f\n', An);
fprintf('Background = %.3f\n', backgroundIntensity);
fprintf('Bright peak = %.4f, Dark trough = %.4f\n', ...
    backgroundIntensity*(1+Ap), backgroundIntensity*(1-An));
fprintf('Both bars cross through background at every zero-crossing.\n');
fprintf('Positive excursion scaled by Ap=%.2f, negative excursion scaled by An=%.2f\n', Ap, An);
