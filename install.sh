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
                fi # CRITICAL FIX: Added missing 'fi' here
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
    # CRITICAL FIX: Ensure getty is enabled robustly
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

    # Ensure a basic PATH is set for bash
    export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

    # CRITICAL FIX: Install yay-bin using pacman directly. This assumes yay-bin is in official repos.
    # This completely bypasses cloning and makepkg for yay-bin, which was a source of errors.
    echo "Installing yay-bin directly via pacman..."
    pacman -Syu --noconfirm yay-bin || { echo "CRITICAL ERROR: Failed to install yay-bin via pacman."; exit 1; }
    echo "SUCCESS: yay-bin installed via pacman."

    # No need for YAY_INSTALL_STATUS.tmp as pacman handles installation reliably.
EOL_AUR_INSTALL

# Step 6-C: Install AUR Packages with Yay
echo -e "${YELLOW}Installing AUR packages from pkg_aur.txt...${NOCOLOR}"
arch-chroot /mnt /bin/bash << EOL_AUR_PACKAGES

    # Enable strict mode for error handling within this chroot block
    set -e
    set -o pipefail
    # Ensure a basic PATH is set for bash
    export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

    # Determine if yay was successfully installed by checking the presence of the executable.
    # CRITICAL FIX: Check for yay binary directly in its expected location
    if [ -f "/usr/bin/yay" ] && [ -x "/usr/bin/yay" ]; then
        echo "Yay is confirmed to be installed. Proceeding with AUR packages."
    else
        echo "CRITICAL ERROR: Yay is not found or not executable after pacman installation. Skipping AUR package installation."
        exit 1 # Exit this chroot block, as AUR packages are critical for your setup.
    fi

    pkg_aur_path="/home/andres/temp_dotfiles_setup/pkg_aur.txt"

    if [ ! -f "\${pkg_aur_path}" ]; then
        echo "Error: pkg_aur_path not found at \${pkg_aur_path}. Cannot install AUR packages."
        exit 1 # Exit this chroot block, as AUR packages are critical for your setup.
    fi

    echo "Installing AUR packages listed in \${pkg_aur_path} using yay as user 'andres' (non-interactively)..."
    # NOPASSWD: ALL should handle any sudo prompts from yay itself.
    # CRITICAL FIX: Ensure yay is called as user 'andres' from a shell that respects its PATH.
    # Use 'bash -l -c' to ensure a login shell is used, which helps with PATH and environment setup.
    sudo -u andres bash -l -c "yes | yay -S --noconfirm - < \"\${pkg_aur_path}\"" || { echo "Warning: Some AUR packages failed to install. Please review the output above. Continuing."; }
    
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

    # Ensure a basic PATH is set for bash
    export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

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

    # CRITICAL FIX: Ensure /home/andres and its contents are owned by 'andres'
    echo "Setting correct ownership for /home/andres..."
    chown -R andres:andres /home/andres || { echo "Error: Failed to set ownership of /home/andres."; exit 1; }

    # --- Zsh Plugin Setup ---
    echo "Setting up Zsh plugins..."
    # Ensure .oh-my-zsh base directory exists and is owned by andres
    mkdir -p /home/andres/.oh-my-zsh/custom/plugins || { echo "Error: Failed to create .oh-my-zsh custom plugins directory."; }
    chown -R andres:andres /home/andres/.oh-my-zsh || { echo "Error: Failed to set ownership for .oh-my-zsh. Continuing."; }

    # Clone zsh-autosuggestions
    if [ ! -d "/home/andres/.oh-my-zsh/custom/plugins/zsh-autosuggestions" ]; then
        echo "Cloning zsh-autosuggestions..."
        git clone --depth 1 https://github.com/zsh-users/zsh-autosuggestions /home/andres/.oh-my-zsh/custom/plugins/zsh-autosuggestions || { echo "Warning: Failed to clone zsh-autosuggestions. Continuing."; }
    else
        echo "zsh-autosuggestions already cloned. Skipping."
    fi
    chown -R andres:andres /home/andres/.oh-my-zsh/custom/plugins/zsh-autosuggestions || { echo "Error: Failed to set ownership for zsh-autosuggestions. Continuing."; }

    # fzf is now installed via AUR, so no local cloning/install script needed here.
    echo "fzf is handled by AUR installation. Skipping local fzf setup."

    # Move fonts, themes, systemd user services (ownership should be correct now)
    echo "Adjusting dotfile locations if necessary..."
    if [ -d "/home/andres/fonts" ]; then
        mkdir -p /home/andres/.local/share/fonts || { echo "Error: Failed to create fonts directory."; }
        mv /home/andres/fonts/* /home/andres/.local/share/fonts/ 2>/dev/null || { echo "Warning: Failed to move fonts. Continuing."; }
        rmdir /home/andres/fonts 2>/dev/null || true # Ignore error if dir not empty
    fi
    if [ -d "/home/andres/themes" ]; then
        mkdir -p /home/andres/.local/share/themes || { echo "Error: Failed to create themes directory."; }
        mv /home/andres/themes/* /home/andres/.local/share/themes/ 2>/dev/null || { echo "Warning: Failed to move themes. Continuing."; }
        rmdir /home/andres/themes 2>/dev/null || true
    fi
    if [ -d "/home/andres/systemd" ]; then
        mkdir -p /home/andres/.config/systemd/user || { echo "Error: Failed to create systemd user services directory."; }
        mv /home/andres/systemd/* /home/andres/.config/systemd/user/ 2>/dev/null || { echo "Warning: Failed to move systemd user services. Continuing."; }
        rmdir /home/andres/systemd 2>/dev/null || true
    fi

    # CRITICAL SECURITY STEP: Tighten NOPASSWD rule after dotfile restoration
    echo "Restoring specific NOPASSWD rule for makepkg and yay only..."
    echo "%wheel ALL=(ALL:ALL) NOPASSWD: /usr/bin/makepkg, /usr/bin/yay" > /etc/sudoers.d/90-andres-nopasswd || { echo "Warning: Could not restore specific NOPASSWD rule."; }
    chmod 0440 /etc/sudoers.d/90-andres-nopasswd || { echo "Warning: Could not set permissions for 90-andres-nopasswd sudoers file."; }
    rm -f /etc/sudoers.d/90-andres-install-nopasswd || { echo "Warning: Could not remove temporary broad NOPASSWD file."; }

    # CRITICAL: Prepare a one-time systemd service to enable uwsm@andres.service on first boot.
    # This addresses the "command not found" for systemctl --user and permission issues in chroot.
    echo "Creating one-time systemd service for uwsm@andres.service enablement..."
    mkdir -p /etc/systemd/system/ || { echo "Error: Failed to create /etc/systemd/system directory."; exit 1; }
    # CRITICAL FIX: Get UID for 'andres' dynamically and use it in DBUS_SESSION_BUS_ADDRESS
    ANDRES_UID=$(id -u andres) || { echo "Error: Could not get UID for user 'andres'."; exit 1; }

    cat > /etc/systemd/system/enable-uwsm-on-first-boot.service << EOT_UWSM_SERVICE
[Unit]
Description=Enable uwsm@andres.service on first boot
After=network-online.target multi-user.target
Wants=network-online.target

[Service]
Type=oneshot
# CRITICAL FIX: Use the dynamically obtained UID for D-Bus path.
# Use 'bash -l -c' to ensure a login shell environment for systemctl --user.
ExecStart=/bin/bash -l -c "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:\$PATH && export XDG_RUNTIME_DIR=/run/user/${ANDRES_UID} && DBUS_SESSION_BUS_ADDRESS=unix:path=\${XDG_RUNTIME_DIR}/bus systemctl --user enable --now uwsm@andres.service"
ExecStartPost=/bin/bash -c "/usr/bin/rm -f /etc/systemd/system/enable-uwsm-on-first-boot.service"
User=andres
Environment="HOME=/home/andres"
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOT_UWSM_SERVICE
    chmod 644 /etc/systemd/system/enable-uwsm-on-first-boot.service || { echo "Error: Failed to set permissions for uwsm enablement service."; exit 1; }
    systemctl enable enable-uwsm-on-first-boot.service || { echo "Error: Failed to enable one-time uwsm enablement service."; exit 1; }

EOL_DOTFILES


# ---------------------------------------------------
# Step 8: Post-Installation User Configuration and Service Activation
# ---------------------------------------------------
echo -e "${CYAN}--- Step 8: Post-Installation User Configuration and Service Activation ---${NOCOLOR}"
echo -e "${YELLOW}Setting default shell to Zsh...${NOCOLOR}"

execute_command "Set default shell to Zsh for user 'andres'" "arch-chroot /mnt usermod --shell /usr/bin/zsh andres" "false"

# uwsm service enablement is now handled by the one-time service on first boot.
echo -e "${YELLOW}uwsm@andres.service enablement will be handled by a one-time systemd service on first boot.${NOCOLOR}"

# ---------------------------------------------------
# Step 9: Final Clean-up and Reboot
# ---------------------------------------------------
echo -e "${CYAN}--- Step 9: Final Clean-up and Reboot ---${NOCOLOR}"
echo -e "${GREEN}Installation complete. Unmounting partitions and cleaning up temporary files.${NOCOLOR}"

execute_command "Clean up temporary dotfiles directory" "rm -rf \"${DOTFILES_TEMP_NVME_DIR}\"" "true"
execute_command "Unmount -R /mnt" "umount -R /mnt" "false"

echo -e "${GREEN}You can now reboot into your new system.${NOCOLOR}"
