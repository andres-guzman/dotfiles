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

# --- New: Interactive Error Handler Function ---
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
# Removed inner quotes around $DRIVE in eval commands to prevent empty string expansion
execute_command "Create GPT label on ${DRIVE}" "parted -s $DRIVE mklabel gpt" "false"
execute_command "Create EFI partition" "parted -s $DRIVE mkpart primary fat32 1MiB 1025MiB" "false"
execute_command "Set ESP flag on EFI partition" "parted -s $DRIVE set 1 esp on" "false"
execute_command "Create Swap partition" "parted -s $DRIVE mkpart primary linux-swap 1025MiB 9249MiB" "false"
execute_command "Create Root partition" "parted -s $DRIVE mkpart primary ext4 9249MiB 100%" "false"

# Step 1-B: Format the partitions
execute_command "Format EFI partition" "mkfs.fat -F32 ${DRIVE}p1" "false"
execute_command "Format Swap partition" "mkswap ${DRIVE}p2" "false"
execute_command "Format Root partition" "mkfs.ext4 ${DRIVE}p3" "false"
execute_command "Enable Swap" "swapon ${DRIVE}p2" "false"

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
execute_command "Pacstrap base system" "pacstrap /mnt base linux-firmware git sudo networkmanager nano efibootmgr 2>&1 | tee /mnt/pacstrap.log" "false"

# Step 2-C: Generate fstab
execute_command "Generate fstab" "genfstab -U /mnt >> /mnt/etc/fstab" "false"


# ---------------------------------------------------
# Step 3: Prepare Dotfiles for Chroot
# ---------------------------------------------------
echo -e "${CYAN}--- Step 3: Preparing dotfiles for chroot access ---${NOCOLOR}"
echo -e "${YELLOW}Downloading package lists directly to NVMe for chroot access...${NOCOLOR}"

execute_command "Create /mnt/home/andres directory" "mkdir -p /mnt/home/andres" "false"
execute_command "Create temporary dotfiles directory on NVMe" "mkdir -p \"$DOTFILES_TEMP_NVME_DIR\"" "false"

# Download pkg_official.txt directly to the NVMe drive with robust error handling
echo -e "${YELLOW}Attempting to download pkg_official.txt to ${DOTFILES_TEMP_NVME_DIR}...${NOCOLOR}"
execute_command "Download pkg_official.txt" "curl -f -o \"$DOTFILES_TEMP_NVME_DIR/pkg_official.txt\" \"$PKG_OFFICIAL_URL\"" "false"
execute_command "Verify pkg_official.txt download" "[ ! -f \"$DOTFILES_TEMP_NVME_DIR/pkg_official.txt\" ] && exit 1" "false"

# Download pkg_aur.txt directly to the NVMe drive with robust error handling
echo -e "${YELLOW}Attempting to download pkg_aur.txt to ${DOTFILES_TEMP_NVME_DIR}...${NOCOLOR}"
execute_command "Download pkg_aur.txt" "curl -f -o \"$DOTFILES_TEMP_NVME_DIR/pkg_aur.txt\" \"$PKG_AUR_URL\"" "false"
execute_command "Verify pkg_aur.txt download" "[ ! -f \"$DOTFILES_TEMP_NVME_DIR/pkg_aur.txt\" ] && exit 1" "false"


# ---------------------------------------------------
# Step 4: System Configuration (Inside chroot)
# ---------------------------------------------------
echo -e "${CYAN}--- Step 4: System Configuration (Inside chroot) ---${NOCOLOR}"
echo -e "${YELLOW}Entering chroot environment to configure the system...${NOCOLOR}"

