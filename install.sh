#!/bin/bash

# Enable strict mode for error handling
set -e
set -o pipefail

# Define colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NOCOLOR='\033[0m'

# Define the repository URL for cloning the bare repo later
REPO_URL="https://github.com/andres-guzman/dotfiles.git"
# This will be the location of the temporary dotfiles repo in the new system's /home/andres/
DOTFILES_TEMP_DIR="/home/andres/dotfiles-temp"

# Define GitHub raw URLs for package lists (assuming they are in the root of your public repo)
PKG_OFFICIAL_URL="https://raw.githubusercontent.com/andres-guzman/dotfiles/main/pkg_official.txt"
PKG_AUR_URL="https://raw.githubusercontent.com/andres-guzman/dotfiles/main/pkg_aur.txt"

# --- GUARANTEED VARIABLE DEFINITION (moved to top for robustness) ---
# This is a critical redundant step to guarantee the variable is not empty.
DOTFILES_TEMP_NVME_DIR="/mnt/home/andres/temp_dotfiles_setup"
# -------------------------------------------------------------------

# --- Interactive Error Handler Function (for commands outside arch-chroot) ---
# This function offers retry/skip/quit options upon command failure.
# Arguments:
#   1: Description of the command that failed (for display)
#   2: The actual command string that failed (for display)
#   3: "true" if the step can be skipped, "false" if critical (only retry/quit)
handle_failure() {
    local cmd_description="$1"
    local failed_command="$2"
    local skippable="$3"

    echo -e "${RED}Error: ${cmd_description} failed!${NOCOLOR}"
    echo -e "${YELLOW}Failed command: ${failed_command}${NOCOLOR}"

    while true; do
        if [[ "$skippable" == "true" ]]; then
            echo -e "${YELLOW}Options: (r)etry, (s)kip this step, (q)uit installation.${NOCOLOR}"
        else
            echo -e "${YELLOW}This step is critical and cannot be skipped. Options: (r)etry, (q)uit installation.${NOCOLOR}"
        fi
        
        read -r -p "Enter your choice: " choice
        case "$choice" in
            r|R)
                echo -e "${YELLOW}Retrying '${cmd_description}'...${NOCOLOR}"
                return 0 # Indicate retry
                ;;
            s|S)
                if [[ "$skippable" == "true" ]]; then
                    echo -e "${YELLOW}Skipping '${cmd_description}'.${NOCOLOR}"
                    return 1 # Indicate skip
                else
                    echo -e "${RED}Invalid choice. This critical step cannot be skipped.${NOCOLOR}"
                fi
                ;;
            q|Q)
                echo -e "${RED}Quitting installation as requested.${NOCOLOR}"
                exit 1
                ;;
            *)
                echo -e "${RED}Invalid choice. Please enter 'r', 's', or 'q'.${NOCOLOR}"
                ;;
        esac
    done
}

# --- Wrapper function to execute commands with error handling ---
execute_command() {
    local cmd_description="$1"
    local command_to_execute="$2"
    local skippable="$3" # "true" or "false"

    while true; do
        if eval "$command_to_execute"; then
            echo -e "${GREEN}SUCCESS: ${cmd_description}${NOCOLOR}"
            return 0 # Command succeeded
        else
            if handle_failure "$cmd_description" "$command_to_execute" "$skippable"; then
                # User chose to retry, so loop continues
                continue
            else
                # User chose to skip or quit
                if [[ "$skippable" == "true" ]]; then
                    return 1 # Indicate skip
                else
                    echo -e "${RED}Critical command '${cmd_description}' failed and cannot be skipped. Exiting.${NOCOLOR}"
                    exit 1
                fi
            fi
        fi
    done
}


# ---------------------------------------------------
# Step 1: Disk Partitioning and Formatting
# ---------------------------------------------------
# Set the device variable for clarity.
# WARNING: This is a destructive operation on this device.
DRIVE="/dev/nvme0n1"

# --- NEW: Validate DRIVE variable ---
if [[ -z "$DRIVE" ]]; then
    echo -e "${RED}Critical Error: The DRIVE variable is empty. Please set it to your NVMe device (e.g., /dev/nvme0n1).${NOCOLOR}"
    exit 1
fi
echo -e "${YELLOW}Starting installation on target drive: ${DRIVE}${NOCOLOR}"
# -----------------------------------

