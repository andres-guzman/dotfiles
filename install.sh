#!/bin/bash

# Define the repository URL
REPO_URL="https://github.com/andres-guzman/dotfiles.git"
DOTFILES_DIR="$HOME/dotfiles"

# ---------------------------------------------------
# Step 1: Clone the dotfiles repository
# ---------------------------------------------------
echo "Cloning dotfiles repository..."
git clone --bare "$REPO_URL" "$DOTFILES_DIR"

# ---------------------------------------------------
# Step 2: Disk Partitioning and Formatting
# ---------------------------------------------------
# Set the device variable for clarity.
# WARNING: This is a destructive operation on this device.
DRIVE="/dev/nvme0n1"

echo "Partitioning and formatting the drive..."

# Step 2-A: Partition the disk
parted -s "$DRIVE" mklabel gpt
parted -s "$DRIVE" mkpart primary fat32 1MiB 1025MiB
parted -s "$DRIVE" set 1 esp on
parted -s "$DRIVE" mkpart primary linux-swap 1025MiB 9249MiB
parted -s "$DRIVE" mkpart primary ext4 9249MiB 100%

# Step 2-B: Format the partitions
mkfs.fat -F32 "${DRIVE}p1" # EFI
mkswap "${DRIVE}p2"        # Swap
mkfs.ext4 "${DRIVE}p3"     # Root
swapon "${DRIVE}p2"

# ---------------------------------------------------
# Step 3: Base System Installation
# ---------------------------------------------------
echo "Mounting partitions and installing base system..."

# Step 3-A: Mount partitions
mount "${DRIVE}p3" /mnt
mkdir /mnt/boot
mount "${DRIVE}p1" /mnt/boot

# Step 3-B: Install the base system and essential packages
pacstrap /mnt base linux-firmware git sudo networkmanager nano efibootmgr systemd-boot

# Step 3-C: Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

# ---------------------------------------------------
# Step 4: System Configuration (Inside chroot)
# ---------------------------------------------------
echo "Entering chroot environment to configure the system..."

arch-chroot /mnt << EOF
    # Step 4-A: Time, Locale, and Hostname
    ln -sf /usr/share/zoneinfo/America/La_Paz /etc/localtime
    hwclock --systohc

    # Set keyboard layout
    echo "KEYMAP=la-latin1" > /etc/vconsole.conf

    sed -i 's/#en_CA.UTF-8 UTF-8/en_CA.UTF-8 UTF-8/' /etc/locale.gen
    sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
    sed -i 's/#es_BO.UTF-8 UTF-8/es_BO.UTF-8 UTF-8/' /etc/locale.gen
    locale-gen
    echo "LANG=en_US.UTF-8" > /etc/locale.conf

    echo "archlinux" > /etc/hostname
    echo "127.0.0.1   localhost" >> /etc/hosts
    echo "::1         localhost" >> /etc/hosts
    echo "127.0.1.1   archlinux.localdomain archlinux" >> /etc/hosts

    # Step 4-B: User and Sudo Configuration
    useradd -m andres
    echo "andres:password" | chpasswd
    usermod -aG wheel andres
    sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

    # Step 4-C: Install Kernels and other core packages
    pacman -Syu --noconfirm linux-zen linux linux-headers linux-zen-headers intel-ucode
    pacman -S --noconfirm git sudo networkmanager nano efibootmgr systemd-boot pipewire pipewire-pulse wireplumber zsh

    # Step 4-D: Bootloader Configuration
    bootctl install

    TODAY=$(date +%Y-%m-%d)

    echo "default ${TODAY}_linux-zen.conf" > /boot/loader/loader.conf
    echo "timeout  0" >> /boot/loader/loader.conf
    echo "console-mode max" >> /boot/loader/loader.conf
    echo "editor   no" >> /boot/loader/loader.conf

    echo "title    Arch Linux Zen" > "/boot/loader/entries/${TODAY}_linux-zen.conf"
    echo "linux    /vmlinuz-linux-zen" >> "/boot/loader/entries/${TODAY}_linux-zen.conf"
    echo "initrd   /intel-ucode.img" >> "/boot/loader/entries/${TODAY}_linux-zen.conf"
    echo "initrd   /initramfs-linux-zen.img" >> "/boot/loader/entries/${TODAY}_linux-zen.conf"
    echo "options  root=UUID=$(blkid -s UUID -o value /dev/nvme0n1p3) rw vt.global_cursor_default=0 nowatchdog ipv6.disable=1 mitigations=off" >> "/boot/loader/entries/${TODAY}_linux-zen.conf"

    echo "title    Arch Linux" > "/boot/loader/entries/${TODAY}_linux.conf"
    echo "linux    /vmlinuz-linux" >> "/boot/loader/entries/${TODAY}_linux.conf"
    echo "initrd   /intel-ucode.img" >> "/boot/loader/entries/${TODAY}_linux.conf"
    echo "initrd   /initramfs-linux.img" >> "/boot/loader/entries/${TODAY}_linux.conf"
    echo "options  root=UUID=$(blkid -s UUID -o value /dev/nvme0n1p3) rw vt.global_cursor_default=0 nowatchdog ipv6.disable=1 mitigations=off" >> "/boot/loader/entries/${TODAY}_linux.conf"
    
    # Step 4-E: Automate login and set default shell
    usermod --shell /usr/bin/zsh andres
    systemctl enable uwsm@andres.service