# Explicitly use /bin/sh for the chroot shell to avoid bash-specific issues
arch-chroot /mnt /bin/sh << 'EOF_CHROOT_SCRIPT' # Use single quotes to prevent variable expansion now
    # Ensure a basic PATH is set for sh
    export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

    # --- New: Interactive Error Handler Function (inside chroot) ---
    handle_failure_chroot() {
        local cmd_description="$1"
        local failed_command="$2"
        local skippable="$3"

        echo "Error: $cmd_description failed!"
        echo "Failed command: $failed_command"

        while true; do
            if [ "$skippable" = "true" ]; then
                echo "Options: (r)etry, (s)kip this step, (q)uit installation."
            else
                echo "This step is critical and cannot be skipped. Options: (r)etry, (q)uit installation."
            fi
            
            read -r -p "Enter your choice: " choice
            case "$choice" in
                r|R)
                    echo "Retrying '$cmd_description'..."
                    return 0 # Indicate retry
                    ;;
                s|S)
                    if [ "$skippable" = "true" ]; then
                        echo "Skipping '$cmd_description'."
                        return 1 # Indicate skip
                    else
                        echo "Invalid choice. This critical step cannot be skipped."
                    fi
                    ;;
                q|Q)
                    echo "Quitting installation as requested."
                    exit 1
                    ;;
                *)
                    echo "Invalid choice. Please enter 'r', 's', or 'q'."
                    ;;
            esac
        done
    }

    execute_command_chroot() {
        local cmd_description="$1"
        local command_to_execute="$2"
        local skippable="$3"

        while true; do
            if eval "$command_to_execute"; then
                echo "SUCCESS: $cmd_description"
                return 0
            else
                if handle_failure_chroot "$cmd_description" "$command_to_execute" "$skippable"; then
                    continue
                else
                    if [ "$skippable" = "true" ]; then
                        return 1
                    else
                        echo "Critical command '$cmd_description' failed and cannot be skipped. Exiting."
                        exit 1
                    fi
                fi
            fi
        done
    }


    # Step 4-A: Time, Locale, and Hostname
    echo "Configuring time, locale, and hostname..."
    execute_command_chroot "Set timezone" "ln -sf /usr/share/zoneinfo/America/La_Paz /etc/localtime" "false"
    execute_command_chroot "Set hardware clock" "hwclock --systohc" "false"
    execute_command_chroot "Set keyboard layout" "echo \"KEYMAP=la-latin1\" > /etc/vconsole.conf" "false"

    execute_command_chroot "Uncomment en_CA locale" "sed -i '/#en_CA.UTF-8 UTF-8/s/^#//' /etc/locale.gen" "false"
    execute_command_chroot "Uncomment en_US locale" "sed -i '/#en_US.UTF-8 UTF-8/s/^#//' /etc/locale.gen" "false"
    execute_command_chroot "Uncomment es_BO locale" "sed -i '/#es_BO.UTF-8 UTF-8/s/^#//' /etc/locale.gen" "false"
    execute_command_chroot "Generate locales" "locale-gen" "false"
    execute_command_chroot "Set LANG in locale.conf" "echo \"LANG=en_US.UTF-8\" > /etc/locale.conf" "false"

    execute_command_chroot "Set hostname" "echo \"archlinux\" > /etc/hostname" "false"
    execute_command_chroot "Add localhost to hosts" "echo \"127.0.0.1   localhost\" >> /etc/hosts" "false"
    execute_command_chroot "Add ::1 to hosts" "echo \"::1         localhost\" >> /etc/hosts" "false"
    execute_command_chroot "Add archlinux to hosts" "echo \"127.0.1.1   archlinux.localdomain archlinux\" >> /etc/hosts" "false"

    # Step 4-B: User and Sudo Configuration
    echo "Creating user 'andres' and configuring sudo..."
    execute_command_chroot "Create user 'andres'" "useradd -m andres" "false"
    execute_command_chroot "Set password for 'andres'" "echo \"andres:password\" | chpasswd" "false" # REMEMBER TO CHANGE PASSWORD
    execute_command_chroot "Add 'andres' to wheel group" "usermod -aG wheel andres" "false"
    execute_command_chroot "Uncomment wheel group in sudoers" "sed -i '/%wheel ALL=(ALL:ALL) ALL/s/^# //g' /etc/sudoers" "false"

    # Step 4-C: Install Kernels and other core packages & Enable multilib
    echo "Installing Zen and Stable kernels, microcode, core utilities, and enabling multilib..."
    execute_command_chroot "Install kernels and microcode" "pacman -Syu --noconfirm linux-zen linux linux-headers linux-zen-headers intel-ucode" "false"
    execute_command_chroot "Install core audio and zsh packages" "pacman -S --noconfirm pipewire pipewire-pulse wireplumber zsh" "false"

    # Enable multilib repository
    execute_command_chroot "Uncomment multilib section (Include line) in pacman.conf" "sed -i '/^#\[multilib\]/,/^#Include = \/etc\/pacman.d\/mirrorlist/ { s/^#// }' /etc/pacman.conf" "false"
    execute_command_chroot "Synchronize package databases and perform full system update after enabling multilib" "pacman -Syyu --noconfirm" "false"

    # Step 4-D: Bootloader Configuration
    echo "Configuring systemd-boot..."
    execute_command_chroot "Install systemd-boot" "bootctl install" "false"

    TODAY=$(date +%Y-%m-%d) # Not escaped in inner shell; bash handles this when writing the here-doc.

    execute_command_chroot "Create loader.conf" "echo \"default ${TODAY}_linux-zen.conf\" > /boot/loader/loader.conf" "false"
    execute_command_chroot "Add timeout to loader.conf" "echo \"timeout  0\" >> /boot/loader/loader.conf" "false"
    execute_command_chroot "Add console-mode to loader.conf" "echo \"console-mode max\" >> /boot/loader/loader.conf" "false"
    execute_command_chroot "Add editor no to loader.conf" "echo \"editor   no\" >> /boot/loader/loader.conf" "false"

    execute_command_chroot "Create linux-zen boot entry" "echo \"title    Arch Linux Zen\" > \"/boot/loader/entries/${TODAY}_linux-zen.conf\"" "false"
    execute_command_chroot "Add linux-zen kernel to boot entry" "echo \"linux    /vmlinuz-linux-zen\" >> \"/boot/loader/entries/${TODAY}_linux-zen.conf\"" "false"
    execute_command_chroot "Add intel-ucode initrd to linux-zen boot entry" "echo \"initrd   /intel-ucode.img\" >> \"/boot/loader/entries/${TODAY}_linux-ucode.img\"" "false"
    execute_command_chroot "Add initramfs-linux-zen to boot entry" "echo \"initrd   /initramfs-linux-zen.img\" >> \"/boot/loader/entries/${TODAY}_linux-zen.conf\"" "false"
    execute_command_chroot "Add options to linux-zen boot entry" "echo \"options  root=UUID=$(blkid -s UUID -o value /dev/nvme0n1p3) rw vt.global_cursor_default=0 nowatchdog ipv6.disable=1 mitigations=off\" >> \"/boot/loader/entries/${TODAY}_linux-zen.conf\"" "false"

    execute_command_chroot "Create linux boot entry" "echo \"title    Arch Linux\" > \"/boot/loader/entries/${TODAY}_linux.conf\"" "false"
    execute_command_chroot "Add linux kernel to boot entry" "echo \"linux    /vmlinuz-linux\" >> \"/boot/loader/entries/${TODAY}_linux.conf\"" "false"
    execute_command_chroot "Add intel-ucode initrd to linux boot entry" "echo \"initrd   /intel-ucode.img\" >> \"/boot/loader/entries/${TODAY}_linux-ucode.img\"" "false"
    execute_command_chroot "Add initramfs-linux to boot entry" "echo \"initrd   /initramfs-linux.img\" >> \"/boot/loader/entries/${TODAY}_linux.conf\"" "false"
    execute_command_chroot "Add options to linux boot entry" "echo \"options  root=UUID=$(blkid -s UUID -o value /dev/nvme0n1p3) rw vt.global_cursor_default=0 nowatchdog ipv6.disable=1 mitigations=off\" >> \"/boot/loader/entries/${TODAY}_linux.conf\"" "false"
    
    # Step 4-E: Enable getty service for auto-login (uwsm will be enabled later)
    execute_command_chroot "Enable getty service" "systemctl enable getty@tty1.service" "false"
