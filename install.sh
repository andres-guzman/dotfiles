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

# Define the repository URL
REPO_URL="https://github.com/andres-guzman/dotfiles.git"
# This will be the location of the *bare* dotfiles repo in the new system's /home/andres/
DOTFILES_BARE_DIR="/home/andres/dotfiles" 

# IMPORTANT: This script assumes it is run from within a *full working clone*
# of your dotfiles repository in the live environment.
# E.g., you first ran:
#   git clone https://github.com/andres-guzman/dotfiles.git /root/dotfiles_temp
#   cd /root/dotfiles_temp
#   ./install.sh
# The variable DOTFILES_WORK_DIR will point to this temporary clone.
DOTFILES_WORK_DIR=$(pwd)

# ---------------------------------------------------
# Step 1: Prepare for installation
# ---------------------------------------------------
echo -e "${CYAN}--- Step 1: Preparing for installation ---${NOCOLOR}"
echo -e "${YELLOW}Copying installation files to new root for chroot access...${NOCOLOR}"

# Copy the entire dotfiles working directory into the new root's /home/andres/
# This makes pkg_official.txt, pkg_aur.txt, and install.sh accessible inside chroot.
# We'll clean this up later in Step 9.
mkdir -p /mnt/home/andres/ || { echo -e "${RED}Error: Failed to create /mnt/home/andres directory.${NOCOLOR}"; exit 1; }
cp -r "$DOTFILES_WORK_DIR" /mnt/home/andres/ || { echo -e "${RED}Error: Failed to copy dotfiles working directory to /mnt/home/andres/.${NOCOLOR}"; exit 1; }

# Update DOTFILES_WORK_DIR to reflect its location inside the /mnt environment
# when accessed from chroot. It will be /home/andres/dotfiles_temp if the initial clone
# was named dotfiles_temp. Let's assume it's simply 'dotfiles' after copying.
DOTFILES_IN_CHROOT_PATH="/home/andres/$(basename "$DOTFILES_WORK_DIR")"


# ---------------------------------------------------
# Step 2: Disk Partitioning and Formatting
# ---------------------------------------------------
# Set the device variable for clarity.
# WARNING: This is a destructive operation on this device.
DRIVE="/dev/nvme0n1"

echo -e "${CYAN}--- Step 2: Disk Partitioning and Formatting ---${NOCOLOR}"
echo -e "${YELLOW}Partitioning and formatting the drive: ${DRIVE}...${NOCOLOR}"

# Step 2-A: Partition the disk
# Create a new GPT partition table
parted -s "$DRIVE" mklabel gpt || { echo -e "${RED}Error: Failed to create GPT label on ${DRIVE}.${NOCOLOR}"; exit 1; }
# Create the EFI partition (1G)
parted -s "$DRIVE" mkpart primary fat32 1MiB 1025MiB || { echo -e "${RED}Error: Failed to create EFI partition.${NOCOLOR}"; exit 1; }
parted -s "$DRIVE" set 1 esp on || { echo -e "${RED}Error: Failed to set ESP flag on EFI partition.${NOCOLOR}"; exit 1; }
# Create the Swap partition (8G)
parted -s "$DRIVE" mkpart primary linux-swap 1025MiB 9249MiB || { echo -e "${RED}Error: Failed to create Swap partition.${NOCOLOR}"; exit 1; }
# Create the Root partition (the rest of the drive)
parted -s "$DRIVE" mkpart primary ext4 9249MiB 100% || { echo -e "${RED}Error: Failed to create Root partition.${NOCOLOR}"; exit 1; }

# Step 2-B: Format the partitions
mkfs.fat -F32 "${DRIVE}p1" || { echo -e "${RED}Error: Failed to format EFI partition.${NOCOLOR}"; exit 1; } # EFI
mkswap "${DRIVE}p2" || { echo -e "${RED}Error: Failed to format Swap partition.${NOCOLOR}"; exit 1; }        # Swap
mkfs.ext4 "${DRIVE}p3" || { echo -e "${RED}Error: Failed to format Root partition.${NOCOLOR}"; exit 1; }     # Root
swapon "${DRIVE}p2" || { echo -e "${RED}Error: Failed to enable Swap.${NOCOLOR}"; exit 1; }