EOF

echo "Exiting chroot environment..."

# ---------------------------------------------------
# Step 5: Automounting Other Drives
# ---------------------------------------------------
echo "Mounting other hard drives..."

# Create mount points for the drives
mkdir /mnt/Documents /mnt/Videos /mnt/Backup

# Get the UUIDs for your three hard drives
DOCS_UUID=$(blkid -s UUID -o value /dev/sda)
VIDEOS_UUID=$(blkid -s UUID -o value /dev/sdb)
BACKUP_UUID=$(blkid -s UUID -o value /dev/sdc)

# Add the entries to fstab.
echo "" >> /mnt/etc/fstab
echo "# Mounting other drives" >> /mnt/etc/fstab
echo "UUID=${DOCS_UUID} /mnt/Documents ext4 defaults,nodev,nosuid,noexec,nofail,x-gvfs-show,user 0 0" >> /mnt/etc/fstab
echo "UUID=${VIDEOS_UUID} /mnt/Videos ext4 defaults,nodev,nosuid,noexec,nofail,x-gvfs-show,user 0 0" >> /mnt/etc/fstab
echo "UUID=${BACKUP_UUID} /mnt/Backup ext4 defaults,nodev,nosuid,noexec,nofail,x-gvfs-show,user 0 0" >> /mnt/etc/fstab

# ---------------------------------------------------
# Step 6: Hyprland and Other Package Installation
# ---------------------------------------------------
# Step 6-A: Install Official Packages
echo "Installing official packages from pkg_official.txt..."
pacman -Syu --noconfirm - < /home/andres/dotfiles/pkg_official.txt

# Step 6-B: Install AUR Helper (Yay)
echo "Installing yay from AUR..."
git clone https://aur.archlinux.org/yay-bin.git /home/andres/yay-bin
chown -R andres:andres /home/andres/yay-bin
sudo -u andres bash << EOL
    cd /home/andres/yay-bin
    makepkg -si --noconfirm
EOL

# Step 6-C: Install AUR Packages with Yay
echo "Installing AUR packages from pkg_aur.txt..."
sudo -u andres yay -S --noconfirm - < /home/andres/dotfiles/pkg_aur.txt

# ---------------------------------------------------
# Step 7: Dotfile Restoration
# ---------------------------------------------------
echo "Restoring dotfiles..."
# Set up a git alias and restore dotfiles
# This part assumes you have backed up your home directory files
sudo -u andres bash << EOL
    git --git-dir=$HOME/dotfiles --work-tree=$HOME config --local status.showUntrackedFiles no
    git --git-dir=$HOME/dotfiles --work-tree=$HOME checkout --force
EOL

# ---------------------------------------------------
# Step 8: Final Clean-up and Reboot
# ---------------------------------------------------
echo "Installation complete. Unmounting partitions."
umount -R /mnt
echo "You can now reboot into your new system."