-- List of shaders to cycle through
local shaders = {
    "/home/andres/.config/mpv/shaders/blurGauss_pass2.hlsl",
    "/home/andres/.config/mpv/shaders/NoChroma.hook",
    "/home/andres/.config/mpv/shaders/adaptive-sharpen.glsl",
    "/home/andres/.config/mpv/shaders/Anime4K_AutoDownscalePre_x2.glsl",
    "/home/andres/.config/mpv/shaders/Anime4K_AutoDownscalePre_x4.glsl",
    "/home/andres/.config/mpv/shaders/Anime4K_Clamp_Highlights.glsl",
    "/home/andres/.config/mpv/shaders/Anime4K_Darken_Fast.glsl",
    "/home/andres/.config/mpv/shaders/Anime4K_Darken_HQ.glsl",
    "/home/andres/.config/mpv/shaders/Anime4K_Darken_VeryFast.glsl",
    "/home/andres/.config/mpv/shaders/Anime4K_Deblur_DoG.glsl",
    "/home/andres/.config/mpv/shaders/Anime4K_Deblur_Original.glsl",
    "/home/andres/.config/mpv/shaders/Anime4K_Denoise_Bilateral_Mean.glsl",
    "/home/andres/.config/mpv/shaders/Anime4K_Denoise_Bilateral_Median.glsl",
    "/home/andres/.config/mpv/shaders/Anime4K_Denoise_Bilateral_Mode.glsl",
    "/home/andres/.config/mpv/shaders/Anime4K_Restore_CNN_L.glsl",
    "/home/andres/.config/mpv/shaders/Anime4K_Restore_CNN_M.glsl",
    "/home/andres/.config/mpv/shaders/Anime4K_Restore_CNN_S.glsl",
    "/home/andres/.config/mpv/shaders/Anime4K_Restore_CNN_Soft_L.glsl",
    "/home/andres/.config/mpv/shaders/Anime4K_Restore_CNN_Soft_M.glsl",
    "/home/andres/.config/mpv/shaders/Anime4K_Restore_CNN_Soft_S.glsl",
    "/home/andres/.config/mpv/shaders/Anime4K_Restore_CNN_Soft_UL.glsl",
    "/home/andres/.config/mpv/shaders/Anime4K_Restore_CNN_Soft_VL.glsl",
    "/home/andres/.config/mpv/shaders/Anime4K_Restore_CNN_UL.glsl",
    "/home/andres/.config/mpv/shaders/Anime4K_Restore_CNN_VL.glsl",
    "/home/andres/.config/mpv/shaders/Anime4K_Thin_Fast.glsl",
    "/home/andres/.config/mpv/shaders/Anime4K_Thin_HQ.glsl",
    "/home/andres/.config/mpv/shaders/Anime4K_Thin_VeryFast.glsl",
    "/home/andres/.config/mpv/shaders/Anime4K_Upscale_CNN_x2_L.glsl",
    "/home/andres/.config/mpv/shaders/Anime4K_Upscale_CNN_x2_M.glsl",
    "/home/andres/.config/mpv/shaders/Anime4K_Upscale_CNN_x2_S.glsl",
    "/home/andres/.config/mpv/shaders/Anime4K_Upscale_CNN_x2_UL.glsl",
    "/home/andres/.config/mpv/shaders/Anime4K_Upscale_CNN_x2_VL.glsl",
    "/home/andres/.config/mpv/shaders/Anime4K_Upscale_Deblur_DoG_x2.glsl",
    "/home/andres/.config/mpv/shaders/Anime4K_Upscale_Deblur_Original_x2.glsl",
    "/home/andres/.config/mpv/shaders/Anime4K_Upscale_Denoise_CNN_x2_L.glsl",
    "/home/andres/.config/mpv/shaders/Anime4K_Upscale_Denoise_CNN_x2_M.glsl",
    "/home/andres/.config/mpv/shaders/Anime4K_Upscale_Denoise_CNN_x2_S.glsl",
    "/home/andres/.config/mpv/shaders/Anime4K_Upscale_Denoise_CNN_x2_UL.glsl",
    "/home/andres/.config/mpv/shaders/Anime4K_Upscale_Denoise_CNN_x2_VL.glsl",
    "/home/andres/.config/mpv/shaders/Anime4K_Upscale_DoG_x2.glsl",
    "/home/andres/.config/mpv/shaders/Anime4K_Upscale_DTD_x2.glsl",
    "/home/andres/.config/mpv/shaders/Anime4K_Upscale_Original_x2.glsl",
    "/home/andres/.config/mpv/shaders/ArtCNN_C4F16.glsl",
    "/home/andres/.config/mpv/shaders/ArtCNN_C4F32.glsl",
    "/home/andres/.config/mpv/shaders/CAS-scaled.glsl",
    "/home/andres/.config/mpv/shaders/CfL_Prediction.glsl",
    "/home/andres/.config/mpv/shaders/CfL_Prediction_Lite.glsl",
    "/home/andres/.config/mpv/shaders/filmgrain.glsl",
    "/home/andres/.config/mpv/shaders/FSRCNNX_x2_16-0-4-1.glsl",
    "/home/andres/.config/mpv/shaders/FSRCNNX_x2_8-0-4-1.glsl",
    "/home/andres/.config/mpv/shaders/FSR.glsl",
    "/home/andres/.config/mpv/shaders/KrigBilateral.glsl",
    "/home/andres/.config/mpv/shaders/nnedi3-nns128-win8x6.hook",
    "/home/andres/.config/mpv/shaders/nnedi3-nns16-win8x6.hook",
    "/home/andres/.config/mpv/shaders/nnedi3-nns256-win8x6.hook",
    "/home/andres/.config/mpv/shaders/nnedi3-nns32-win8x6.hook",
    "/home/andres/.config/mpv/shaders/nnedi3-nns64-win8x6.hook",
    "/home/andres/.config/mpv/shaders/noise_static_chroma.hook",
    "/home/andres/.config/mpv/shaders/noise_static_chroma_strong.hook",
    "/home/andres/.config/mpv/shaders/noise_static_luma.hook",
    "/home/andres/.config/mpv/shaders/noise_static_luma_strong.hook",
    "/home/andres/.config/mpv/shaders/NVScaler.glsl", -- Added this one found in ls output
    "/home/andres/.config/mpv/shaders/ravu-lite-ar-r4.hook",
    "/home/andres/.config/mpv/shaders/ravu-zoom-ar-r3.hook",
    "/home/andres/.config/mpv/shaders/SSimDownscaler.glsl",
    "/home/andres/.config/mpv/shaders/SSimSuperRes.glsl"
}

