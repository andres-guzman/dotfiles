#!/usr/bin/env bash

# Working version of the Arch Linux update script.
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
COLOR_WHITE='\033[1;37m' # This is a bright white using standard ANSI
# True Color (24-bit RGB) definitions
COLOR_ELECTRIC_BLUE='\033[38;2;0;191;255m'
# Toned-down Violet Purple (R=177, G=118, B=255) - from #b176ff
COLOR_VIOLET_PURPLE='\033[38;2;177;118;255m'
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

        # IMPORTANT: Prepare the CHECKUPDATES_DB variable for use inside the 'command' string.
        # This ensures 'checkupdates' uses the correct temporary database path.
        temp_db_for_cmd=$(mktemp -u /tmp/checkupdates_db_XXXXXX)
        CHECKUPDATES_DB_CMD="CHECKUPDATES_DB=\"$temp_db_for_cmd\""
        # Ensure this temporary database is removed when the script exits
        trap '[ -f "$temp_db_for_cmd" ] && rm "$temp_db_for_cmd" 2>/dev/null' EXIT INT TERM

        # Construct the command string to be executed in kitty
        # This string includes the update process and the new formatted exit message
        command="
        cowsay -f /usr/share/cowsay/cows/bender.cow \"$(fortune)\"
        echo -e '\\n\\n'

        echo -e \"${COLOR_ELECTRIC_BLUE}╭─────────────────────────────────────────────────────────────────────────────────────────╮${COLOR_RESET}\"
        echo -e \"${COLOR_ELECTRIC_BLUE}│ 󰉁   ARCH LINUX UPDATE SCRIPT (version 1.666)                                            │${COLOR_RESET}\"
        echo -e \"${COLOR_ELECTRIC_BLUE}│ 󰉁                                                                                       │${COLOR_RESET}\"
        echo -e \"${COLOR_ELECTRIC_BLUE}│ 󰉁   Available Updates:                                                                  │${COLOR_RESET}\"
        echo -e \"${COLOR_ELECTRIC_BLUE}╰─────────────────────────────────────────────────────────────────────────────────────────╯${COLOR_RESET}\\n\"

        echo -e \"${COLOR_ELECTRIC_BLUE}Official: ${COLOR_RESET}${COLOR_WHITE}$official${COLOR_RESET}\"
        echo -e \"${COLOR_ELECTRIC_BLUE}AUR: ${COLOR_RESET}${COLOR_WHITE}$aur${COLOR_RESET}\\n\"
        
        # Display pending official updates
        echo -e \"${COLOR_ELECTRIC_BLUE}Official packages to be updated:${COLOR_RESET}\"
        # Capture and color the output of checkupdates
        OFFICIAL_PKG_LIST=\$(${CHECKUPDATES_DB_CMD} checkupdates 2>/dev/null)
        if [ -z \"\$OFFICIAL_PKG_LIST\" ]; then # Check if output is empty
            echo -e \"${COLOR_ELECTRIC_BLUE}No official updates pending.${COLOR_RESET}\\n\"
        else
            echo -e \"${COLOR_ELECTRIC_BLUE}\$OFFICIAL_PKG_LIST${COLOR_RESET}\\n\" # Print captured output with color
        fi

        # Display pending AUR updates
        echo -e \"${COLOR_ELECTRIC_BLUE}AUR packages to be updated:${COLOR_RESET}\"
        # Capture and color the output of the AUR helper
        AUR_PKG_LIST=\$(${aurhlpr} -Qua 2>/dev/null)
        if [ -z \"\$AUR_PKG_LIST\" ]; then # Check if output is empty
            echo -e \"${COLOR_ELECTRIC_BLUE}No updates pending.${COLOR_RESET}\\n\"
        else
            echo -e \"${COLOR_ELECTRIC_BLUE}\$AUR_PKG_LIST${COLOR_RESET}\\n\" # Print captured output with color
        fi

        # Display the start of the system update
        echo -e \"${COLOR_VIOLET_PURPLE}╭─────────────────────────────────────────────────────────────────────────────────────────╮${COLOR_RESET}\"
        echo -e \"${COLOR_VIOLET_PURPLE}│    Start the system update...                                                          │${COLOR_RESET}\"
        echo -e \"${COLOR_VIOLET_PURPLE}╰─────────────────────────────────────────────────────────────────────────────────────────╯${COLOR_RESET}\\n\"
        # echo -e \"\\n\" # Add newline after list if present

        # Perform the actual system update.
        # Note: The output from this command (pacman/yay) is colored by their own configuration,
        # not directly by this script. Ensure 'Color' is uncommented in /etc/pacman.conf for best results.
        if ! ${aurhlpr} -Syu; then
            echo -e '\\n'
            echo -e \"${COLOR_HOT_PINK}╭─────────────────────────────────────────────────────────────────────────────────────────╮${COLOR_RESET}\"
            echo -e \"${COLOR_HOT_PINK}│    UPDATE FAILED                                                                       │${COLOR_RESET}\"
            echo -e \"${COLOR_HOT_PINK}│    Please see the output ABOVE for details                                             │${COLOR_RESET}\"
            echo -e \"${COLOR_HOT_PINK}╰─────────────────────────────────────────────────────────────────────────────────────────╯${COLOR_RESET}\\n\"
        else
            echo -e '\\n'
            echo -e \"${COLOR_MAGENTA}╭─────────────────────────────────────────────────────────────────────────────────────────╮${COLOR_RESET}\"
            echo -e \"${COLOR_MAGENTA}│    System Update Completed                                                             │${COLOR_RESET}\"
            echo -e \"${COLOR_MAGENTA}╰─────────────────────────────────────────────────────────────────────────────────────────╯${COLOR_RESET}\\n\"
        fi

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

# Check for AUR updates (non-interactive)
aur_updates_count=$(${aurhlpr} -Qua 2>/dev/null | wc -l)
if [ $? -ne 0 ]; then
    echo "Warning: Failed to check for AUR updates. Using 0 for AUR count." >&2
    aur_updates_count=0
fi

# Check for official updates (fast method using a temporary database)
official_updates_count=0
temp_db=$(mktemp -u /tmp/checkupdates_db_XXXXXX)
# Ensure temporary database is removed on exit, interrupt, or termination
trap '[ -f "$temp_db" ] && rm "$temp_db" 2>/dev/null' EXIT INT TERM
if CHECKUPDATES_DB="$temp_db" checkupdates 2>/dev/null >/dev/null; then
    # If checkupdates succeeds, get the count of lines
    official_updates_count=$(CHECKUPDATES_DB="$temp_db" checkupdates 2>/dev/null | wc -l)
else
    echo "Warning: Failed to check for official updates. Using 0 for official count." >&2
fi

# Calculate total available updates
upd=$((official_updates_count + aur_updates_count))

# Prepare the upgrade info to be saved
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