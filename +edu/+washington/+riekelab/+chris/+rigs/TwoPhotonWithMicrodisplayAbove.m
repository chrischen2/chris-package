classdef TwoPhotonWithMicrodisplayAbove < edu.washington.riekelab.rigs.TwoPhoton
    
    methods
        
        function obj = TwoPhotonWithMicrodisplayAbove()
            import symphonyui.builtin.devices.*;
            import symphonyui.core.*;
            import edu.washington.*;
            
            daq = obj.daqController;
            
            ramps = containers.Map();
            ramps('minimum') = linspace(0, 65535, 256);
            ramps('low')     = 65535 * importdata(riekelab.Package.getCalibrationResource('rigs', 'two_photon', 'microdisplay_above_low_gamma_ramp.txt'));
            ramps('medium')  = 65535 * importdata(riekelab.Package.getCalibrationResource('rigs', 'two_photon', 'microdisplay_above_medium_gamma_ramp.txt'));
            ramps('high')    = 65535 * importdata(riekelab.Package.getCalibrationResource('rigs', 'two_photon', 'microdisplay_above_high_gamma_ramp.txt'));
            ramps('maximum') = linspace(0, 65535, 256);
            microdisplay = riekelab.devices.MicrodisplayDevice('gammaRamps', ramps, 'micronsPerPixel', 1.1, 'comPort', 'COM3');
            microdisplay.bindStream(daq.getStream('doport1'));
            daq.getStream('doport1').setBitPosition(microdisplay, 15);
            microdisplay.addConfigurationSetting('ndfs', {}, ...
                'type', PropertyType('cellstr', 'row', {'B1', 'B2', 'B3', 'B4', 'B12', 'B13'}));
            microdisplay.addResource('ndfAttenuations', containers.Map( ...
                {'white', 'red', 'green', 'blue'}, { ...
                containers.Map( ...
                    {'B1', 'B2', 'B3', 'B4', 'B12', 'B13'}, ...
                    {0.26, 0.60, 0.98, 2.21, 0.27, 1.03}), ...
                containers.Map( ...
                    {'B1', 'B2', 'B3', 'B4', 'B12', 'B13'}, ...
                    {0.26, 0.60, 0.97, 2.09, 0.27, 1.01}), ...
                containers.Map( ...
                    {'B1', 'B2', 'B3', 'B4', 'B12', 'B13'}, ...
                    {0.26, 0.61, 0.98, 2.22, 0.27, 1.03}), ...
                containers.Map( ...
                    {'B1', 'B2', 'B3', 'B4', 'B12', 'B13'}, ...
                    {0.26, 0.60, 0.97, 2.24, 0.27, 1.04})}));
            microdisplay.addResource('fluxFactorPaths', containers.Map( ...
                {'low', 'medium', 'high'}, { ...
                riekelab.Package.getCalibrationResource('rigs', 'two_photon', 'microdisplay_above_low_flux_factors.txt'), ...
                riekelab.Package.getCalibrationResource('rigs', 'two_photon', 'microdisplay_above_medium_flux_factors.txt'), ...
                riekelab.Package.getCalibrationResource('rigs', 'two_photon', 'microdisplay_above_high_flux_factors.txt')}));
            microdisplay.addConfigurationSetting('lightPath', 'above', 'isReadOnly', true);
            microdisplay.addResource('spectrum', containers.Map( ...
                {'white', 'red', 'green', 'blue'}, { ...
                importdata(riekelab.Package.getCalibrationResource('rigs', 'two_photon', 'microdisplay_above_white_spectrum.txt')), ...
                importdata(riekelab.Package.getCalibrationResource('rigs', 'two_photon', 'microdisplay_above_red_spectrum.txt')), ...
                importdata(riekelab.Package.getCalibrationResource('rigs', 'two_photon', 'microdisplay_above_green_spectrum.txt')), ...
                importdata(riekelab.Package.getCalibrationResource('rigs', 'two_photon', 'microdisplay_above_blue_spectrum.txt'))}));
            obj.addDevice(microdisplay);
            
            frameMonitor = UnitConvertingDevice('Frame Monitor', 'V').bindStream(daq.getStream('ai7'));
            obj.addDevice(frameMonitor);
        end
        
    end
    
end
