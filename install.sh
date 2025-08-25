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
# This will be the location of the *bare* dotfiles repo in the new system's /home/andres/
DOTFILES_BARE_DIR="/home/andres/dotfiles" 

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
execute_command "Pacstrap base system and base-devel" "pacstrap /mnt base base-devel linux-firmware git sudo networkmanager nano efibootmgr 2>&1 | tee /mnt/pacstrap.log" "false"

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
    echo "andres:password" | chpasswd || { echo "Error: Failed to set password for 'andres'."; exit 1; } # REMEMBER TO CHANGE PASSWORD
    usermod -aG wheel andres || { echo "Error: Failed to add 'andres' to wheel group."; exit 1; }
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

    TODAY=$(date +%Y-%m-%d)

    echo "default ${TODAY}_linux-zen.conf" > /boot/loader/loader.conf || { echo "Error: Failed to create loader.conf."; exit 1; }
    echo "timeout  0" >> /boot/loader/loader.conf
    echo "console-mode max" >> /boot/loader/loader.conf
    echo "editor   no" >> /boot/loader/loader.conf

    echo "title    Arch Linux Zen" > "/boot/loader/entries/${TODAY}_linux-zen.conf" || { echo "Error: Failed to create linux-zen boot entry."; exit 1; }
    echo "linux    /vmlinuz-linux-zen" >> "/boot/loader/entries/${TODAY}_linux-zen.conf"
    echo "initrd   /intel-ucode.img" >> "/boot/loader/entries/${TODAY}_linux-ucode.img" 
    echo "initrd   /initramfs-linux-zen.img" >> "/boot/loader/entries/${TODAY}_linux-zen.conf"
    echo "options  root=UUID=$(blkid -s UUID -o value /dev/nvme0n1p3) rw vt.global_cursor_default=0 nowatchdog ipv6.disable=1 mitigations=off" >> "/boot/loader/entries/${TODAY}_linux-zen.conf"

    echo "title    Arch Linux" > "/boot/loader/entries/${TODAY}_linux.conf" || { echo "Error: Failed to create linux boot entry."; exit 1; }
    echo "linux    /vmlinuz-linux" >> "/boot/loader/entries/${TODAY}_linux.conf"
    echo "initrd   /intel-ucode.img" >> "/boot/loader/entries/${TODAY}_linux-ucode.img" 
    echo "initrd   /initramfs-linux.img" >> "/boot/loader/entries/${TODAY}_linux.conf"
    echo "options  root=UUID=$(blkid -s UUID -o value /dev/nvme0n1p3) rw vt.global_cursor_default=0 nowatchdog ipv6.disable=1 mitigations=off" >> "/boot/loader/entries/${TODAY}_linux.conf"
    
    # Step 4-E: Enable getty service for auto-login (uwsm will be enabled later)
    systemctl enable getty@tty1.service || { echo "Error: Failed to enable getty service."; exit 1; }
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

BACKUP_UUID=$(eval "$BACKUP_UUID_CMD" 2>/dev/null) || { echo -e "${YELLOW}Warning: /dev/sdc not found or UUID not readable. Skipping fstab entry for Backup.${NOCOLOR}"; }
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
execute_command "Install official packages" "arch-chroot /mnt pacman -S --noconfirm - < \"${DOTFILES_TEMP_NVME_DIR}/pkg_official.txt\"" "false"

# --- New: Targeted uwsm installation verification and forceful reinstallation ---
UWSM_INSTALLED=false
echo -e "${YELLOW}Verifying 'uwsm' package installation...${NOCOLOR}"
if arch-chroot /mnt pacman -Q uwsm >/dev/null 2>&1; then
    echo -e "${GREEN}SUCCESS: 'uwsm' package is reported as installed by pacman -Q.${NOCOLOR}"
    UWSM_INSTALLED=true
else
    echo -e "${RED}Error: 'uwsm' package does not appear to be installed via pacman -Q, despite being in pkg_official.txt.${NOCOLOR}"
    echo -e "${YELLOW}This might indicate a problem during the 'Install official packages' step or a missing dependency.${NOCOLOR}"
    
    # Try forceful reinstallation directly here, as base-devel should now be present
    echo -e "${YELLOW}Attempting forceful reinstallation of 'uwsm' to resolve.${NOCOLOR}"
    if execute_command "Force reinstall uwsm" "arch-chroot /mnt pacman -S --noconfirm --overwrite '*' uwsm" "false"; then
        echo -e "${GREEN}SUCCESS: 'uwsm' forcefully reinstalled and now reported as installed.${NOCOLOR}"
        UWSM_INSTALLED=true
    else
        echo -e "${RED}Error: Forceful reinstallation of 'uwsm' failed. uwsm service cannot be enabled.${NOCOLOR}"
        UWSM_INSTALLED=false
    fi
fi

