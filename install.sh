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

# IMPORTANT: This script assumes it is downloaded as a single file to a location
# on the RAM disk (e.g., /root/install.sh) and executed from there.
# It will then fetch pkg_official.txt and pkg_aur.txt directly to the NVMe disk.

# ---------------------------------------------------
# Step 1: Disk Partitioning and Formatting
# ---------------------------------------------------
# Set the device variable for clarity.
# WARNING: This is a destructive operation on this device.
DRIVE="/dev/nvme0n1"

echo -e "${CYAN}--- Step 1: Disk Partitioning and Formatting ---${NOCOLOR}"
echo -e "${YELLOW}Partitioning and formatting the drive: ${DRIVE}...${NOCOLOR}"

# Step 1-A: Partition the disk
# Create a new GPT partition table
parted -s "$DRIVE" mklabel gpt || { echo -e "${RED}Error: Failed to create GPT label on ${DRIVE}.${NOCOLOR}"; exit 1; }
# Create the EFI partition (1G)
parted -s "$DRIVE" mkpart primary fat32 1MiB 1025MiB || { echo -e "${RED}Error: Failed to create EFI partition.${NOCOLOR}"; exit 1; }
parted -s "$DRIVE" set 1 esp on || { echo -e "${RED}Error: Failed to set ESP flag on EFI partition.${NOCOLOR}"; exit 1; }
# Create the Swap partition (8G)
parted -s "$DRIVE" mkpart primary linux-swap 1025MiB 9249MiB || { echo -e "${RED}Error: Failed to create Swap partition.${NOCOLOR}"; exit 1; }
# Create the Root partition (the rest of the drive)
parted -s "$DRIVE" mkpart primary ext4 9249MiB 100% || { echo -e "${RED}Error: Failed to create Root partition.${NOCOLOR}"; exit 1; }

# Step 1-B: Format the partitions
mkfs.fat -F32 "${DRIVE}p1" || { echo -e "${RED}Error: Failed to format EFI partition.${NOCOLOR}"; exit 1; } # EFI
mkswap "${DRIVE}p2" || { echo -e "${RED}Error: Failed to format Swap partition.${NOCOLOR}"; exit 1; }        # Swap
mkfs.ext4 "${DRIVE}p3" || { echo -e "${RED}Error: Failed to format Root partition.${NOCOLOR}"; exit 1; }     # Root
swapon "${DRIVE}p2" || { echo -e "${RED}Error: Failed to enable Swap.${NOCOLOR}"; exit 1; }

# ---------------------------------------------------
# Step 2: Base System Installation
# ---------------------------------------------------
echo -e "${CYAN}--- Step 2: Base System Installation ---${NOCOLOR}"
echo -e "${YELLOW}Mounting partitions and installing base system...${NOCOLOR}"

# Step 2-A: Mount partitions
mount "${DRIVE}p3" /mnt || { echo -e "${RED}Error: Failed to mount Root partition.${NOCOLOR}"; exit 1; }
mkdir -p /mnt/boot || { echo -e "${RED}Error: Failed to create /mnt/boot directory.${NOCOLOR}"; exit 1; }
mount "${DRIVE}p1" /mnt/boot || { echo -e "${RED}Error: Failed to mount EFI partition.${NOCOLOR}"; exit 1; }

# Step 2-B: Install the base system and essential packages
# Adding verbose output for pacstrap to a log file on the NVMe.
echo -e "${YELLOW}Installing base system with pacstrap (output to /mnt/pacstrap.log)...${NOCOLOR}"
pacstrap /mnt base linux-firmware git sudo networkmanager nano efibootmgr 2>&1 | tee /mnt/pacstrap.log || { echo -e "${RED}Error: Failed to pacstrap base system. Check /mnt/pacstrap.log for details.${NOCOLOR}"; exit 1; }

# Step 2-C: Generate fstab
echo -e "${YELLOW}Generating fstab...${NOCOLOR}"
genfstab -U /mnt >> /mnt/etc/fstab || { echo -e "${RED}Error: Failed to generate fstab.${NOCOLOR}"; exit 1; }