EOF_CHROOT_SCRIPT

echo -e "${YELLOW}Exiting chroot environment...${NOCOLOR}"

# ---------------------------------------------------
# Step 5: Automounting Other Drives
# ---------------------------------------------------
echo -e "${CYAN}--- Step 5: Automounting Other Drives ---${NOCOLOR}"
echo -e "${YELLOW}Mounting other hard drives...${NOCOLOR}"

# Create mount points for the drives
execute_command "Create mount points for external drives" "mkdir -p /mnt/Documents /mnt/Videos /mnt/Backup" "true"

# Get the UUIDs for your three hard drives
# These steps are skippable if the drives are not present, but critical if they are expected.
DOCS_UUID_CMD="blkid -s UUID -o value /dev/sda"
VIDEOS_UUID_CMD="blkid -s UUID -o value /dev/sdb"
BACKUP_UUID_CMD="blkid -s UUID -o value /dev/sdc"

if execute_command "Get UUID for /dev/sda (Documents)" "$DOCS_UUID_CMD" "true"; then
    DOCS_UUID=$(eval "$DOCS_UUID_CMD") # Capture the output
    execute_command "Add /dev/sda to fstab" "echo \"UUID=${DOCS_UUID} /mnt/Documents ext4 defaults,nodev,nosuid,noexec,nofail,x-gvfs-show,user 0 0\" >> /mnt/etc/fstab" "true"
