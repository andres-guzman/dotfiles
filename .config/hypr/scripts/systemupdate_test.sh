#!/usr/bin/env bash

# This is a TEST VERSION of the Arch Linux update script.
# It simulates package update output and does NOT perform actual system updates.
# Use this script to test visual enhancements.

# Check if the system is Arch Linux
if [ ! -f /etc/arch-release ]; then
    echo "This script is intended for Arch Linux systems only."
    exit 0
fi

# Source variables from globalcontrol.sh
scrDir=$(dirname "$(realpath "$0")")
# shellcheck disable=SC1091
source "$scrDir/globalcontrol.sh"

# Ensure the AUR helper function is available
get_aurhlpr
export -f pkg_installed

# Define the temporary file for update information
temp_file="$HYDE_RUNTIME_DIR/update_info"

# Load existing update info if the file exists
# shellcheck source=/dev/null
[ -f "$temp_file" ] && source "$temp_file"

# ANSI color codes
COLOR_RESET='\033[0m'
COLOR_GREEN='\033[0;32m'
COLOR_RED='\033[0;31m'
COLOR_BLUE='\033[0;34m'
COLOR_YELLOW='\033[0;33m'
COLOR_CYAN='\033[0;36m'
COLOR_MAGENTA='\033[0;35m'
COLOR_BOLD='\033[1m'
COLOR_WHITE='\033[1;37m'
COLOR_ELECTRIC_BLUE='\033[38;2;0;191;255m'
COLOR_VIOLET_PURPLE='\033[38;2;142;114;255m'
COLOR_HOT_PINK='\033[38;2;228;89;198m'