# Install terminus-font and set console font for the live environment
echo -e "${YELLOW}Installing terminus-font for console display...${NOCOLOR}"
pacman -Sy --noconfirm terminus-font || { echo -e "${RED}Error: Failed to install terminus-font in live environment.${NOCOLOR}"; exit 1; }
echo -e "${YELLOW}Setting console font to ter-v16n...${NOCOLOR}"
setfont ter-v16n || { echo -e "${RED}Error: Failed to set console font in live environment.${NOCOLOR}"; exit 1; }


# ---------------------------------------------------
# Step 3: Prepare Dotfiles for Chroot
# ---------------------------------------------------
echo -e "${CYAN}--- Step 3: Preparing dotfiles for chroot access ---${NOCOLOR}"
echo -e "${YELLOW}Downloading package lists directly to NVMe for chroot access...${NOCOLOR}"

# Explicitly create /mnt/home/andres before creating the temporary directory
mkdir -p /mnt/home/andres || { echo -e "${RED}Error: Failed to create /mnt/home/andres directory on NVMe.${NOCOLOR}"; exit 1; }

# Create a temporary directory on the NVme disk for fetching dotfiles
DOTFILES_TEMP_NVME_DIR="/mnt/home/andres/temp_dotfiles_setup"
mkdir -p "$DOTFILES_TEMP_NVME_DIR" || { echo -e "${RED}Error: Failed to create temporary dotfiles directory on NVMe: $DOTFILES_TEMP_NVME_DIR.${NOCOLOR}"; exit 1; }

# Download pkg_official.txt directly to the NVMe drive with robust error handling
echo -e "${YELLOW}Attempting to download pkg_official.txt to ${DOTFILES_TEMP_NVME_DIR}...${NOCOLOR}"
curl -f -o "$DOTFILES_TEMP_NVME_DIR/pkg_official.txt" "$PKG_OFFICIAL_URL" || { 
    echo -e "${RED}Error: Failed to download pkg_official.txt to NVMe. Check URL: $PKG_OFFICIAL_URL and network connectivity.${NOCOLOR}"; 
    exit 1; 
}
# Verify download immediately
if [ ! -f "$DOTFILES_TEMP_NVME_DIR/pkg_official.txt" ]; then
    echo -e "${RED}Error: pkg_official.txt was not found after download attempt in ${DOTFILES_TEMP_NVME_DIR}. Download failed silently.${NOCOLOR}"; 
    exit 1;
fi
echo -e "${GREEN}pkg_official.txt downloaded successfully.${NOCOLOR}"

# Download pkg_aur.txt directly to the NVMe drive with robust error handling
echo -e "${YELLOW}Attempting to download pkg_aur.txt to ${DOTFILES_TEMP_NVME_DIR}...${NOCOLOR}"
curl -f -o "$DOTFILES_TEMP_NVME_DIR/pkg_aur.txt" "$PKG_AUR_URL" || { 
    echo -e "${RED}Error: Failed to download pkg_aur.txt to NVMe. Check URL: $PKG_AUR_URL and network connectivity.${NOCOLOR}"; 
    exit 1; 
}
# Verify download immediately
if [ ! -f "$DOTFILES_TEMP_NVME_DIR/pkg_aur.txt" ]; then
    echo -e "${RED}Error: pkg_aur.txt was not found after download attempt in ${DOTFILES_TEMP_NVME_DIR}. Download failed silently.${NOCOLOR}"; 
    exit 1;
fi
echo -e "${GREEN}pkg_aur.txt downloaded successfully.${NOCOLOR}"


# ---------------------------------------------------
# Step 4: System Configuration (Inside chroot)
# ---------------------------------------------------
echo -e "${CYAN}--- Step 4: System Configuration (Inside chroot) ---${NOCOLOR}"
echo -e "${YELLOW}Entering chroot environment to configure the system...${NOCOLOR}"