else
    echo -e "${YELLOW}Warning: Skipping /dev/sda (Documents) fstab entry.${NOCOLOR}"
fi

if execute_command "Get UUID for /dev/sdb (Videos)" "$VIDEOS_UUID_CMD" "true"; then
    VIDEOS_UUID=$(eval "$VIDEOS_UUID_CMD")
    execute_command "Add /dev/sdb to fstab" "echo \"UUID=${VIDEOS_UUID} /mnt/Videos ext4 defaults,nodev,nosuid,noexec,nofail,x-gvfs-show,user 0 0\" >> /mnt/etc/fstab" "true"
else
    echo -e "${YELLOW}Warning: Skipping /dev/sdb (Videos) fstab entry.${NOCOLOR}"
fi

if execute_command "Get UUID for /dev/sdc (Backup)" "$BACKUP_UUID_CMD" "true"; then
    BACKUP_UUID=$(eval "$BACKUP_UUID_CMD")
    execute_command "Add /dev/sdc to fstab" "echo \"UUID=${BACKUP_UUID} /mnt/Backup ext4 defaults,nodev,nosuid,noexec,nofail,x-gvfs-show,user 0 0\" >> /mnt/etc/fstab" "true"
else
    echo -e "${YELLOW}Warning: Skipping /dev/sdc (Backup) fstab entry.${NOCOLOR}"
fi

# ---------------------------------------------------
# Step 6: Hyprland and Other Package Installation
# ---------------------------------------------------
echo -e "${CYAN}--- Step 6: Hyprland and Other Package Installation ---${NOCOLOR}"

# Step 6-A: Install Official Packages
echo -e "${YELLOW}Installing official packages from pkg_official.txt...${NOCOLOR}"
execute_command "Refresh package databases before official package installation" "arch-chroot /mnt pacman -Syyu --noconfirm" "false"
execute_command "Install official packages" "arch-chroot /mnt pacman -S --noconfirm - < \"$DOTFILES_TEMP_NVME_DIR/pkg_official.txt\"" "false"

