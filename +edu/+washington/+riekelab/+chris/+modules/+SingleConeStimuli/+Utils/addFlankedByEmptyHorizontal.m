function button = addFlankedByEmptyHorizontal(classType, parent, widths, varargin)
import appbox.*;
mainBox = uix.HBox( ...
    'Parent', parent);
uix.Empty( ...
    'Parent', mainBox);
button = classType( ...
    'Parent', mainBox, ...
    varargin{:});
uix.Empty( ...
    'Parent', mainBox);

mainBox.Widths = widths;
end