# Explicitly use /bin/sh for the chroot shell to avoid bash-specific issues
arch-chroot /mnt /bin/sh << EOF_CHROOT_SCRIPT
    # Ensure a basic PATH is set for sh
    export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

    # Step 4-A: Time, Locale, and Hostname
    echo "Configuring time, locale, and hostname..."
    ln -sf /usr/share/zoneinfo/America/La_Paz /etc/localtime || { echo "Error: Failed to set timezone."; exit 1; }
    hwclock --systohc || { echo "Error: Failed to set hardware clock."; exit 1; }

    # Set keyboard layout
    echo "KEYMAP=la-latin1" > /etc/vconsole.conf || { echo "Error: Failed to set keyboard layout."; exit 1; }

    # Robust sed for locale.gen
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
    # Robust sed for sudoers
    sed -i '/%wheel ALL=(ALL:ALL) ALL/s/^# //g' /etc/sudoers || { echo "Error: Failed to uncomment wheel group in sudoers."; exit 1; }

    # Step 4-C: Install Kernels and other core packages & Enable multilib
    echo "Installing Zen and Stable kernels, microcode, core utilities, and enabling multilib..."
    pacman -Syu --noconfirm linux-zen linux linux-headers linux-zen-headers intel-ucode || { echo "Error: Failed to install kernels and microcode."; exit 1; }
    pacman -S --noconfirm pipewire pipewire-pulse wireplumber zsh || { echo "Error: Failed to install core audio and zsh packages."; exit 1; }

    # Enable multilib repository
    # Using a simpler sed command to uncomment [multilib] and its Include line.
    # This assumes the Include line is immediately after [multilib].
    sed -i '/\[multilib\]/{n;s/^#//}' /etc/pacman.conf || { echo "Error: Failed to uncomment multilib section (Include line) in pacman.conf."; exit 1; }
    sed -i '/\[multilib\]/s/^#//' /etc/pacman.conf || { echo "Error: Failed to uncomment [multilib] header in pacman.conf."; exit 1; }
    # Perform a full system update and database synchronization after enabling multilib
    pacman -Syyu --noconfirm || { echo "Error: Failed to synchronize package databases and perform full system update after enabling multilib."; exit 1; }

    # Step 4-D: Bootloader Configuration
    echo "Configuring systemd-boot..."
    # Removed chown for /boot as FAT32 does not support Linux permissions.
    bootctl install || { echo "Error: Failed to install systemd-boot."; exit 1; }

    TODAY=\$(date +%Y-%m-%d) # Escaped for the inner shell

    # All echo commands for boot entries must run as root (default in arch-chroot).
    echo "default \${TODAY}_linux-zen.conf" > /boot/loader/loader.conf || { echo "Error: Failed to create loader.conf."; exit 1; }
    echo "timeout  0" >> /boot/loader/loader.conf
    echo "console-mode max" >> /boot/loader/loader.conf
    echo "editor   no" >> /boot/loader/loader.conf

    echo "title    Arch Linux Zen" > "/boot/loader/entries/\${TODAY}_linux-zen.conf" || { echo "Error: Failed to create linux-zen boot entry."; exit 1; }
    echo "linux    /vmlinuz-linux-zen" >> "/boot/loader/entries/\${TODAY}_linux-zen.conf"
    echo "initrd   /intel-ucode.img" >> "/boot/loader/entries/\${TODAY}_linux-zen.conf"
    echo "initrd   /initramfs-linux-zen.img" >> "/boot/loader/entries/\${TODAY}_linux-zen.conf"
    echo "options  root=UUID=\$(blkid -s UUID -o value /dev/nvme0n1p3) rw vt.global_cursor_default=0 nowatchdog ipv6.disable=1 mitigations=off" >> "/boot/loader/entries/\${TODAY}_linux-zen.conf"

    echo "title    Arch Linux" > "/boot/loader/entries/\${TODAY}_linux.conf" || { echo "Error: Failed to create linux boot entry."; exit 1; }
    echo "linux    /vmlinuz-linux" >> "/boot/loader/entries/\${TODAY}_linux.conf"
    echo "initrd   /intel-ucode.img" >> "/boot/loader/entries/\${TODAY}_linux.conf"
    echo "initrd   /initramfs-linux.img" >> "/boot/loader/entries/\${TODAY}_linux.conf"
    echo "options  root=UUID=\$(blkid -s UUID -o value /dev/nvme0n1p3) rw vt.global_cursor_default=0 nowatchdog ipv6.disable=1 mitigations=off" >> "/boot/loader/entries/\${TODAY}_linux.conf"
    
    # Step 4-E: Enable getty service for auto-login (uwsm will be enabled later)
    systemctl enable getty@tty1.service || { echo "Error: Failed to enable getty service."; exit 1; }
EOF_CHROOT_SCRIPT

