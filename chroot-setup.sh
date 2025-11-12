#!/bin/bash
# Chroot Setup Script for Ionix
# This script runs INSIDE the chroot environment to configure the base system.

set -e

# Source library functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/configure.sh"
source "$SCRIPT_DIR/lib/users.sh"
source "$SCRIPT_DIR/lib/bootloader.sh"

echo ""
echo "=========================================="
echo "  Ionix Chroot Configuration"
echo "=========================================="
echo ""
echo "This script will configure your Ionix system."
echo ""

# Check if we're running inside chroot
if [[ ! -f /.chroot_ionix_marker ]]; then
  echo "Warning: This script should be run inside arch-chroot."
  read -p "Continue anyway? (y/N): " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
  fi
fi

# Function to load configuration from file
load_config() {
  local config_file="$1"
  
  if [[ -f "$config_file" ]]; then
    echo "Loading configuration from $config_file..."
    source "$config_file"
    echo "✓ Configuration loaded."
    return 0
  else
    echo "No configuration file found. Will use interactive setup."
    return 1
  fi
}

# Function to run interactive configuration
interactive_config() {
  echo ""
  echo "=========================================="
  echo "  System Configuration"
  echo "=========================================="
  echo ""
  
  # Timezone
  read -p "Enter timezone (e.g., America/New_York): " TIMEZONE
  if [[ -z "$TIMEZONE" ]]; then
    TIMEZONE="UTC"
  fi
  
  # Locale
  read -p "Enter locale (e.g., en_US.UTF-8): " LOCALE
  if [[ -z "$LOCALE" ]]; then
    LOCALE="en_US.UTF-8"
  fi
  
  # Keymap
  read -p "Enter keymap (e.g., us): " KEYMAP
  if [[ -z "$KEYMAP" ]]; then
    KEYMAP="us"
  fi
  
  # Hostname
  while true; do
    read -p "Enter hostname: " HOSTNAME
    if [[ -n "$HOSTNAME" ]]; then
      break
    fi
    echo "Hostname cannot be empty."
  done
}

# Main execution
main() {
  # Try to load config from file, otherwise use interactive
  if ! load_config "/root/ionix/ionix.conf"; then
    interactive_config
  fi
  
  echo ""
  echo "Applying system configuration..."
  echo ""
  
  # Apply timezone
  if [[ -n "$TIMEZONE" ]]; then
    cfg::set_timezone "$TIMEZONE" || {
      echo "Warning: Failed to set timezone."
    }
  fi
  
  # Apply locale
  if [[ -n "$LOCALE" ]]; then
    cfg::set_locale "$LOCALE" || {
      echo "Warning: Failed to set locale."
    }
  fi
  
  # Apply keymap
  if [[ -n "$KEYMAP" ]]; then
    cfg::set_keymap "$KEYMAP" || {
      echo "Warning: Failed to set keymap."
    }
  fi
  
  # Apply hostname
  if [[ -n "$HOSTNAME" ]]; then
    cfg::set_hostname "$HOSTNAME" || {
      echo "Warning: Failed to set hostname."
    }
  fi
  
  # Enable NetworkManager
  echo ""
  cfg::enable_networkmanager || {
    echo "Warning: Failed to enable NetworkManager."
  }
  
  # Install essential packages
  echo ""
  echo "Installing essential packages..."
  pacman -S --noconfirm --needed base-devel sudo || {
    echo "Warning: Failed to install some packages."
  }
  
  # User setup
  user::setup_interactive || {
    echo "Warning: User setup incomplete."
  }
  
  # Bootloader setup
  boot::setup_interactive || {
    echo "Error: Bootloader setup failed."
    echo "You will need to configure the bootloader manually."
  }
  
  # Regenerate initramfs
  echo ""
  cfg::regenerate_initramfs || {
    echo "Warning: Failed to regenerate initramfs."
  }
  
  echo ""
  echo "=========================================="
  echo "  Ionix Installation Complete!"
  echo "=========================================="
  echo ""
  echo "Your Ionix system is now configured."
  echo ""
  echo "Next steps:"
  echo "  1. Exit the chroot environment (type 'exit')"
  echo "  2. Unmount partitions: umount -R /mnt"
  echo "  3. Reboot: reboot"
  echo ""
  echo "After reboot, log in and enjoy your Ionix system!"
  echo ""
}

# Run main function
main
