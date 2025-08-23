#!/bin/bash

# Function to launch an application only if it's not already running
launch_if_not_running() {
    local app_name="$1"
    # Check if the process is already running
    if ! pgrep -x "$app_name" > /dev/null; then
        # If not, launch the application
        "$app_name" &
    fi
}

# Use the function for each of your applications
launch_if_not_running "nicotine"
sleep 0.5
launch_if_not_running "qbittorrent"
sleep 0.5
launch_if_not_running "amule"