echo -e "${YELLOW}Exiting chroot environment...${NOCOLOR}"

# ---------------------------------------------------
# Step 5: Automounting Other Drives
# ---------------------------------------------------
echo -e "${CYAN}--- Step 5: Automounting Other Drives ---${NOCOLOR}"
echo -e "${YELLOW}Mounting other hard drives...${NOCOLOR}"

# Create mount points for the drives
mkdir -p /mnt/Documents /mnt/Videos /mnt/Backup || { echo -e "${RED}Error: Failed to create mount points for external drives.${NOCOLOR}"; exit 1; }

# Get the UUIDs for your three hard drives
DOCS_UUID=$(blkid -s UUID -o value /dev/sda) || { echo -e "${RED}Error: /dev/sda not found or UUID not readable. Check your external drives are connected and detected.${NOCOLOR}"; exit 1; }
VIDEOS_UUID=$(blkid -s UUID -o value /dev/sdb) || { echo -e "${RED}Error: /dev/sdb not found or UUID not readable. Check your external drives are connected and detected.${NOCOLOR}"; exit 1; }
BACKUP_UUID=$(blkid -s UUID -o value /dev/sdc) || { echo -e "${RED}Error: /dev/sdc not found or UUID not readable. Check your external drives are connected and detected.${NOCOLOR}"; exit 1; }

# Add the entries to fstab.
echo "" >> /mnt/etc/fstab
echo "# Mounting other drives" >> /mnt/etc/fstab
echo "UUID=${DOCS_UUID} /mnt/Documents ext4 defaults,nodev,nosuid,noexec,nofail,x-gvfs-show,user 0 0" >> /mnt/etc/fstab
echo "UUID=${VIDEOS_UUID} /mnt/Videos ext4 defaults,nodev,nosuid,noexec,nofail,x-gvfs-show,user 0 0" >> /mnt/etc/fstab
echo "UUID=${BACKUP_UUID} /mnt/Backup ext4 defaults,nodev,nosuid,noexec,nofail,x-gvfs-show,user 0 0" >> /mnt/etc/fstab

# ---------------------------------------------------
# Step 6: Hyprland and Other Package Installation
# ---------------------------------------------------
echo -e "${CYAN}--- Step 6: Hyprland and Other Package Installation ---${NOCOLOR}"

# Step 6-A: Install Official Packages
echo -e "${YELLOW}Installing official packages from pkg_official.txt...${NOCOLOR}"
# Path adjusted to fetch from NVMe temporary directory
arch-chroot /mnt pacman -Syu --noconfirm - < "$DOTFILES_TEMP_NVME_DIR/pkg_official.txt" || { echo -e "${RED}Error: Failed to install official packages.${NOCOLOR}"; exit 1; }

# Step 6-B: Install AUR Helper (Yay)
echo -e "${YELLOW}Installing yay from AUR...${NOCOLOR}"
# Clone yay-bin and build as the 'andres' user in the new root
arch-chroot /mnt bash << EOL
    git clone https://aur.archlinux.org/yay-bin.git /home/andres/yay-bin || { echo "Error: Failed to clone yay-bin inside chroot."; exit 1; }
    chown -R andres:andres /home/andres/yay-bin || { echo "Error: Failed to change ownership of yay-bin inside chroot."; exit 1; }
    # Run makepkg as the 'andres' user
    sudo -u andres bash -c "cd /home/andres/yay-bin && makepkg -si --noconfirm" || { echo "Error: Failed to build and install yay inside chroot."; exit 1; }
EOL

# Step 6-C: Install AUR Packages with Yay
echo -e "${YELLOW}Installing AUR packages from pkg_aur.txt...${NOCOLOR}"
# Ensure yay is run as the 'andres' user and uses the correct path to pkg_aur.txt
arch-chroot /mnt sudo -u andres bash << EOL
    yay -S --noconfirm - < "$DOTFILES_TEMP_NVME_DIR/pkg_aur.txt" || { echo "Error: Failed to install AUR packages inside chroot."; exit 1; }
EOL