# Final check for uwsm.service file after all installation attempts
if [[ "$UWSM_INSTALLED" == "true" ]] && ! arch-chroot /mnt test -f /usr/lib/systemd/system/uwsm@.service; then
    echo -e "${RED}Critical inconsistency: 'uwsm' package is reported installed, but uwsm@.service unit file is still missing.${NOCOLOR}"
    echo -e "${YELLOW}This indicates a deeper system issue with package file extraction. Skipping uwsm service enablement.${NOCOLOR}"
    UWSM_INSTALLED=false # Mark as not truly installed for service enablement purposes
fi
# ---------------------------------------------------

# Step 6-B: Install AUR Helper (Yay)
echo -e "${YELLOW}Installing yay from AUR...${NOCOLOR}"
arch-chroot /mnt /bin/bash << EOL_AUR_INSTALL

    # Enable strict mode for error handling within this chroot block
    set -e
    set -o pipefail

    YAY_CLONE_RETRIES=3
    YAY_CLONE_SUCCESS=false

    for i in \$(seq 1 \$YAY_CLONE_RETRIES); do
        echo "Attempt \$i of \$YAY_CLONE_RETRIES to clone yay-bin..."
        # Corrected AUR URL to .org
        if git clone --depth 1 --config http.postBuffer=104857600 --config http.lowSpeedLimit=0 --config http.lowSpeedTime=20 https://aur.archlinux.org/yay-bin.git /home/andres/yay-bin; then
            YAY_CLONE_SUCCESS=true
            echo "SUCCESS: Cloned yay-bin from AUR."
            break
        else
            echo "Warning: Failed to clone yay-bin. Retrying in 5 seconds..."
            sleep 5
        fi
    done

    if ! \$YAY_CLONE_SUCCESS; then
        echo "Error: Failed to clone yay-bin after multiple attempts. AUR packages will not be installed."
        # Instead of exiting this heredoc with 0, we can write a flag to /tmp to signal failure to the next block.
        echo "YAY_INSTALL_STATUS=FAILED" > /tmp/yay_install_status.tmp
        exit 0 # Exit this chroot block gracefully.
    fi

    # Ownership and makepkg commands remain. These are critical if yay was cloned.
    chown -R andres:andres /home/andres/yay-bin || { echo "Error: Failed to change ownership of yay-bin inside chroot."; exit 1; }
    # Run makepkg as the 'andres' user
    sudo -u andres bash -c "cd /home/andres/yay-bin && makepkg -si --noconfirm" || { echo "Error: Failed to build and install yay inside chroot."; exit 1; }
    echo "YAY_INSTALL_STATUS=SUCCESS" > /tmp/yay_install_status.tmp
EOL_AUR_INSTALL

# Step 6-C: Install AUR Packages with Yay
echo -e "${YELLOW}Installing AUR packages from pkg_aur.txt...${NOCOLOR}"
arch-chroot /mnt /bin/bash << EOL_AUR_PACKAGES

    # Enable strict mode for error handling within this chroot block
    set -e
    set -o pipefail

    # Read the status from the temporary file to check if yay was installed.
    # If the file doesn't exist or indicates failure, skip AUR packages.
    if [ -f "/tmp/yay_install_status.tmp" ] && [ "\$(cat /tmp/yay_install_status.tmp)" = "SUCCESS" ]; then
        echo "Yay was successfully installed. Proceeding with AUR packages."
    else
        echo "Warning: Yay was not successfully installed. Skipping AUR package installation."
        exit 0 # Exit this chroot block gracefully.
    fi

    pkg_aur_path="/home/andres/temp_dotfiles_setup/pkg_aur.txt" # This path should be correct from outer script

    if [ ! -f "\${pkg_aur_path}" ]; then
        echo "Error: pkg_aur_path not found at \${pkg_aur_path}. Cannot install AUR packages."
        exit 0 # Exit this chroot block gracefully, no AUR packages to install
    fi

    echo "Installing AUR packages listed in \${pkg_aur_path}..."
    if ! sudo -u andres yay -S --noconfirm - < "\${pkg_aur_path}"; then
        echo "Warning: Some AUR packages failed to install. Please review the output above."
        # Don't exit here, allow main script to continue, as some packages might be non-critical.
    fi
    rm -f /tmp/yay_install_status.tmp # Clean up the status file after use
EOL_AUR_PACKAGES