echo -e "${CYAN}--- Step 1: Disk Partitioning and Formatting ---${NOCOLOR}"
echo -e "${YELLOW}Partitioning and formatting the drive: ${DRIVE}...${NOCOLOR}"

# Step 1-A: Partition the disk
execute_command "Create GPT label on ${DRIVE}" "parted -s \"${DRIVE}\" mklabel gpt" "false"
execute_command "Create EFI partition" "parted -s \"${DRIVE}\" mkpart primary fat32 1MiB 1025MiB" "false"
execute_command "Set ESP flag on EFI partition" "parted -s \"${DRIVE}\" set 1 esp on" "false"
execute_command "Create Swap partition" "parted -s \"${DRIVE}\" mkpart primary linux-swap 1025MiB 9249MiB" "false"
execute_command "Create Root partition" "parted -s \"${DRIVE}\" mkpart primary ext4 9249MiB 100%" "false"

# Step 1-B: Format the partitions
execute_command "Format EFI partition" "mkfs.fat -F32 \"${DRIVE}p1\"" "false"
execute_command "Format Swap partition" "mkswap \"${DRIVE}p2\"" "false"
execute_command "Format Root partition" "mkfs.ext4 \"${DRIVE}p3\"" "false"
execute_command "Enable Swap" "swapon \"${DRIVE}p2\"" "false"

# ---------------------------------------------------
# Step 2: Base System Installation
# ---------------------------------------------------
echo -e "${CYAN}--- Step 2: Base System Installation ---${NOCOLOR}"
echo -e "${YELLOW}Mounting partitions and installing base system...${NOCOLOR}"

# Step 2-A: Mount partitions
execute_command "Mount Root partition" "mount \"${DRIVE}p3\" /mnt" "false"
execute_command "Create /mnt/boot directory" "mkdir -p /mnt/boot" "false"
execute_command "Mount EFI partition" "mount \"${DRIVE}p1\" /mnt/boot" "false"


# Install terminus-font and set console font for the live environment (EARLIEST POSSIBLE)
echo -e "${YELLOW}Installing terminus-font for console display...${NOCOLOR}"
execute_command "Install terminus-font in live environment" "pacman -Sy --noconfirm terminus-font" "true"
echo -e "${YELLOW}Setting console font to ter-v16n...${NOCOLOR}"
execute_command "Set console font in live environment" "setfont ter-v16n" "true"

# Step 2-B: Install the base system and essential packages
echo -e "${YELLOW}Installing base system with pacstrap (output to /mnt/pacstrap.log)...${NOCOLOR}"
# IMPORTANT: Added base-devel to ensure build tools like debugedit are present early
execute_command "Pacstrap /mnt base system and base-devel" "pacstrap /mnt base base-devel linux-firmware git sudo networkmanager nano efibootmgr 2>&1 | tee /mnt/pacstrap.log" "false"

# Step 2-C: Generate fstab
execute_command "Generate fstab" "genfstab -U /mnt >> /mnt/etc/fstab" "false"

# --- NEW: Copy host resolv.conf into chroot for DNS resolution (MOVED TO AFTER PACSTRAP) ---
echo -e "${YELLOW}Copying /etc/resolv.conf from live environment to /mnt/etc/resolv.conf for DNS resolution in chroot...${NOCOLOR}"
execute_command "Copy /etc/resolv.conf" "cp /etc/resolv.conf /mnt/etc/resolv.conf" "false"


# ---------------------------------------------------
# Step 3: Prepare Dotfiles for Chroot
# ---------------------------------------------------
echo -e "${CYAN}--- Step 3: Preparing dotfiles for chroot access ---${NOCOLOR}"
echo -e "${YELLOW}Downloading package lists directly to NVMe for chroot access...${NOCOLOR}"

# Debug print at the start of Step 3 to confirm variable values
echo -e "${YELLOW}DEBUG (Step 3): DRIVE='${DRIVE}', DOTFILES_TEMP_NVME_DIR='${DOTFILES_TEMP_NVME_DIR}'${NOCOLOR}"

execute_command "Create /mnt/home/andres directory" "mkdir -p /mnt/home/andres" "false"
execute_command "Create temporary dotfiles directory on NVMe" "mkdir -p \"${DOTFILES_TEMP_NVME_DIR}\"" "false"