# Step 6-B: Install AUR Helper (Yay)
echo -e "${YELLOW}Installing yay from AUR...${NOCOLOR}"
arch-chroot /mnt bash << 'EOL_AUR_INSTALL' # Use single quotes here to prevent outer shell variable expansion

    # --- Interactive Error Handler Function (inside chroot) ---
    handle_failure_aur() {
        local cmd_description="$1"
        local failed_command="$2"
        local skippable="$3"

        echo "Error: $cmd_description failed!"
        echo "Failed command: $failed_command"

        while true; do
            if [ "$skippable" = "true" ]; then
                echo "Options: (r)etry, (s)kip this step, (q)uit installation."
            else
                echo "This step is critical and cannot be skipped. Options: (r)etry, (q)uit installation."
            fi
            
            read -r -p "Enter your choice: " choice
            case "$choice" in
                r|R)
                    echo "Retrying '$cmd_description'..."
                    return 0 # Indicate retry
                    ;;
                s|S)
                    if [ "$skippable" = "true" ]; then
                        echo "Skipping '$cmd_description'."
                        return 1 # Indicate skip
                    else
                        echo "Invalid choice. This critical step cannot be skipped."
                    fi
                    ;;
                q|Q)
                    echo "Quitting installation as requested."
                    exit 1
                    ;;
                *)
                    echo "Invalid choice. Please enter 'r', 's', or 'q'."
                    ;;
            esac
        done
    }

    execute_command_aur() {
        local cmd_description="$1"
        local command_to_execute="$2"
        local skippable="$3"

        while true; do
            if eval "$command_to_execute"; then
                echo "SUCCESS: $cmd_description"
                return 0
            else
                if handle_failure_aur "$cmd_description" "$command_to_execute" "$skippable"; then
                    continue
                else
                    if [ "$skippable" = "true" ]; then
                        return 1
                    else
                        echo "Critical command '$cmd_description' failed and cannot be skipped. Exiting."
                        exit 1
                    fi
                fi
            fi
        done
    }

    # Clone yay-bin with a timeout and interactive retry
    YAY_CLONE_CMD="git clone --depth 1 --config http.postBuffer=104857600 --config http.lowSpeedLimit=0 --config http.lowSpeedTime=20 https://aur.archlinux.org/yay-bin.git /home/andres/yay-bin"
    if ! execute_command_aur "Clone yay-bin from AUR" "$YAY_CLONE_CMD" "true"; then
        echo "Warning: Failed to clone yay-bin. AUR packages will not be installed."
        exit 0 # Exit this chroot block, but allow main script to continue
    fi

    # Ownership and makepkg commands remain. These are critical if yay was cloned.
    execute_command_aur "Change ownership of yay-bin" "chown -R andres:andres /home/andres/yay-bin" "false"
    # Run makepkg as the 'andres' user
    # makepkg will prompt, ensure --noconfirm
    execute_command_aur "Build and install yay" "sudo -u andres bash -c \"cd /home/andres/yay-bin && makepkg -si --noconfirm\"" "false"

EOL_AUR_INSTALL