# ---------------------------------------------------
# Step 7: Dotfile Restoration
# ---------------------------------------------------
echo -e "${CYAN}--- Step 7: Dotfile Restoration ---${NOCOLOR}"
echo -e "${YELLOW}Setting up bare dotfiles repository and restoring configurations to /home/andres/...${NOCOLOR}"
arch-chroot /mnt /bin/bash << EOL_DOTFILES

    # Enable strict mode for error handling within this chroot block
    set -e
    set -o pipefail

    # FIX: Add defaultBranch configuration to prevent warnings
    git config --global init.defaultBranch main || { echo "Warning: Failed to set git default branch globally. Continuing."; }

    # Variables from outer script need to be explicitly passed or reconstructed.
    DOTFILES_BARE_DIR_CHROOT="/home/andres/dotfiles"
    REPO_URL_CHROOT="https://github.com/andres-guzman/dotfiles.git"

    git init --bare "\${DOTFILES_BARE_DIR_CHROOT}" || { echo "Error: Failed to initialize bare dotfiles repository."; exit 1; }
    git --git-dir="\${DOTFILES_BARE_DIR_CHROOT}" --work-tree=/home/andres config --local status.showUntrackedFiles no || { echo "Error: Failed to configure git for dotfiles."; exit 1; }
    git --git-dir="\${DOTFILES_BARE_DIR_CHROOT}" --work-tree=/home/andres remote add origin "\${REPO_URL_CHROOT}" || { echo "Error: Failed to add origin remote to bare dotfiles repo."; exit 1; }
    git --git-dir="\${DOTFILES_BARE_DIR_CHROOT}" --work-tree=/home/andres fetch origin main || { echo "Error: Failed to fetch from origin remote."; exit 1; }
    git --git-dir="\${DOTFILES_BARE_DIR_CHROOT}" --work-tree=/home/andres checkout --force main || { echo "Error: Failed to checkout main branch from bare dotfiles repo."; exit 1; }

    echo "Adjusting dotfile locations if necessary..."
    # Move fonts
    if [ -d "/home/andres/fonts" ]; then
        mkdir -p /home/andres/.local/share/fonts || { echo "Error: Failed to create fonts directory."; }
        mv /home/andres/fonts/* /home/andres/.local/share/fonts/ 2>/dev/null || { echo "Warning: Failed to move fonts. Continuing."; }
        rmdir /home/andres/fonts 2>/dev/null || true # Ignore error if dir not empty
    fi
    # Move themes
    if [ -d "/home/andres/themes" ]; then
        mkdir -p /home/andres/.local/share/themes || { echo "Error: Failed to create themes directory."; }
        mv /home/andres/themes/* /home/andres/.local/share/themes/ 2>/dev/null || { echo "Warning: Failed to move themes. Continuing."; }
        rmdir /home/andres/themes 2>/dev/null || true
    fi
    # Move systemd user services
    if [ -d "/home/andres/systemd" ]; then
        mkdir -p /home/andres/.config/systemd/user || { echo "Error: Failed to create systemd user services directory."; }
        mv /home/andres/systemd/* /home/andres/.config/systemd/user/ 2>/dev/null || { echo "Warning: Failed to move systemd user services. Continuing."; }
        rmdir /home/andres/systemd 2>/dev/null || true
    fi
EOL_DOTFILES


# ---------------------------------------------------
# Step 8: Post-Installation User Configuration and Service Activation
# ---------------------------------------------------
echo -e "${CYAN}--- Step 8: Post-Installation User Configuration and Service Activation ---${NOCOLOR}"
echo -e "${YELLOW}Setting default shell to Zsh and enabling uwsm service...${NOCOLOR}"

execute_command "Set default shell to Zsh for user 'andres'" "arch-chroot /mnt usermod --shell /usr/bin/zsh andres" "false"

# Check if uwsm.service unit file exists before attempting to enable.
# This depends on the UWSM_INSTALLED flag set earlier.
if [[ "$UWSM_INSTALLED" == "true" ]]; then
    if arch-chroot /mnt test -f /usr/lib/systemd/system/uwsm@.service; then
        echo -e "${GREEN}uwsm@.service unit file found. Attempting to enable uwsm service.${NOCOLOR}"
        execute_command "Enable uwsm service" "arch-chroot /mnt systemctl enable uwsm@andres.service" "true"
    else
        # This branch should now only be hit if the package was marked installed, but the file is still missing.
        echo -e "${RED}Error: uwsm@.service unit file not found even after ensuring uwsm package installation (final check).${NOCOLOR}"
        echo -e "${YELLOW}This indicates a deeper system issue with package file extraction for 'uwsm'. Skipping uwsm service enablement.${NOCOLOR}"
        # Execute a dummy command to give interactive options
        execute_command "Attempt to enable uwsm service (diagnostic, likely requires manual fix)" "false" "true"
    fi
else
    echo -e "${YELLOW}Skipping uwsm service enablement as the 'uwsm' package could not be installed after multiple attempts.${NOCOLOR}"
fi


# ---------------------------------------------------
# Step 9: Final Clean-up and Reboot
# ---------------------------------------------------
echo -e "${CYAN}--- Step 9: Final Clean-up and Reboot ---${NOCOLOR}"
echo -e "${GREEN}Installation complete. Unmounting partitions and cleaning up temporary files.${NOCOLOR}"

execute_command "Clean up temporary dotfiles directory" "rm -rf \"${DOTFILES_TEMP_NVME_DIR}\"" "true"
execute_command "Unmount /mnt" "umount -R /mnt" "false"

echo -e "${GREEN}You can now reboot into your new system.${NOCOLOR}"