# ---------------------------------------------------
# Step 7: Dotfile Restoration
# ---------------------------------------------------
echo -e "${CYAN}--- Step 7: Dotfile Restoration ---${NOCOLOR}"
echo -e "${YELLOW}Setting up bare dotfiles repository and restoring configurations to /home/andres/...${NOCOLOR}"
# This step initializes the bare repository in the new system's home directory
arch-chroot /mnt bash << EOL
    # Initialize the bare repository
    git init --bare "$DOTFILES_BARE_DIR" || { echo "Error: Failed to initialize bare dotfiles repository."; exit 1; }
    # Configure git to use the bare repo for dotfile management
    git --git-dir="$DOTFILES_BARE_DIR" --work-tree=/home/andres config --local status.showUntrackedFiles no || { echo "Error: Failed to configure git for dotfiles."; exit 1; }
    # The 'checkout' step will now clone from the remote repo directly to the user's home
    # as we no longer have a local full clone in /mnt/home/andres/
    git --git-dir="$DOTFILES_BARE_DIR" --work-tree=/home/andres remote add origin "$REPO_URL" || { echo "Error: Failed to add origin remote to bare dotfiles repo."; exit 1; }
    git --git-dir="$DOTFILES_BARE_DIR" --work-tree=/home/andres fetch origin main || { echo "Error: Failed to fetch from origin remote."; exit 1; }
    git --git-dir="$DOTFILES_BARE_DIR" --work-tree=/home/andres checkout --force main || { echo "Error: Failed to checkout main branch from bare dotfiles repo."; exit 1; }
EOL

# Assuming user's dotfiles repo structure is mostly flat or directly maps to $HOME/.config etc.
echo -e "${YELLOW}Adjusting dotfile locations if necessary...${NOCOLOR}"
arch-chroot /mnt bash << EOL
    # Move fonts to ~/.local/share/fonts (if they were at the root of your dotfiles repo)
    if [ -d "/home/andres/fonts" ]; then
        mkdir -p /home/andres/.local/share/fonts
        mv /home/andres/fonts/* /home/andres/.local/share/fonts/ || { echo "Error: Failed to move fonts."; exit 1; }
        rmdir /home/andres/fonts
    fi
    # Move themes to ~/.local/share/themes (if they were at the root of your dotfiles repo)
    if [ -d "/home/andres/themes" ]; then
        mkdir -p /home/andres/.local/share/themes
        mv /home/andres/themes/* /home/andres/.local/share/themes/ || { echo "Error: Failed to move themes."; exit 1; }
        rmdir /home/andres/themes
    fi
    # Move systemd user services to ~/.config/systemd/user (if they were at the root of your dotfiles repo)
    if [ -d "/home/andres/systemd" ]; then
        mkdir -p /home/andres/.config/systemd/user
        mv /home/andres/systemd/* /home/andres/.config/systemd/user/ || { echo "Error: Failed to move systemd user services."; exit 1; }
        rmdir /home/andres/systemd
    fi
EOL


# ---------------------------------------------------
# Step 8: Post-Installation User Configuration and Service Activation
# ---------------------------------------------------
echo -e "${CYAN}--- Step 8: Post-Installation User Configuration and Service Activation ---${NOCOLOR}"
echo -e "${YELLOW}Setting default shell to Zsh and enabling uwsm service...${NOCOLOR}"

# Set default shell to Zsh for user 'andres'
arch-chroot /mnt usermod --shell /usr/bin/zsh andres || { echo "Error: Failed to set default shell for 'andres' to zsh."; exit 1; }

# Enable uwsm service for user 'andres'
arch-chroot /mnt systemctl enable uwsm@andres.service || { echo "Error: Failed to enable uwsm service."; exit 1; }

# ---------------------------------------------------
# Step 9: Final Clean-up and Reboot
# ---------------------------------------------------
echo -e "${CYAN}--- Step 9: Final Clean-up and Reboot ---${NOCOLOR}"
echo -e "${GREEN}Installation complete. Unmounting partitions and cleaning up temporary files.${NOCOLOR}"

# Clean up the temporary dotfiles directory from NVMe
rm -rf "$DOTFILES_TEMP_NVME_DIR" || { echo "Warning: Failed to remove temporary dotfiles directory from NVMe. Please clean up manually."; }

umount -R /mnt || { echo -e "${RED}Error: Failed to unmount /mnt. Please unmount manually.${NOCOLOR}"; exit 1; }
echo -e "${GREEN}You can now reboot into your new system.${NOCOLOR}"