# ---------------------------------------------------
# Step 3: Base System Installation
# ---------------------------------------------------
echo -e "${CYAN}--- Step 3: Base System Installation ---${NOCOLOR}"
echo -e "${YELLOW}Mounting partitions and installing base system...${NOCOLOR}"

# Step 3-A: Mount partitions
mount "${DRIVE}p3" /mnt || { echo -e "${RED}Error: Failed to mount Root partition.${NOCOLOR}"; exit 1; }
mkdir -p /mnt/boot || { echo -e "${RED}Error: Failed to create /mnt/boot directory.${NOCOLOR}"; exit 1; }
mount "${DRIVE}p1" /mnt/boot || { echo -e "${RED}Error: Failed to mount EFI partition.${NOCOLOR}"; exit 1; }

# Step 3-B: Install the base system and essential packages
# Removed 'systemd-boot' from pacstrap as it's not a package itself.
# 'bootctl' (for systemd-boot) is part of 'systemd' which comes with 'base'.
echo -e "${YELLOW}Installing base system with pacstrap...${NOCOLOR}"
pacstrap /mnt base linux-firmware git sudo networkmanager nano efibootmgr || { echo -e "${RED}Error: Failed to pacstrap base system.${NOCOLOR}"; exit 1; }

# Step 3-C: Generate fstab
echo -e "${YELLOW}Generating fstab...${NOCOLOR}"
genfstab -U /mnt >> /mnt/etc/fstab || { echo -e "${RED}Error: Failed to generate fstab.${NOCOLOR}"; exit 1; }

# ---------------------------------------------------
# Step 4: System Configuration (Inside chroot)
# ---------------------------------------------------
echo -e "${CYAN}--- Step 4: System Configuration (Inside chroot) ---${NOCOLOR}"
echo -e "${YELLOW}Entering chroot environment to configure the system...${NOCOLOR}"

