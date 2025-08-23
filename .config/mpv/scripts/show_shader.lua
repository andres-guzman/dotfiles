-- This script will show the current shader being used in the terminal
mp.add_key_binding("Ctrl+i", "show-shader", function()
    local shaders = mp.get_property_native("glsl-shaders")
    if shaders then
        print("Current Shader: " .. shaders)
    else
        print("No shaders applied.")
    end
end)
