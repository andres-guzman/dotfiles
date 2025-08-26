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

# --- Wrapper function to execute commands with error handling ---
# This is a non-interactive function for maximum automation.
execute_command() {
    local cmd_description="$1"
    local command_to_execute="$2"

    echo -e "${CYAN}Executing: ${cmd_description}${NOCOLOR}"
    if eval "$command_to_execute"; then
        echo -e "${GREEN}SUCCESS: ${cmd_description}${NOCOLOR}"
        return 0
    else
        echo -e "${RED}FAILURE: ${cmd_description} failed. Exiting script.${NOCOLOR}"
        exit 1
    fi
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
execute_command "Create GPT label on ${DRIVE}" "parted -s \"${DRIVE}\" mklabel gpt"
execute_command "Create EFI partition" "parted -s \"${DRIVE}\" mkpart primary fat32 1MiB 1025MiB"
execute_command "Set ESP flag on EFI partition" "parted -s \"${DRIVE}\" set 1 esp on"
execute_command "Create Swap partition" "parted -s \"${DRIVE}\" mkpart primary linux-swap 1025MiB 9249MiB"
execute_command "Create Root partition" "parted -s \"${DRIVE}\" mkpart primary ext4 9249MiB 100%"

# Step 1-B: Format the partitions
execute_command "Format EFI partition" "mkfs.fat -F32 \"${DRIVE}p1\""
execute_command "Format Swap partition" "mkswap \"${DRIVE}p2\""
execute_command "Format Root partition" "mkfs.ext4 \"${DRIVE}p3\""
execute_command "Enable Swap" "swapon \"${DRIVE}p2\""

# ---------------------------------------------------
# Step 2: Base System Installation
# ---------------------------------------------------
echo -e "${CYAN}--- Step 2: Base System Installation ---${NOCOLOR}"
echo -e "${YELLOW}Mounting partitions and installing base system...${NOCOLOR}"

# Step 2-A: Mount partitions
execute_command "Mount Root partition" "mount \"${DRIVE}p3\" /mnt"
execute_command "Create /mnt/boot directory" "mkdir -p /mnt/boot"
execute_command "Mount EFI partition" "mount \"${DRIVE}p1\" /mnt/boot"


# Install terminus-font and set console font for the live environment (EARLIEST POSSIBLE)
echo -e "${YELLOW}Installing terminus-font for console display...${NOCOLOR}"
pacman -Sy --noconfirm terminus-font || echo "Warning: Could not install terminus-font. Continuing."
echo -e "${YELLOW}Setting console font to ter-v16n...${NOCOLOR}"
setfont ter-v16n || echo "Warning: Could not set console font. Continuing."

# Step 2-B: Install the base system and essential packages
echo -e "${YELLOW}Installing base system with pacstrap (output to /mnt/pacstrap.log)...${NOCOLOR}"
# IMPORTANT: Added base-devel to ensure build tools like debugedit are present early
execute_command "Pacstrap /mnt base system and base-devel" "pacstrap /mnt base base-devel linux-firmware git sudo networkmanager nano efibootmgr 2>&1 | tee /mnt/pacstrap.log"

# Step 2-C: Generate fstab
execute_command "Generate fstab" "genfstab -U /mnt >> /mnt/etc/fstab"

# --- NEW: Copy host resolv.conf into chroot for DNS resolution (MOVED TO AFTER PACSTRAP) ---
echo -e "${YELLOW}Copying /etc/resolv.conf from live environment to /mnt/etc/resolv.conf for DNS resolution in chroot...${NOCOLOR}"
execute_command "Copy /etc/resolv.conf" "cp /etc/resolv.conf /mnt/etc/resolv.conf"


# ---------------------------------------------------
# Step 3: Prepare Dotfiles and Chroot Script
# ---------------------------------------------------
echo -e "${CYAN}--- Step 3: Prepare Dotfiles and Chroot Script ---${NOCOLOR}"
echo -e "${YELLOW}Downloading package lists and creating chroot script directly on NVMe...${NOCOLOR}"

execute_command "Create /mnt/home/andres directory" "mkdir -p /mnt/home/andres"
execute_command "Create temporary dotfiles directory on NVMe" "mkdir -p \"${DOTFILES_TEMP_NVME_DIR}\""

# Download pkg_official.txt directly to the NVMe drive with robust error handling
echo -e "${YELLOW}Attempting to download pkg_official.txt to ${DOTFILES_TEMP_NVME_DIR}...${NOCOLOR}"
execute_command "Download pkg_official.txt" "curl -f -o \"${DOTFILES_TEMP_NVME_DIR}/pkg_official.txt\" \"${PKG_OFFICIAL_URL}\""

# Download pkg_aur.txt directly to the NVMe drive with robust error handling
echo -e "${YELLOW}Attempting to download pkg_aur.txt to ${DOTFILES_TEMP_NVME_DIR}...${NOCOLOR}"
execute_command "Download pkg_aur.txt" "curl -f -o \"${DOTFILES_TEMP_NVME_DIR}/pkg_aur.txt\" \"${PKG_AUR_URL}\""

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
echo -e "${YELLOW}Removing 'wlogout' and 'spotify' from the AUR package list as requested to bypass PGP errors.${NOCOLOR}"
sed -i '/^spotify$/d' "${DOTFILES_TEMP_NVME_DIR}/pkg_aur.txt"
sed -i '/^wlogout$/d' "${DOTFILES_TEMP_NVME_DIR}/pkg_aur.txt"

# ---------------------------------------------------
# Step 4: Create and Execute the Chroot Script
# ---------------------------------------------------
echo -e "${CYAN}--- Step 4: Creating and executing chroot script ---${NOCOLOR}"
echo -e "${YELLOW}Creating temporary script inside /mnt for chroot execution...${NOCOLOR}"

cat > /mnt/chroot-script.sh << 'EOF_CHROOT_SCRIPT_FINAL'
#!/bin/bash
# This script is executed inside the chroot environment.
set -e
set -o pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/home/andres/.local/bin

# --- Non-interactive error handling inside chroot ---
# Critical commands will exit on failure. Skippable commands will warn and continue.
execute_chroot_command() {
    local cmd_description="$1"
    local command_to_execute="$2"

    echo "Executing (chroot): ${cmd_description}"
    if eval "$command_to_execute"; then
        echo "SUCCESS (chroot): ${cmd_description}"
        return 0
    else
        echo "FAILURE (chroot): ${cmd_description} failed."
        exit 1
    fi
}
    
# Step 4-A: Time, Locale, and Hostname
echo "Configuring time, locale, and hostname..."
execute_chroot_command "Set timezone" "ln -sf /usr/share/zoneinfo/America/La_Paz /etc/localtime"
execute_chroot_command "Set hardware clock" "hwclock --systohc"
execute_chroot_command "Set keyboard layout" "echo \"KEYMAP=la-latin1\" > /etc/vconsole.conf"

execute_chroot_command "Uncomment en_CA locale" "sed -i '/#en_CA.UTF-8 UTF-8/s/^#//' /etc/locale.gen"
execute_chroot_command "Uncomment en_US locale" "sed -i '/#en_US.UTF-8 UTF-8/s/^#//' /etc/locale.gen"
execute_chroot_command "Uncomment es_BO locale" "sed -i '/#es_BO.UTF-8 UTF-8/s/^#//' /etc/locale.gen"
execute_chroot_command "Generate locales" "locale-gen"
execute_chroot_command "Set LANG in locale.conf" "echo \"LANG=en_US.UTF-8\" > /etc/locale.conf"

execute_chroot_command "Set hostname" "echo \"archlinux\" > /etc/hostname"
execute_chroot_command "Add hosts entries" "echo -e \"127.0.0.1\tlocalhost\n::1\t\tlocalhost\n127.0.1.1\tarchlinux.localdomain archlinux\" >> /etc/hosts"

# Step 4-B: User and Sudo Configuration
echo "Creating user 'andres' and configuring sudo..."
execute_chroot_command "Create user 'andres'" "useradd -m andres"
execute_chroot_command "Set password for 'andres'" "echo \"andres:armoniac\" | chpasswd" # PASSWORD SET TO 'armoniac'
execute_chroot_command "Add 'andres' to wheel group" "usermod -aG wheel andres"
    
echo "Configuring NOPASSWD for 'andres'..."
execute_chroot_command "Create NOPASSWD sudoers file" "echo \"%wheel ALL=(ALL:ALL) NOPASSWD: ALL\" > /etc/sudoers.d/90-andres-install-nopasswd"
execute_chroot_command "Set permissions on sudoers file" "chmod 0440 /etc/sudoers.d/90-andres-install-nopasswd"
execute_chroot_command "Uncomment wheel group in sudoers" "sed -i '/%wheel ALL=(ALL:ALL) ALL/s/^# //g' /etc/sudoers"

# Step 4-C: Install Kernels and other core packages & Enable multilib
echo "Installing Zen and Stable kernels, microcode, core utilities, and enabling multilib..."
execute_chroot_command "Install kernels and microcode" "pacman -Syu --noconfirm linux-zen linux linux-headers linux-zen-headers intel-ucode"
execute_chroot_command "Install core audio and zsh packages" "pacman -S --noconfirm pipewire pipewire-pulse wireplumber zsh"

echo "Enabling multilib repository..."
execute_chroot_command "Modify pacman.conf for multilib" "sed -i '/^#\[multilib\]/,/^#Include = \/etc\/pacman.d\/mirrorlist/ { s/^#// }' /etc/pacman.conf"
execute_chroot_command "Synchronize package databases" "pacman -Syyu --noconfirm"

# Step 4-D: Bootloader Configuration
echo "Configuring systemd-boot..."
execute_chroot_command "Install systemd-boot" "bootctl install"

TODAY=$(date +%Y-%m-%d")

execute_chroot_command "Create loader.conf" "echo -e \"default ${TODAY}_linux-zen.conf\ntimeout  0\nconsole-mode max\neditor   no\" > /boot/loader/loader.conf"
execute_chroot_command "Create linux-zen boot entry" "echo -e \"title\tArch Linux Zen\nlinux\t/vmlinuz-linux-zen\ninitrd\t/intel-ucode.img\ninitrd\t/initramfs-linux-zen.img\noptions\troot=UUID=\$(blkid -s UUID -o value /dev/nvme0n1p3) rw vt.global_cursor_default=0 nowatchdog ipv6.disable=1 mitigations=off\" > \"/boot/loader/entries/${TODAY}_linux-zen.conf\""
execute_chroot_command "Create linux boot entry" "echo -e \"title\tArch Linux\nlinux\t/vmlinuz-linux\ninitrd\t/intel-ucode.img\ninitrd\t/initramfs-linux.img\noptions\troot=UUID=\$(blkid -s UUID -o value /dev/nvme0n1p3) rw vt.global_cursor_default=0 nowatchdog ipv6.disable=1 mitigations=off\" > \"/boot/loader/entries/${TODAY}_linux.conf\""
    
# Step 4-E: Enable getty service for auto-login
echo "Creating systemd override for agetty to enable autologin..."
execute_chroot_command "Create getty override directory" "mkdir -p /etc/systemd/system/getty@tty1.service.d"
execute_chroot_command "Create autologin.conf" "echo -e \"[Service]\nExecStart=\nExecStart=-/usr/bin/agetty --autologin andres --noclear %I \\\$TERM\" > /etc/systemd/system/getty@tty1.service.d/autologin.conf"
execute_chroot_command "Enable getty service" "systemctl enable getty@tty1.service"

# CRITICAL FIX: Create a simple .bash_profile with a direct exec to uwsm.
echo "Creating or updating .bash_profile for autologin and uwsm autostart..."
BASH_PROFILE_PATH="/home/andres/.bash_profile"
    
execute_chroot_command "Create .bash_profile if it doesn't exist" "touch \"\${BASH_PROFILE_PATH}\""
execute_chroot_command "Set initial ownership of .bash_profile" "chown andres:andres \"\${BASH_PROFILE_PATH}\""

# Overwrite the file with the simple, guaranteed-to-work autostart logic.
execute_chroot_command "Write autostart logic to .bash_profile" "cat > \"\${BASH_PROFILE_PATH}\" << 'EOF_BASH_PROFILE'
# Start Hyprland using uwsm if not already in a graphical session.
if [[ -z \"\$DISPLAY\" && \"\$XDG_VTNR\" -eq 1 ]]; then
    exec /usr/bin/uwsm
fi
EOF_BASH_PROFILE"
execute_chroot_command "Set final ownership of .bash_profile" "chown andres:andres \"\${BASH_PROFILE_PATH}\""


# Step 6-A: Install Official Packages
echo "Installing official packages from pkg_official.txt..."
OFFICIAL_PACKAGES_FILE="/home/andres/temp_dotfiles_setup/pkg_official.txt"
if ! grep -q "^uwsm$" "\${OFFICIAL_PACKAGES_FILE}"; then
    echo "uwsm" >> "\${OFFICIAL_PACKAGES_FILE}"
    echo "Added uwsm to official package list."
fi
execute_chroot_command "Install official packages (including uwsm)" "pacman -S --noconfirm - \$(cat \"\${OFFICIAL_PACKAGES_FILE}\")"

# Step 6-B: Install AUR Helper (Yay)
echo "Installing yay from AUR..."
YAY_CLONE_DIR="/home/andres/yay-bin"
execute_chroot_command "Create yay-bin directory" "mkdir -p \"\${YAY_CLONE_DIR}\""
execute_chroot_command "Set ownership of yay-bin directory" "chown andres:andres \"\${YAY_CLONE_DIR}\""
execute_chroot_command "Clone yay-bin as 'andres'" "sudo -u andres git clone --depth 1 https://aur.archlinux.org/yay-bin.git \"\${YAY_CLONE_DIR}\""
execute_chroot_command "Change ownership of cloned yay-bin" "chown -R andres:andres \"\${YAY_CLONE_DIR}\""
execute_chroot_command "Build and install yay as 'andres'" "sudo -u andres bash -l -c \"cd \\\"\${YAY_CLONE_DIR}\\\" && makepkg -si --noconfirm\""

# Step 6-C: Install AUR Packages with Yay
echo "Installing AUR packages from pkg_aur.txt..."
execute_chroot_command "Create necessary dotfile directories" "mkdir -p /home/andres/.config /home/andres/.local/share"
execute_chroot_command "Restore dotfiles" "sudo -u andres rsync -av --exclude='.git/' --exclude='LICENSE' --exclude='README.md' --exclude='pkg_*' /home/andres/temp_dotfiles_setup/ /home/andres/"
execute_chroot_command "Set correct ownership of restored dotfiles" "chown -R andres:andres /home/andres"
execute_chroot_command "Install AUR packages with yay" "sudo -u andres yay -S --noconfirm --removemake --useask --editmenu=false \$(cat /home/andres/temp_dotfiles_setup/pkg_aur.txt)"
    
# Optional: Clean up the temporary dotfiles directory after installation
echo "Cleaning up temporary dotfiles directory..."
execute_chroot_command "Remove temporary dotfiles directory" "rm -rf /home/andres/temp_dotfiles_setup"

# CRITICAL FIX: Clean up the temporary sudoers file.
echo "Removing temporary NOPASSWD sudoers file..."
execute_chroot_command "Remove temporary sudoers file" "rm /etc/sudoers.d/90-andres-install-nopasswd"
    
# CRITICAL FIX: Set the user's default shell to Zsh as requested.
echo "Setting user 'andres' default shell to zsh..."
execute_chroot_command "Set 'andres' shell to zsh" "chsh -s /usr/bin/zsh andres"
    
EOF_CHROOT_SCRIPT_FINAL

execute_command "Execute chroot script" "arch-chroot /mnt bash /chroot-script.sh"
execute_command "Remove temporary chroot script" "rm /mnt/chroot-script.sh"

echo -e "${GREEN}Installation script finished! You can now unmount and reboot into your new Arch Linux system.${NOCOLOR}"