arch-chroot /mnt << EOF
    # Step 4-A: Time, Locale, and Hostname
    echo -e "${YELLOW}Configuring time, locale, and hostname...${NOCOLOR}"
    ln -sf /usr/share/zoneinfo/America/La_Paz /etc/localtime || { echo -e "${RED}Error: Failed to set timezone.${NOCOLOR}"; exit 1; }
    hwclock --systohc || { echo -e "${RED}Error: Failed to set hardware clock.${NOCOLOR}"; exit 1; }

    # Set keyboard layout
    echo "KEYMAP=la-latin1" > /etc/vconsole.conf || { echo -e "${RED}Error: Failed to set keyboard layout.${NOCOLOR}"; exit 1; }

    sed -i 's/#en_CA.UTF-8 UTF-8/en_CA.UTF-8 UTF-8/' /etc/locale.gen || { echo -e "${RED}Error: Failed to uncomment en_CA locale.${NOCOLOR}"; exit 1; }
    sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen || { echo -e "${RED}Error: Failed to uncomment en_US locale.${NOCOLOR}"; exit 1; }
    sed -i 's/#es_BO.UTF-8 UTF-8/es_BO.UTF-8 UTF-8/' /etc/locale.gen || { echo -e "${RED}Error: Failed to uncomment es_BO locale.${NOCOLOR}"; exit 1; }
    locale-gen || { echo -e "${RED}Error: Failed to generate locales.${NOCOLOR}"; exit 1; }
    echo "LANG=en_US.UTF-8" > /etc/locale.conf || { echo -e "${RED}Error: Failed to set LANG in locale.conf.${NOCOLOR}"; exit 1; }

    echo "archlinux" > /etc/hostname || { echo -e "${RED}Error: Failed to set hostname.${NOCOLOR}"; exit 1; }
    echo "127.0.0.1   localhost" >> /etc/hosts
    echo "::1         localhost" >> /etc/hosts
    echo "127.0.1.1   archlinux.localdomain archlinux" >> /etc/hosts

    # Step 4-B: User and Sudo Configuration
    echo -e "${YELLOW}Creating user 'andres' and configuring sudo...${NOCOLOR}"
    useradd -m andres || { echo -e "${RED}Error: Failed to create user 'andres'.${NOCOLOR}"; exit 1; }
    echo "andres:password" | chpasswd || { echo -e "${RED}Error: Failed to set password for 'andres'.${NOCOLOR}"; exit 1; } # REMEMBER TO CHANGE PASSWORD
    usermod -aG wheel andres || { echo -e "${RED}Error: Failed to add 'andres' to wheel group.${NOCOLOR}"; exit 1; }
    sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers || { echo -e "${RED}Error: Failed to uncomment wheel group in sudoers.${NOCOLOR}"; exit 1; }

    # Step 4-C: Install Kernels and other core packages
    echo -e "${YELLOW}Installing Zen and Stable kernels, microcode, and core utilities...${NOCOLOR}"
    pacman -Syu --noconfirm linux-zen linux linux-headers linux-zen-headers intel-ucode || { echo -e "${RED}Error: Failed to install kernels and microcode.${NOCOLOR}"; exit 1; }
    # Removed git, sudo, networkmanager, nano, efibootmgr, systemd-boot as they are either in pacstrap or not actual package names.
    pacman -S --noconfirm pipewire pipewire-pulse wireplumber zsh || { echo -e "${RED}Error: Failed to install core audio and zsh packages.${NOCOLOR}"; exit 1; }

    # Step 4-D: Bootloader Configuration
    echo -e "${YELLOW}Configuring systemd-boot...${NOCOLOR}"
    bootctl install || { echo -e "${RED}Error: Failed to install systemd-boot.${NOCOLOR}"; exit 1; }

    TODAY=$(date +%Y-%m-%d)

    echo "default ${TODAY}_linux-zen.conf" > /boot/loader/loader.conf || { echo -e "${RED}Error: Failed to create loader.conf.${NOCOLOR}"; exit 1; }
    echo "timeout  0" >> /boot/loader/loader.conf
    echo "console-mode max" >> /boot/loader/loader.conf
    echo "editor   no" >> /boot/loader/loader.conf

    echo "title    Arch Linux Zen" > "/boot/loader/entries/${TODAY}_linux-zen.conf" || { echo -e "${RED}Error: Failed to create linux-zen boot entry.${NOCOLOR}"; exit 1; }
    echo "linux    /vmlinuz-linux-zen" >> "/boot/loader/entries/${TODAY}_linux-zen.conf"
    echo "initrd   /intel-ucode.img" >> "/boot/loader/entries/${TODAY}_linux-zen.conf"
    echo "initrd   /initramfs-linux-zen.img" >> "/boot/loader/entries/${TODAY}_linux-zen.conf"
    echo "options  root=UUID=$(blkid -s UUID -o value /dev/nvme0n1p3) rw vt.global_cursor_default=0 nowatchdog ipv6.disable=1 mitigations=off" >> "/boot/loader/entries/${TODAY}_linux-zen.conf"

    echo "title    Arch Linux" > "/boot/loader/entries/${TODAY}_linux.conf" || { echo -e "${RED}Error: Failed to create linux boot entry.${NOCOLOR}"; exit 1; }
    echo "linux    /vmlinuz-linux" >> "/boot/loader/entries/${TODAY}_linux.conf"
    echo "initrd   /intel-ucode.img" >> "/boot/loader/entries/${TODAY}_linux.conf"
    echo "initrd   /initramfs-linux.img" >> "/boot/loader/entries/${TODAY}_linux.conf"
    echo "options  root=UUID=$(blkid -s UUID -o value /dev/nvme0n1p3) rw vt.global_cursor_default=0 nowatchdog ipv6.disable=1 mitigations=off" >> "/boot/loader/entries/${TODAY}_linux.conf"
    
    # Step 4-E: Enable getty service for auto-login (uwsm will be enabled later)
    # The 'uwsm@andres.service' cannot be enabled here because uwsm is installed later in Step 6.
    systemctl enable getty@tty1.service || { echo -e "${RED}Error: Failed to enable getty service.${NOCOLOR}"; exit 1; }