# Step 6-C: Install AUR Packages with Yay
echo -e "${YELLOW}Installing AUR packages from pkg_aur.txt...${NOCOLOR}"
arch-chroot /mnt bash << 'EOL_AUR_PACKAGES'
    # Use the same error handling function defined above for AUR packages
    handle_failure_aur_pkgs() { # Renamed to avoid conflicts if needed, though this is within its own here-doc
        local cmd_description="$1"
        local failed_command="$2"
        local skippable="$3"

        echo "Error: $cmd_description failed!"
        echo "Failed command: $failed_command"

        while true; do
            if [ "$skippable" = "true" ]; then
                echo "Options: (r)etry, (s)kip this step, (q)uit installation."
            else
                echo "This step is critical and cannot be skipped. Options: (r)etry, (q)uit installation."
            fi
            
            read -r -p "Enter your choice: " choice
            case "$choice" in
                r|R)
                    echo "Retrying '$cmd_description'..."
                    return 0 # Indicate retry
                    ;;
                s|S)
                    if [ "$skippable" = "true" ]; then
                        echo "Skipping '$cmd_description'."
                        return 1 # Indicate skip
                    else
                        echo "Invalid choice. This critical step cannot be skipped."
                    fi
                    ;;
                q|Q)
                    echo "Quitting installation as requested."
                    exit 1
                    ;;
                *)
                    echo "Invalid choice. Please enter 'r', 's', or 'q'."
                    ;;
            esac
        }

    execute_command_aur_pkgs() {
        local cmd_description="$1"
        local command_to_execute="$2"
        local skippable="$3"

        while true; do
            if eval "$command_to_execute"; then
                echo "SUCCESS: $cmd_description"
                return 0
            else
                if handle_failure_aur_pkgs "$cmd_description" "$command_to_execute" "$skippable"; then
                    continue
                else
                    if [ "$skippable" = "true" ]; then
                        return 1
                    else
                        echo "Critical command '$cmd_description' failed and cannot be skipped. Exiting."
                        exit 1
                    fi
                fi
            fi
        done
    }

    # Ensure yay is run as the 'andres' user and uses the correct path to pkg_aur.txt
    # Assuming $DOTFILES_TEMP_NVME_DIR is correctly set and readable within chroot
    # We will reconstruct the path.
    local pkg_aur_path="/home/andres/temp_dotfiles_setup/pkg_aur.txt"
    if [ ! -f "$pkg_aur_path" ]; then
        echo "Error: pkg_aur.txt not found at $pkg_aur_path. Cannot install AUR packages."
        exit 1 # Exit this chroot block if pkg_aur.txt is missing
    fi

    if ! execute_command_aur_pkgs "Install AUR packages with Yay" "sudo -u andres yay -S --noconfirm - < \"$pkg_aur_path\"" "true"; then
        echo "Warning: Some AUR packages failed to install."
        # Don't exit here, allow main script to continue, as user chose to skip or some packages might be non-critical.
    fi
EOL_AUR_PACKAGES