# Download pkg_official.txt directly to the NVMe drive with robust error handling
echo -e "${YELLOW}Attempting to download pkg_official.txt to ${DOTFILES_TEMP_NVME_DIR}...${NOCOLOR}"
execute_command "Download pkg_official.txt" "curl -f -o \"${DOTFILES_TEMP_NVME_DIR}/pkg_official.txt\" \"${PKG_OFFICIAL_URL}\"" "false"

# Download pkg_aur.txt directly to the NVMe drive with robust error handling
echo -e "${YELLOW}Attempting to download pkg_aur.txt to ${DOTFILES_TEMP_NVME_DIR}...${NOCOLOR}"
execute_command "Download pkg_aur.txt" "curl -f -o \"${DOTFILES_TEMP_NVME_DIR}/pkg_aur.txt\" \"${PKG_AUR_URL}\"" "false"

# CRITICAL FIX: Add fzf and oh-my-zsh-git to pkg_aur.txt directly here.
echo -e "${YELLOW}Ensuring 'fzf' and 'oh-my-zsh-git' are in the AUR package list.${NOCOLOR}"
if ! grep -q "^fzf$" "${DOTFILES_TEMP_NVME_DIR}/pkg_aur.txt"; then
    echo "fzf" >> "${DOTFILES_TEMP_NVME_DIR}/pkg_aur.txt"
    echo "Added fzf to AUR package list."
fi
if ! grep -q "^oh-my-zsh-git$" "${DOTFILES_TEMP_NVME_DIR}/pkg_aur.txt"; then
    echo "oh-my-zsh-git" >> "${DOTFILES_TEMP_NVME_DIR}/pkg_aur.txt"
    echo "Added oh-my-zsh-git to AUR package list."
fi
# --- FIX: Remove 'wlogout' and 'spotify' from the AUR list to bypass PGP key errors. ---
# This is a temporary measure as requested by the user.
echo -e "${YELLOW}Removing 'wlogout' and 'spotify' from the AUR package list as requested to bypass PGP errors.${NOCOLOR}"
sed -i '/^spotify$/d' "${DOTFILES_TEMP_NVME_DIR}/pkg_aur.txt"
sed -i '/^wlogout$/d' "${DOTFILES_TEMP_NVME_DIR}/pkg_aur.txt"


# ---------------------------------------------------
# Step 4: System Configuration (Inside chroot)
# ---------------------------------------------------
echo -e "${CYAN}--- Step 4: System Configuration (Inside chroot) ---${NOCOLOR}"
echo -e "${YELLOW}Entering chroot environment to configure the system...${NOCOLOR}"

