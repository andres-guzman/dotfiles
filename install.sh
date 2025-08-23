#!/bin/bash

# Define the repository URL
REPO_URL="https://github.com/andres-guzman/dotfiles.git"
DOTFILES_DIR="$HOME/dotfiles"

# --- Start of Automation ---

# Step 1: Clone the dotfiles repository
echo "Cloning dotfiles repository..."
git clone --bare "$REPO_URL" "$DOTFILES_DIR"

# --- Next steps will go here ---

# Step 2: Disk Partitioning

# Step 3: Base System Installation

# Step 4: Hyprland and Package Installation

# Step 5: Service Configuration

# Step 6: Final Clean-up and Reboot