# ---------------------------------------------------
# Step 7: Dotfile Restoration
# ---------------------------------------------------
echo -e "${CYAN}--- Step 7: Dotfile Restoration ---${NOCOLOR}"
echo -e "${YELLOW}Setting up bare dotfiles repository and restoring configurations to /home/andres/...${NOCOLOR}"
arch-chroot /mnt bash << 'EOL_DOTFILES'
    # Re-define error handling functions for this chroot block
    handle_failure_dotfiles() {
        local cmd_description="$1"
        local failed_command="$2"
        local skippable="$3"

        echo "Error: $cmd_description failed!"
        echo "Failed command: $failed_command"

        while true; do
            if [ "$skippable" = "true" ]; then
                echo "Options: (r)etry, (s)kip this step, (q)uit installation."
            else
                echo "This step is critical and cannot be skipped. Options: (r)etry, (q)uit installation."
            fi
            
            read -r -p "Enter your choice: " choice
            case "$choice" in
                r|R)
                    echo "Retrying '$cmd_description'..."
                    return 0 # Indicate retry
                    ;;
                s|S)
                    if [ "$skippable" = "true" ]; then
                        echo "Skipping '$cmd_description'."
                        return 1 # Indicate skip
                    else
                        echo "Invalid choice. This critical step cannot be skipped."
                    fi
                    ;;
                q|Q)
                    echo "Quitting installation as requested."
                    exit 1
                    ;;
                *)
                    echo "Invalid choice. Please enter 'r', 's', or 'q'."
                    ;;
            esac
        }

    execute_command_dotfiles() {
        local cmd_description="$1"
        local command_to_execute="$2"
        local skippable="$3"

        while true; do
            if eval "$command_to_execute"; then
                echo "SUCCESS: $cmd_description"
                return 0
            else
                if handle_failure_dotfiles "$cmd_description" "$command_to_execute" "$skippable"; then
                    continue
                else
                    if [ "$skippable" = "true" ]; then
                        return 1
                    else
                        echo "Critical command '$cmd_description' failed and cannot be skipped. Exiting."
                        exit 1
                    fi
                fi
            fi
        done
    }

    # Variables from outer script need to be explicitly passed or reconstructed.
    # Using hardcoded value for DOTFILES_BARE_DIR as it's static and known.
    local DOTFILES_BARE_DIR_CHROOT="/home/andres/dotfiles"
    local REPO_URL_CHROOT="https://github.com/andres-guzman/dotfiles.git"

    execute_command_dotfiles "Initialize bare dotfiles repository" "git init --bare \"$DOTFILES_BARE_DIR_CHROOT\"" "false"
    execute_command_dotfiles "Configure git for dotfiles" "git --git-dir=\"$DOTFILES_BARE_DIR_CHROOT\" --work-tree=/home/andres config --local status.showUntrackedFiles no" "false"
    execute_command_dotfiles "Add origin remote to bare dotfiles repo" "git --git-dir=\"$DOTFILES_BARE_DIR_CHROOT\" --work-tree=/home/andres remote add origin \"$REPO_URL_CHROOT\"" "false"
    execute_command_dotfiles "Fetch from origin remote" "git --git-dir=\"$DOTFILES_BARE_DIR_CHROOT\" --work-tree=/home/andres fetch origin main" "false"
    execute_command_dotfiles "Checkout main branch from bare dotfiles repo" "git --git-dir=\"$DOTFILES_BARE_DIR_CHROOT\" --work-tree=/home/andres checkout --force main" "false"

    echo "Adjusting dotfile locations if necessary..."
    # Move fonts
    if [ -d "/home/andres/fonts" ]; then
        mkdir -p /home/andres/.local/share/fonts
        execute_command_dotfiles "Move fonts" "mv /home/andres/fonts/* /home/andres/.local/share/fonts/" "true"
        rmdir /home/andres/fonts 2>/dev/null || true # Ignore error if dir not empty
    fi
    # Move themes
    if [ -d "/home/andres/themes" ]; then
        mkdir -p /home/andres/.local/share/themes
        execute_command_dotfiles "Move themes" "mv /home/andres/themes/* /home/andres/.local/share/themes/" "true"
        rmdir /home/andres/themes 2>/dev/null || true
    fi
    # Move systemd user services
    if [ -d "/home/andres/systemd" ]; then
        mkdir -p /home/andres/.config/systemd/user
        execute_command_dotfiles "Move systemd user services" "mv /home/andres/systemd/* /home/andres/.config/systemd/user/" "true"
        rmdir /home/andres/systemd 2>/dev/null || true
    fi
EOL_DOTFILES


# ---------------------------------------------------
# Step 8: Post-Installation User Configuration and Service Activation
# ---------------------------------------------------
echo -e "${CYAN}--- Step 8: Post-Installation User Configuration and Service Activation ---${NOCOLOR}"
echo -e "${YELLOW}Setting default shell to Zsh and enabling uwsm service...${NOCOLOR}"

execute_command "Set default shell to Zsh for user 'andres'" "arch-chroot /mnt usermod --shell /usr/bin/zsh andres" "false"
execute_command "Enable uwsm service" "arch-chroot /mnt systemctl enable uwsm@andres.service" "false"

# ---------------------------------------------------
# Step 9: Final Clean-up and Reboot
# ---------------------------------------------------
echo -e "${CYAN}--- Step 9: Final Clean-up and Reboot ---${NOCOLOR}"
echo -e "${GREEN}Installation complete. Unmounting partitions and cleaning up temporary files.${NOCOLOR}"

execute_command "Clean up temporary dotfiles directory" "rm -rf \"$DOTFILES_TEMP_NVME_DIR\"" "true"
execute_command "Unmount /mnt" "umount -R /mnt" "false"

echo -e "${GREEN}You can now reboot into your new system.${NOCOLOR}"