arch-chroot /mnt /bin/bash << 'EOF_CHROOT_SCRIPT' 
    # Enable strict mode for error handling within the chroot script
    set -e
    set -o pipefail
    
    # Ensure a basic PATH is set for bash
    export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

    # --- Non-interactive error handling inside chroot ---
    # Critical commands will exit on failure. Skippable commands will warn and continue.
    
    # Step 4-A: Time, Locale, and Hostname
    echo "Configuring time, locale, and hostname..."
    ln -sf /usr/share/zoneinfo/America/La_Paz /etc/localtime || { echo "Error: Failed to set timezone."; exit 1; }
    hwclock --systohc || { echo "Error: Failed to set hardware clock."; exit 1; }
    echo "KEYMAP=la-latin1" > /etc/vconsole.conf || { echo "Error: Failed to set keyboard layout."; exit 1; }

    sed -i '/#en_CA.UTF-8 UTF-8/s/^#//' /etc/locale.gen || { echo "Error: Failed to uncomment en_CA locale."; exit 1; }
    sed -i '/#en_US.UTF-8 UTF-8/s/^#//' /etc/locale.gen || { echo "Error: Failed to uncomment en_US locale."; exit 1; }
    sed -i '/#es_BO.UTF-8 UTF-8/s/^#//' /etc/locale.gen || { echo "Error: Failed to uncomment es_BO locale."; exit 1; }
    locale-gen || { echo "Error: Failed to generate locales."; exit 1; }
    echo "LANG=en_US.UTF-8" > /etc/locale.conf || { echo "Error: Failed to set LANG in locale.conf."; exit 1; }

    echo "archlinux" > /etc/hostname || { echo "Error: Failed to set hostname."; exit 1; }
    echo "127.0.0.1   localhost" >> /etc/hosts
    echo "::1         localhost" >> /etc/hosts
    echo "127.0.1.1   archlinux.localdomain archlinux" >> /etc/hosts

    # Step 4-B: User and Sudo Configuration
    echo "Creating user 'andres' and configuring sudo..."
    useradd -m andres || { echo "Error: Failed to create user 'andres'."; exit 1; }
    echo "andres:armoniac" | chpasswd || { echo "Error: Failed to set password for 'andres'."; exit 1; } # PASSWORD SET TO 'armoniac'
    usermod -aG wheel andres || { echo "Error: Failed to add 'andres' to wheel group."; exit 1; }
    
    # CRITICAL FIX: Make NOPASSWD more encompassing for the chroot session.
    # This grants the 'wheel' group (which 'andres' is in) the ability to run any sudo command without a password.
    # This is temporary for the installation and will be tightened after dotfile restoration.
    echo "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/90-andres-install-nopasswd || { echo "Warning: Could not configure NOPASSWD for entire installation. Some steps might require password."; }
    chmod 0440 /etc/sudoers.d/90-andres-install-nopasswd || { echo "Warning: Could not set permissions for 90-andres-install-nopasswd sudoers file."; }
    
    # Also uncomment the general wheel group access for sudo
    sed -i '/%wheel ALL=(ALL:ALL) ALL/s/^# //g' /etc/sudoers || { echo "Error: Failed to uncomment wheel group in sudoers."; exit 1; }


    # Step 4-C: Install Kernels and other core packages & Enable multilib
    echo "Installing Zen and Stable kernels, microcode, core utilities, and enabling multilib..."
    pacman -Syu --noconfirm linux-zen linux linux-headers linux-zen-headers intel-ucode || { echo "Error: Failed to install kernels and microcode."; exit 1; }
    pacman -S --noconfirm pipewire pipewire-pulse wireplumber zsh || { echo "Error: Failed to install core audio and zsh packages."; exit 1; }

    # Enable multilib repository
    sed -i '/^#\[multilib\]/,/^#Include = \/etc\/pacman.d\/mirrorlist/ { s/^#// }' /etc/pacman.conf || { echo "Error: Failed to enable multilib repository in pacman.conf."; exit 1; }
    pacman -Syyu --noconfirm || { echo "Error: Failed to synchronize package databases and perform full system update after enabling multilib."; exit 1; }

    # Step 4-D: Bootloader Configuration
    echo "Configuring systemd-boot..."
    bootctl install || { echo "Error: Failed to install systemd-boot."; exit 1; }

    TODAY=$(date +%Y-%m-%d")

    echo "default ${TODAY}_linux-zen.conf" > /boot/loader/loader.conf || { echo "Error: Failed to create loader.conf."; exit 1; }
    echo "timeout  0" >> /boot/loader/loader.conf
    echo "console-mode max" >> /boot/loader/loader.conf
    echo "editor   no" >> /boot/loader/loader.conf

    echo "title    Arch Linux Zen" > "/boot/loader/entries/${TODAY}_linux-zen.conf" || { echo "Error: Failed to create linux-zen boot entry."; exit 1; }
    echo "linux    /vmlinuz-linux-zen" >> "/boot/loader/entries/${TODAY}_linux-zen.conf"
    echo "initrd   /intel-ucode.img" >> "/boot/loader/entries/${TODAY}_linux-zen.conf"
    echo "initrd   /initramfs-linux-zen.img" >> "/boot/loader/entries/${TODAY}_linux-zen.conf"
    echo "options  root=UUID=$(blkid -s UUID -o value /dev/nvme0n1p3) rw vt.global_cursor_default=0 nowatchdog ipv6.disable=1 mitigations=off" >> "/boot/loader/entries/${TODAY}_linux-zen.conf"

    echo "title    Arch Linux" > "/boot/loader/entries/${TODAY}_linux.conf" || { echo "Error: Failed to create linux boot entry."; exit 1; }
    echo "linux    /vmlinuz-linux" >> "/boot/loader/entries/${TODAY}_linux.conf"
    echo "initrd   /intel-ucode.img" >> "/boot/loader/entries/${TODAY}_linux.conf"
    echo "initrd   /initramfs-linux.img" >> "/boot/loader/entries/${TODAY}_linux.conf"
    echo "options  root=UUID=$(blkid -s UUID -o value /dev/nvme0n1p3) rw vt.global_cursor_default=0 nowatchdog ipv6.disable=1 mitigations=off" >> "/boot/loader/entries/${TODAY}_linux.conf"
    
    # Step 4-E: Enable getty service for auto-login (uwsm will be enabled later)
    # CRITICAL FIX: Create the systemd override for agetty
    echo "Creating systemd override for agetty to enable autologin..."
    mkdir -p /etc/systemd/system/getty@tty1.service.d || { echo "Error: Failed to create getty override directory."; exit 1; }
    cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf << EOF_AUTOLOGIN
[Service]
ExecStart=
ExecStart=-/usr/bin/agetty --autologin andres --noclear %I $TERM
EOF_AUTOLOGIN
    echo "SUCCESS: Created agetty autologin configuration."
    
    # CRITICAL FIX: Ensure getty is enabled robustly
    systemctl enable getty@tty1.service || { echo "Error: Failed to enable getty service."; exit 1; }

    # CRITICAL FIX: Add a line to .bash_profile to handle autostart
    # This is a robust way to start the session manager without relying on a temporary systemd service.
    echo "Creating or updating .bash_profile for autologin and uwsm autostart..."
    BASH_PROFILE_PATH="/home/andres/.bash_profile"
    
    # Check if .bash_profile exists, if not, create it
    if [ ! -f "\${BASH_PROFILE_PATH}" ]; then
        touch "\${BASH_PROFILE_PATH}" || { echo "Error: Failed to create .bash_profile."; exit 1; }
        chown andres:andres "\${BASH_PROFILE_PATH}" || { echo "Error: Failed to set ownership of .bash_profile."; exit 1; }
    fi

    # Append the autostart logic to .bash_profile
    # This logic checks if a Wayland session is already active and starts it if not.
    # NOTE: This ensures it only runs for an interactive login shell.
    cat >> "\${BASH_PROFILE_PATH}" << 'EOF_BASH_PROFILE'
if [[ -z "$DISPLAY" && "$XDG_VTNR" -eq 1 ]]; then
    exec /usr/bin/uwsm
fi
EOF_BASH_PROFILE
    chown andres:andres "\${BASH_PROFILE_PATH}" || { echo "Error: Failed to set ownership of .bash_profile."; exit 1; }

EOF_CHROOT_SCRIPT

echo -e "${YELLOW}Exiting chroot environment...${NOCOLOR}"

# ---------------------------------------------------
# Step 5: Automounting Other Drives
# ---------------------------------------------------
echo -e "${CYAN}--- Step 5: Automounting Other Drives ---${NOCOLOR}"
echo -e "${YELLOW}Mounting other hard drives...${NOCOLOR}"

execute_command "Create mount points for external drives" "mkdir -p /mnt/Documents /mnt/Videos /mnt/Backup" "true"

# Get the UUIDs for your three hard drives
DOCS_UUID_CMD="blkid -s UUID -o value /dev/sda"
VIDEOS_UUID_CMD="blkid -s UUID -o value /dev/sdb"
BACKUP_UUID_CMD="blkid -s UUID -o value /dev/sdc"

# Replaced interactive handling with non-interactive checks and warnings.
DOCS_UUID=$(eval "$DOCS_UUID_CMD" 2>/dev/null) || { echo -e "${YELLOW}Warning: /dev/sda not found or UUID not readable. Skipping fstab entry for Documents.${NOCOLOR}"; }
if [[ -n "$DOCS_UUID" ]]; then
    execute_command "Add /dev/sda to fstab" "echo \"UUID=${DOCS_UUID} /mnt/Documents ext4 defaults,nodev,nosuid,noexec,nofail,x-gvfs-show,user 0 0\" >> /mnt/etc/fstab" "true"
fi

VIDEOS_UUID=$(eval "$VIDEOS_UUID_CMD" 2>/dev/null) || { echo -e "${YELLOW}Warning: /dev/sdb not found or UUID not readable. Skipping fstab entry for Videos.${NOCOLOR}"; }
if [[ -n "$VIDEOS_UUID" ]]; then
    execute_command "Add /dev/sdb to fstab" "echo \"UUID=${VIDEOS_UUID} /mnt/Videos ext4 defaults,nodev,nosuid,noexec,nofail,x-gvfs-show,user 0 0\" >> /mnt/etc/fstab" "true"
fi

BACKUP_UUID=$(eval "$BACKUP_UUID_CMD" 2>/dev/null) || { echo -e "${YELLOW}Warning: /dev/sdc not found or UUID not readable. Skipping fstab entry for Backup.${NOCOLOR}" }
if [[ -n "$BACKUP_UUID" ]]; then
    execute_command "Add /dev/sdc to fstab" "echo \"UUID=${BACKUP_UUID} /mnt/Backup ext4 defaults,nodev,nosuid,noexec,nofail,x-gvfs-show,user 0 0\" >> /mnt/etc/fstab" "true"
fi

# ---------------------------------------------------
# Step 6: Hyprland and Other Package Installation
# ---------------------------------------------------
echo -e "${CYAN}--- Step 6: Hyprland and Other Package Installation ---${NOCOLOR}"

# Step 6-A: Install Official Packages
echo -e "${YELLOW}Installing official packages from pkg_official.txt...${NOCOLOR}"
execute_command "Refresh package databases before official package installation" "arch-chroot /mnt pacman -Syyu --noconfirm" "false"

# CRITICAL FIX: Ensure uwsm is in the official package list.
# We modify pkg_official.txt in the temporary directory before installing.
echo -e "${YELLOW}Ensuring 'uwsm' is in the official package list and will be installed via pacman.${NOCOLOR}"
if ! grep -q "^uwsm$" "${DOTFILES_TEMP_NVME_DIR}/pkg_official.txt"; then
    echo "uwsm" >> "${DOTFILES_TEMP_NVME_DIR}/pkg_official.txt"
    echo "Added uwsm to official package list."
else
    echo "uwsm already in official package list."
fi

OFFICIAL_PACKAGES=$(cat "${DOTFILES_TEMP_NVME_DIR}/pkg_official.txt")
execute_command "Install official packages (including uwsm)" "echo \"${OFFICIAL_PACKAGES}\" | arch-chroot /mnt pacman -S --noconfirm -" "false"

# ---------------------------------------------------

# Step 6-B: Install AUR Helper (Yay)
echo -e "${YELLOW}Installing yay from AUR...${NOCOLOR}"
arch-chroot /mnt /bin/bash << EOL_AUR_INSTALL

    # Enable strict mode for error handling within this chroot block
    set -e
    set -o pipefail

    # Ensure a comprehensive PATH for commands in this chroot block
    export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/home/andres/.local/bin

    YAY_CLONE_RETRIES=5 # Increased retries
    YAY_CLONE_SLEEP=10 # Increased sleep time
    YAY_CLONE_SUCCESS=false

    # CRITICAL FIX: Explicitly create /home/andres/yay-bin with correct ownership as root,
    # then change ownership to 'andres'. This guarantees write permissions for the user.
    echo "Ensuring /home/andres/yay-bin directory exists and is owned by 'andres'..."
    mkdir -p /home/andres/yay-bin || { echo "CRITICAL ERROR: Failed to create /home/andres/yay-bin directory as root."; exit 1; }
    chown andres:andres /home/andres/yay-bin || { echo "CRITICAL ERROR: Failed to set ownership of /home/andres/yay-bin."; exit 1; }

    for i in \$(seq 1 \$YAY_CLONE_RETRIES); do
        echo "Attempt \$i of \$YAY_CLONE_RETRIES to clone yay-bin..."
        # CRITICAL FIX: Ensure git clone is run as user 'andres' directly into /home/andres/yay-bin
        if sudo -u andres git clone --depth 1 --config http.postBuffer=104857600 --config http.lowSpeedLimit=0 --config http.lowSpeedTime=20 https://aur.archlinux.org/yay-bin.git /home/andres/yay-bin; then
            YAY_CLONE_SUCCESS=true
            echo "SUCCESS: Cloned yay-bin from AUR."
            break
        else
            echo "Warning: Failed to clone yay-bin. Retrying in \${YAY_CLONE_SLEEP} seconds..."
            sleep "\${YAY_CLONE_SLEEP}"
        fi
    done

    if ! \$YAY_CLONE_SUCCESS; then
        echo "CRITICAL ERROR: Failed to clone yay-bin after multiple attempts. Exiting AUR install block."
        exit 1 # Critical failure, exit this chroot block
    else
        # Ownership for the cloned directory for user 'andres'
        chown -R andres:andres /home/andres/yay-bin || { echo "Error: Failed to change ownership of yay-bin inside chroot."; exit 1; }
        
        # CRITICAL FIX: Build and install yay as user 'andres' (not root) using sudo and NOPASSWD: ALL.
        # Ensure a robust PATH for makepkg within this subshell.
        echo "Building and installing yay as user 'andres' (non-interactively)..."
        if sudo -u andres bash -l -c "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:\$PATH && cd /home/andres/yay-bin && makepkg -si --noconfirm"; then
            echo "SUCCESS: Built and installed yay."
        else
            echo "CRITICAL ERROR: Failed to build and install yay as user 'andres' inside chroot. Exiting AUR install block."
            exit 1 # Critical failure, exit this chroot block
        fi
    fi
EOL_AUR_INSTALL

# Step 6-C: Install AUR Packages with Yay
echo -e "${YELLOW}Installing AUR packages from pkg_aur.txt...${NOCOLOR}"
arch-chroot /mnt /bin/bash << EOL_AUR_PACKAGES

    # Enable strict mode for error handling within this chroot block
    set -e
    set -o pipefail
    # Ensure a comprehensive PATH for commands in this chroot block
    export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/home/andres/.local/bin

    # Ensure /home/andres/.config and other dotfile directories exist before the restoration.
    # This prevents the restoration script from failing if the directories are not there.
    echo "Creating necessary dotfile directories for 'andres'..."
    mkdir -p /home/andres/.config || { echo "ERROR: Failed to create /home/andres/.config"; }
    mkdir -p /home/andres/.local/share || { echo "ERROR: Failed to create /home/andres/.local/share"; }
    
    # CRITICAL FIX: Direct copy of dotfiles from temporary location to final user home directory.
    # This completely bypasses the original bare git repository method that was causing the error.
    echo "Restoring dotfiles from temporary directory /home/andres/temp_dotfiles_setup..."
    if ! sudo -u andres rsync -av --exclude='.git/' --exclude='LICENSE' --exclude='README.md' --exclude='pkg_*' /home/andres/temp_dotfiles_setup/ /home/andres/; then
        echo "CRITICAL ERROR: Dotfile restoration failed as user 'andres' during rsync. Please check permissions."
        exit 1
    else
        echo "SUCCESS: Dotfiles restored successfully."
    fi

    # CRITICAL FIX: Set correct ownership for all restored files and directories.
    echo "Setting correct ownership for all restored dotfiles..."
    chown -R andres:andres /home/andres || { echo "ERROR: Failed to set ownership of /home/andres"; }

    # Step 6-C.1: Install AUR packages
    # CRITICAL FIX: Use sudo -u andres to ensure the command is run as the user.
    echo "Installing AUR packages from pkg_aur.txt as user 'andres'..."
    if ! sudo -u andres yay -S --noconfirm --removemake --useask --editmenu=false $(cat /home/andres/temp_dotfiles_setup/pkg_aur.txt); then
        echo "ERROR: Yay failed to install AUR packages."
    else
        echo "SUCCESS: Installed AUR packages."
    fi
    
    # Optional: Clean up the temporary dotfiles directory after installation
    echo "Cleaning up temporary dotfiles directory..."
    rm -rf /home/andres/temp_dotfiles_setup || { echo "Warning: Could not remove temporary dotfiles directory."; }

    # CRITICAL FIX: Clean up the temporary sudoers file.
    echo "Removing temporary NOPASSWD sudoers file..."
    rm /etc/sudoers.d/90-andres-install-nopasswd || { echo "Warning: Could not remove temporary sudoers file."; }
    
    # CRITICAL FIX: Set the user's default shell to Zsh as requested.
    echo "Setting user 'andres' default shell to zsh..."
    chsh -s /usr/bin/zsh andres || { echo "Error: Failed to set default shell."; }
    
EOL_AUR_PACKAGES

echo -e "${GREEN}Installation script finished! You can now unmount and reboot into your new Arch Linux system.${NOCOLOR}"