# --- Trigger upgrade section ---
if [ "$1" == "up" ]; then
    if [ -f "$temp_file" ]; then
        # Refreshes the Waybar module after updates, resetting its display
        trap 'pkill -RTMIN+20 waybar' EXIT

        # Read official and AUR update counts from the temp file
        official=0
        aur=0
        while IFS="=" read -r key value; do
            case "$key" in
                OFFICIAL_UPDATES) official=$value ;;
                AUR_UPDATES) aur=$value ;;
            esac
        done <"$temp_file"

        # Construct the command string to be executed in kitty
        # This string includes the update process and the new formatted exit message
        command="
        cowsay -f /usr/share/cowsay/cows/bender.cow \"$(fortune)\"
        echo -e '\\n'

        echo -e \"${COLOR_ELECTRIC_BLUE}╭─────────────────────────────────────────────────────────────────────────────────────────╮${COLOR_RESET}\"
        echo -e \"${COLOR_ELECTRIC_BLUE}│ 󰉁   ARCH LINUX UPDATE SCRIPT (version 1.666)                                            │${COLOR_RESET}\"
        echo -e \"${COLOR_ELECTRIC_BLUE}│ 󰉁                                                                                       │${COLOR_RESET}\"
        echo -e \"${COLOR_ELECTRIC_BLUE}│ 󰉁   Available Updates:                                                                  │${COLOR_RESET}\"
        echo -e \"${COLOR_ELECTRIC_BLUE}╰─────────────────────────────────────────────────────────────────────────────────────────╯${COLOR_RESET}\\n\"

        
        echo -e \"${COLOR_ELECTRIC_BLUE}Official: ${COLOR_RESET}${COLOR_WHITE}$official${COLOR_RESET}\"
        echo -e \"${COLOR_ELECTRIC_BLUE}AUR: ${COLOR_RESET}${COLOR_WHITE}$aur${COLOR_RESET}\\n\"
        
        # Display pending official updates
        echo -e \"${COLOR_ELECTRIC_BLUE}Official packages to be updated:${COLOR_RESET}\"
        # --- MOCK checkupdates OUTPUT for testing ---
        echo -e \"${COLOR_ELECTRIC_BLUE}  core/bash 5.2.025-1 -> 5.2.026-1${COLOR_RESET}\"
        echo -e \"${COLOR_ELECTRIC_BLUE}  extra/neovim 0.9.1-1 -> 0.9.2-1${COLOR_RESET}\"
        echo -e \"${COLOR_ELECTRIC_BLUE}  community/kitty 0.31.0-1 -> 0.32.0-1${COLOR_RESET}\\n\"
        # --- END MOCK ---
        # echo -e \"\\n\" # Add newline after list if present

        # Display pending AUR updates
        echo -e \"${COLOR_ELECTRIC_BLUE}AUR packages to be updated:${COLOR_RESET}\"
        # --- MOCK AUR helper OUTPUT for testing ---
        echo -e \"${COLOR_ELECTRIC_BLUE}  aur/brave-bin 1.67.119-1 -> 1.68.120-1${COLOR_RESET}\"
        echo -e \"${COLOR_ELECTRIC_BLUE}  aur/visual-studio-code-bin 1.90.0-1 -> 1.90.1-1${COLOR_RESET}\"
        # --- END MOCK ---
        echo -e \"\\n\" # Add newline after list if present

        echo -e \"${COLOR_VIOLET_PURPLE}╭─────────────────────────────────────────────────────────────────────────────────────────╮${COLOR_RESET}\"
        echo -e \"${COLOR_VIOLET_PURPLE}│    Start the system update...                                                          │${COLOR_RESET}\"
        echo -e \"${COLOR_VIOLET_PURPLE}╰─────────────────────────────────────────────────────────────────────────────────────────╯${COLOR_RESET}\\n\"

        # Perform the actual system update (MOCKED for testing)
        # To simulate a SUCCESSFUL update, keep this section as is.
        # To simulate a FAILED update, comment out the success block below
        # and uncomment the error block.
        
        # --- MOCK Successful Update Output ---
        echo -e \"${COLOR_VIOLET_PURPLE}:: Running post-transaction hooks...\"
        echo -e \"${COLOR_VIOLET_PURPLE}(1/1) Arming ConditionNeedsUpdate...${COLOR_RESET}\"
        echo -e \"${COLOR_VIOLET_PURPLE}:: Synchronizing package databases...${COLOR_RESET}\"
        echo -e \"${COLOR_VIOLET_PURPLE}:: Starting full system upgrade...${COLOR_RESET}\"
        echo -e \"${COLOR_VIOLET_PURPLE}:: Resolving dependencies...${COLOR_RESET}\"
        echo -e \"${COLOR_VIOLET_PURPLE}:: Looking for conflicting packages...${COLOR_RESET}\"
        echo -e \"${COLOR_VIOLET_PURPLE}:: No updates found for core/bash${COLOR_RESET}\"
        echo -e \"${COLOR_VIOLET_PURPLE}:: Package sync and upgrade complete!${COLOR_RESET}\"
        # echo -e \"\\n${COLOR_GREEN}╭───────────────────────────╮${COLOR_RESET}\"
        # echo -e \"${COLOR_GREEN}│  System Update Completed  │${COLOR_RESET}\"
        # echo -e \"${COLOR_GREEN}╰───────────────────────────╯${COLOR_RESET}\\n\"
        # --- END MOCK Successful Update Output ---

        # --- MOCK Failed Update Output (uncomment to test failure) ---
        # echo -e \"\\n${COLOR_RED}╭────────────────────────────────────────────╮${COLOR_RESET}\"
        # echo -e \"${COLOR_RED}│   Error: Update Failed                        │${COLOR_RESET}\"
        # echo -e \"${COLOR_RED}│   Please check the output below for details   │${COLOR_RESET}\"
        # echo -e \"${COLOR_RED}╰───────────────────────────────────────────────╯${COLOR_RESET}\\n\"
        # echo -e \"${COLOR_RED}error: failed to prepare transaction (could not satisfy dependencies)${COLOR_RESET}\"
        # echo -e \"${COLOR_RED}error: failed to commit transaction (conflicting files)${COLOR_RESET}\"
        # --- END MOCK Failed Update Output ---

        # Original update logic (commented out for this test script)
        # if ! ${aurhlpr} -Syu; then
        #     echo -e \"${COLOR_RED}╭──────────────────────╮${COLOR_RESET}\"
        #     echo -e \"${COLOR_RED}│  Error: Update Failed  │${COLOR_RESET}\"
        #     echo -e \"${COLOR_RED}│  Please check the output above for details. │${COLOR_RESET}\"
        #     echo -e \"${COLOR_RED}╰─────────────────────────╯${COLOR_RESET}\\n\"
        # else
        #     echo -e \"\\n${COLOR_GREEN}╭───────────────────────────────────────╮${COLOR_RESET}\"
        #     echo -e \"${COLOR_GREEN}│         System Update Completed         │${COLOR_RESET}\"
        #     echo -e \"${COLOR_GREEN}╰───────────────────────────────────────╯${COLOR_RESET}\\n\"
        # fi

        # --- MOCK Failed Update Output (uncomment to test failure) ---
        echo -e '\\n'

        echo -e \"${COLOR_HOT_PINK}error: failed to prepare transaction (could not satisfy dependencies)${COLOR_RESET}\"
        echo -e \"${COLOR_HOT_PINK}error: failed to commit transaction (conflicting files)${COLOR_RESET}\"
        echo -e '\\n'
        echo -e \"${COLOR_HOT_PINK}╭─────────────────────────────────────────────────────────────────────────────────────────╮${COLOR_RESET}\"
        echo -e \"${COLOR_HOT_PINK}│    UPDATE FAILED                                                                       │${COLOR_RESET}\"
        echo -e \"${COLOR_HOT_PINK}│    Please see the output above for details                                             │${COLOR_RESET}\"
        echo -e \"${COLOR_HOT_PINK}╰─────────────────────────────────────────────────────────────────────────────────────────╯${COLOR_RESET}\\n\"
        # --- END MOCK Failed Update Output ---

        echo -e \"${COLOR_MAGENTA}╭─────────────────────────────────────────────────────────────────────────────────────────╮${COLOR_RESET}\"
        echo -e \"${COLOR_MAGENTA}│    System Update Completed                                                             │${COLOR_RESET}\"
        echo -e \"${COLOR_MAGENTA}╰─────────────────────────────────────────────────────────────────────────────────────────╯${COLOR_RESET}\\n\"
        # read -n 1 -s # -s flag to prevent input characters from being shown

        echo -e \"Press any key to exit...\\n\"
        read -n 1 -s # -s flag to prevent input characters from being shown
        "
        # Execute the command in a new kitty terminal
        kitty --title systemupdate sh -c "${command}"
    else
        echo "No upgrade info found. Please run the script without parameters first to check for updates."
    fi
    exit 0