-- Variable to track the current shader index
local current_shader = 0  -- Start with no shader applied

-- Function to apply the current shader
function apply_shader()
    if current_shader == 0 then
        mp.set_property("glsl-shaders", "")  -- Remove all shaders
        mp.osd_message("No shader applied")
        print("Script: Cleared shaders.") -- Debug line
    else
        local shader = shaders[current_shader]
        -- Extract filename for cleaner OSD message
        local filename = shader:match("^.*/(.*)$") or shader
        mp.set_property("glsl-shaders", shader)
        mp.osd_message("Applying shader (" .. current_shader .. "/" .. #shaders .. "): " .. filename)
        print("Script: Applying shader: " .. shader) -- Debug line
    end
end

-- Function to cycle through shaders
function cycle_shaders()
    current_shader = current_shader + 1
    if current_shader > #shaders then
        current_shader = 0  -- Reset to "no shader" state
    end
    apply_shader()
end

-- Keybinding to cycle shaders with UP arrow
mp.add_key_binding("UP", "cycle_shaders", cycle_shaders)

-- Keybinding to show the current shader with Ctrl+i
mp.add_key_binding("Ctrl+i", "show_shader", function()
    if current_shader == 0 then
        mp.osd_message("Current shader: None")
        print("Script: Current shader: None") -- Debug line
    else
        local shader = shaders[current_shader]
        local filename = shader:match("^.*/(.*)$") or shader
        mp.osd_message("Current shader (" .. current_shader .. "/" .. #shaders .. "): " .. filename)
        print("Script: Current shader: " .. shader) -- Debug line
    end
end)

print("Script: cycle_shaders.lua loaded successfully.") -- Confirmation message