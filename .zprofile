# #!/bin/bash

# # Check if DISPLAY is not set AND if we are on tty1
# if [[ -z "$DISPLAY" ]] && [[ "$(tty)" == /dev/tty1 ]]; then
#     # Check if uwsm allows starting
#     if uwsm check may-start >/dev/null 2>&1; then
#         # Start Hyprland via uwsm and suppress all output
#         exec uwsm start hyprland.desktop >/dev/null 2>&1
#     else
#         # Start Hyprland directly and suppress all output
#         exec Hyprland >/dev/null 2>&1
#     fi
# fi

# # Suppress the login message
# touch ~/.hushlogin





# if [[ -z $DISPLAY ]] && [[ $(tty) == /dev/tty1 ]]; then
#     exec Hyprland >/dev/null 2>&1
# fi

# # Suppress the login message
# touch ~/.hushlogin







# if [[ -z $DISPLAY ]] && [[ $(tty) == /dev/tty1 ]]; then
#     exec Hyprland >/dev/null 2>&1
# fi

# # Suppress the login message
# touch ~/.hushlogin






if [[ -z $DISPLAY ]] && [[ $(tty) == /dev/tty1 ]]; then
    if [[ -f ~/.zshenv ]]; then
        source ~/.zshenv
    fi
    exec Hyprland >/dev/null 2>&1
fi

# Suppress the login message
touch ~/.hushlogin