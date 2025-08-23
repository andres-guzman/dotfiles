#!/bin/bash

# A list of applications to exclude from the kill command
# Add your terminal, bar, and any other apps you want to keep open
exclude_list=('waybar' 'hyprland' 'dunst' 'nm-applet' 'blueman-applet' 'xdg-desktop-portal-hyprland' 'hyde-shell' 'wl-paste' 'wl-clip-persist' 'udiskie' 'kitty' 'mpvpaper' 'rclone')

# Get the PIDs of all open windows
pids=$(hyprctl clients -j | jq -r '.[].pid')

# Loop through each PID and check if its associated app should be excluded
for pid in $pids; do
    # Get the process name from the PID
    app_name=$(ps -p $pid -o comm=)

    # Check if the app_name is in our exclude list
    is_excluded=false
    for exclude_app in "${exclude_list[@]}"; do
        if [[ "$app_name" == "$exclude_app" ]]; then
            is_excluded=true
            break
        fi
    done

    # If the app is not in the exclude list, kill it gracefully
    if [[ "$is_excluded" == "false" ]]; then
        kill -SIGTERM $pid
    fi
done