EOF

echo -e "${YELLOW}Exiting chroot environment...${NOCOLOR}"

# ---------------------------------------------------
# Step 5: Automounting Other Drives
# ---------------------------------------------------
echo -e "${CYAN}--- Step 5: Automounting Other Drives ---${NOCOLOR}"
echo -e "${YELLOW}Mounting other hard drives...${NOCOLOR}"

# Create mount points for the drives
mkdir -p /mnt/Documents /mnt/Videos /mnt/Backup || { echo -e "${RED}Error: Failed to create mount points for external drives.${NOCOLOR}"; exit 1; }

# Get the UUIDs for your three hard drives
# Note: These UUIDs must be stable and the devices must be present.
# It's assumed /dev/sda, /dev/sdb, /dev/sdc are your external drives in this order.
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
# Use --noconfirm for automated installation. Path adjusted to DOTFILES_IN_CHROOT_PATH.
arch-chroot /mnt pacman -Syu --noconfirm - < "$DOTFILES_IN_CHROOT_PATH/pkg_official.txt" || { echo -e "${RED}Error: Failed to install official packages.${NOCOLOR}"; exit 1; }

# Step 6-B: Install AUR Helper (Yay)
echo -e "${YELLOW}Installing yay from AUR...${NOCOLOR}"
# Clone yay-bin and build as the 'andres' user in the new root
arch-chroot /mnt bash << EOL
    git clone https://aur.archlinux.org/yay-bin.git /home/andres/yay-bin || { echo -e "${RED}Error: Failed to clone yay-bin inside chroot.${NOCOLOR}"; exit 1; }
    chown -R andres:andres /home/andres/yay-bin || { echo -e "${RED}Error: Failed to change ownership of yay-bin inside chroot.${NOCOLOR}"; exit 1; }
    # Run makepkg as the 'andres' user
    sudo -u andres bash -c "cd /home/andres/yay-bin && makepkg -si --noconfirm" || { echo -e "${RED}Error: Failed to build and install yay inside chroot.${NOCOLOR}"; exit 1; }
EOL

# Step 6-C: Install AUR Packages with Yay
echo -e "${YELLOW}Installing AUR packages from pkg_aur.txt...${NOCOLOR}"
# Ensure yay is run as the 'andres' user and uses the correct path to pkg_aur.txt
arch-chroot /mnt sudo -u andres bash << EOL
    yay -S --noconfirm - < "$DOTFILES_IN_CHROOT_PATH/pkg_aur.txt" || { echo -e "${RED}Error: Failed to install AUR packages inside chroot.${NOCOLOR}"; exit 1; }
EOL

# ---------------------------------------------------
# Step 7: Dotfile Restoration
# ---------------------------------------------------
echo -e "${CYAN}--- Step 7: Dotfile Restoration ---${NOCOLOR}"
echo -e "${YELLOW}Setting up bare dotfiles repository and restoring configurations to /home/andres/...${NOCOLOR}"
# This step initializes the bare repository in the new system's home directory
arch-chroot /mnt bash << EOL
    # Initialize the bare repository
    git init --bare "$DOTFILES_BARE_DIR" || { echo -e "${RED}Error: Failed to initialize bare dotfiles repository.${NOCOLOR}"; exit 1; }
    # Configure git to use the bare repo for dotfile management
    git --git-dir="$DOTFILES_BARE_DIR" --work-tree=/home/andres config --local status.showUntrackedFiles no || { echo -e "${RED}Error: Failed to configure git for dotfiles.${NOCOLOR}"; exit 1; }
    # Checkout files from the previously copied working directory to the user's home
    # We are checking out from the temporary working directory that was copied into /mnt/home/andres/
    git --git-dir="$DOTFILES_BARE_DIR" --work-tree=/home/andres checkout --force "$(basename "$DOTFILES_WORK_DIR")" || { echo -e "${RED}Error: Failed to checkout dotfiles from copied working directory.${NOCOLOR}"; exit 1; }
    # We need to manually copy specific dotfiles to their locations that git won't handle well
    # or where the repository structure doesn't perfectly match the target.
    # e.g., if .zshrc is at the root of the repo, it will be checked out to /home/andres/.zshrc
    # If fonts/ is at the root of the repo, it will be in /home/andres/fonts/ - we will move them.