fi

# --- Check for updates section (when no 'up' parameter is given) ---

# Mock the update counts for testing purposes
# You can change these values to simulate different update scenarios
aur_updates_count=2    # Simulate 2 AUR updates
official_updates_count=3 # Simulate 3 official updates

# Note: The actual 'checkupdates' and AUR helper commands are NOT run in this test script
# during the initial check. This is solely for testing visual output.

# Calculate total available updates (based on mocked values)
upd=$((official_updates_count + aur_updates_count))

# Prepare the upgrade info to be saved (using mocked values)
upgrade_info=$(
    cat <<EOF
OFFICIAL_UPDATES=$official_updates_count
AUR_UPDATES=$aur_updates_count
EOF
)

# Save the upgrade info to the temporary file
echo "$upgrade_info" > "$temp_file"

# Show tooltip for Waybar based on update status
if [ "$upd" -eq 0 ]; then
    upd=""  # Remove icon completely if no updates
    # upd="󰮯"  # Uncomment to show icon even with 0 updates
    echo "{\"text\":\"$upd\", \"tooltip\":\" Packages are up to date\"}"
else
    echo "{\"text\":\" SYSTEM UPDATES $upd<span color='#cdd6f473'>    </span>\", \"tooltip\":\"Official $official_updates_count\nAUR $aur_updates_count\"}"
fi