EOL

# Assuming user's dotfiles repo structure is mostly flat or directly maps to $HOME/.config etc.
# If your dotfiles repo has structures like 'fonts/' or 'themes/' directly at its root,
# these files would be checked out to /home/andres/fonts/ and /home/andres/themes/.
# We need to move them to their correct XDG locations if that's the case.
echo -e "${YELLOW}Adjusting dotfile locations if necessary...${NOCOLOR}"
arch-chroot /mnt bash << EOL
    # Move fonts to ~/.local/share/fonts (if they were at the root of your dotfiles repo)
    if [ -d "/home/andres/fonts" ]; then
        mkdir -p /home/andres/.local/share/fonts
        mv /home/andres/fonts/* /home/andres/.local/share/fonts/ || { echo -e "${RED}Error: Failed to move fonts.${NOCOLOR}"; exit 1; }
        rmdir /home/andres/fonts
    fi
    # Move themes to ~/.local/share/themes (if they were at the root of your dotfiles repo)
    if [ -d "/home/andres/themes" ]; then
        mkdir -p /home/andres/.local/share/themes
        mv /home/andres/themes/* /home/andres/.local/share/themes/ || { echo -e "${RED}Error: Failed to move themes.${NOCOLOR}"; exit 1; }
        rmdir /home/andres/themes
    fi
    # Move systemd user services to ~/.config/systemd/user (if they were at the root of your dotfiles repo)
    if [ -d "/home/andres/systemd" ]; then
        mkdir -p /home/andres/.config/systemd/user
        mv /home/andres/systemd/* /home/andres/.config/systemd/user/ || { echo -e "${RED}Error: Failed to move systemd user services.${NOCOLOR}"; exit 1; }
        rmdir /home/andres/systemd
    fi
EOL


# ---------------------------------------------------
# Step 8: Post-Installation User Configuration and Service Activation
# ---------------------------------------------------
echo -e "${CYAN}--- Step 8: Post-Installation User Configuration and Service Activation ---${NOCOLOR}"
echo -e "${YELLOW}Setting default shell to Zsh and enabling uwsm service...${NOCOLOR}"

# Set default shell to Zsh for user 'andres'
# Zsh is now installed as part of the official packages in Step 6-A
arch-chroot /mnt usermod --shell /usr/bin/zsh andres || { echo -e "${RED}Error: Failed to set default shell for 'andres' to zsh.${NOCOLOR}"; exit 1; }

# Enable uwsm service for user 'andres'
# uwsm is now installed as part of the official packages in Step 6-A
arch-chroot /mnt systemctl enable uwsm@andres.service || { echo -e "${RED}Error: Failed to enable uwsm service.${NOCOLOR}"; exit 1; }

# ---------------------------------------------------
# Step 9: Final Clean-up and Reboot
# ---------------------------------------------------
echo -e "${CYAN}--- Step 9: Final Clean-up and Reboot ---${NOCOLOR}"
echo -e "${GREEN}Installation complete. Unmounting partitions and cleaning up temporary files.${NOCOLOR}"

# Clean up the temporary dotfiles working directory from /mnt/home/andres/
rm -rf /mnt/home/andres/$(basename "$DOTFILES_WORK_DIR") || { echo -e "${RED}Warning: Failed to remove temporary dotfiles working directory from /mnt/home/andres/. Please clean up manually.${NOCOLOR}"; }

umount -R /mnt || { echo -e "${RED}Error: Failed to unmount /mnt. Please unmount manually.${NOCOLOR}"; exit 1; }
echo -e "${GREEN}You can now reboot into your new system.${NOCOLOR}"
