#!/bin/bash
# Chroot Setup Script for Ionix
# This script runs INSIDE the chroot environment to configure the base system.

set -e

# Source library functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/configure.sh"
source "$SCRIPT_DIR/lib/users.sh"
source "$SCRIPT_DIR/lib/bootloader.sh"
source "$SCRIPT_DIR/lib/graphics.sh"

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

# Install all the specific OS packages
# Here we do all of the installation of the Ionix OS packages and configuration
boot::install_ionix_os() {
  local curDir="$(pwd)"

  # Install Ionix OS packages based on config/packages.json
  local packages_file="$SCRIPT_DIR/config/packages.json"
  
  if [[ ! -f "$packages_file" ]]; then
    echo "Warning: packages.json not found at $packages_file"
    return 0
  fi
  
  # Check if jq is installed for JSON parsing
  if ! command -v jq &> /dev/null; then
    echo "Installing jq for JSON parsing..."
    pacman -S --noconfirm --needed jq || {
      echo "Error: Failed to install jq"
      return 1
    }
  fi
  
  echo ""
  echo "=========================================="
  echo "  Installing Ionix OS Packages"
  echo "=========================================="
  echo ""
  
  # 1. Install Pacman packages
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📦 Installing Pacman packages..."
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  local pacman_packages
  pacman_packages=$(jq -r '.pacman[]' "$packages_file" 2>/dev/null)
  
  if [[ -n "$pacman_packages" ]]; then
    echo "Packages to install:"
    echo "$pacman_packages" | sed 's/^/  - /'
    echo ""
    
    # Convert to array and install
    local pkg_array=()
    while IFS= read -r pkg; do
      pkg_array+=("$pkg")
    done <<< "$pacman_packages"
    
    if pacman -Syu --noconfirm --needed "${pkg_array[@]}"; then
      echo "✓ Pacman packages installed successfully"
    else
      echo "Warning: Some pacman packages failed to install"
    fi
  else
    echo "No pacman packages to install"
  fi
  
  # 2. Install AUR packages
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "🔧 Installing AUR packages..."
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  local aur_packages
  aur_packages=$(jq -r '.aur[]' "$packages_file" 2>/dev/null)
  
  
  if [[ -n "$aur_packages" ]]; then
    # Create temporary user for AUR builds if needed
    if ! id -u ionix_aur &> /dev/null; then
      echo "Creating temporary user 'ionix_aur' for AUR builds..."
      useradd -m -G wheel ionix_aur

      # Set no password
      echo "ionix_aur ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers.d/ionix_aur
      chmod 440 /etc/sudoers.d/ionix_aur
    fi

    # If yay bin doesn't exist, install it
  echo "Installing yay AUR helper..."
  echo "This will allow us to install packages from the Arch User Repository"
  
    if git clone https://aur.archlinux.org/yay-bin.git /tmp/yay; then
      cd /tmp/yay
      chown -R ionix_aur:ionix_aur /tmp/yay
      chmod -R 777 /tmp/yay
      if sudo -u ionix_aur makepkg -si --noconfirm; then
        echo "✓ Yay AUR helper installed successfully"
      else
        echo "Error: Failed to build and install yay"
      fi
      cd "$curDir"
      rm -rf /tmp/yay
    else
      echo "Error: Failed to clone yay repository"
    fi

    echo "Packages to install:"
    echo "$aur_packages" | sed 's/^/  - /'
    echo ""
    
    # Convert to array and install with yay
    local aur_array=()
    while IFS= read -r pkg; do
      aur_array+=("$pkg")
    done <<< "$aur_packages"

    if sudo -u ionix_aur yay -Sy --noconfirm --needed "${aur_array[@]}"; then
      echo "✓ AUR packages installed successfully"
    else
      echo "Warning: Some AUR packages failed to install"
    fi
  else
    echo "No AUR packages to install"
  fi

  # Remove temporary AUR user
  if id -u ionix_aur &> /dev/null; then
    echo "Removing temporary user 'ionix_aur'..."
    userdel -r ionix_aur
    rm -f /etc/sudoers.d/ionix_aur
  fi
  
  # 3. Install Snap packages
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📸 Installing Snap packages..."
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  # First enable and start snapd
  if systemctl enable snapd.socket &> /dev/null && systemctl start snapd.socket &> /dev/null; then
    echo "✓ Snapd service enabled and started"
    
    local snap_packages
    snap_packages=$(jq -r '.snap[]' "$packages_file" 2>/dev/null)
    
    if [[ -n "$snap_packages" ]]; then
      echo "Packages to install:"
      echo "$snap_packages" | sed 's/^/  - /'
      echo ""
      
      while IFS= read -r pkg; do
        if snap install "$pkg"; then
          echo "✓ Installed: $pkg"
        else
          echo "Warning: Failed to install snap package: $pkg"
        fi
      done <<< "$snap_packages"
    else
      echo "No snap packages to install"
    fi
  else
    echo "Warning: Failed to start snapd service, skipping snap packages"
  fi
  
  # 4. Install Other packages (custom scripts)
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "🛠️  Installing custom packages..."
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  local other_keys
  other_keys=$(jq -r '.other | keys[]' "$packages_file" 2>/dev/null)
  
  if [[ -n "$other_keys" ]]; then
    while IFS= read -r key; do
      echo ""
      echo "Installing: $key"
      
      # Get commands array for this key
      local cmd_count
      cmd_count=$(jq -r ".other[\"$key\"] | length" "$packages_file")
      
      local success=true
      for ((i=0; i<cmd_count; i++)); do
        local cmd
        cmd=$(jq -r ".other[\"$key\"][$i]" "$packages_file")
        
        echo "  Running: $cmd"
        if eval "$cmd"; then
          echo "  ✓ Command succeeded"
        else
          echo "  ✗ Command failed"
          success=false
          break
        fi
      done
      
      if [[ "$success" == "true" ]]; then
        echo "✓ $key installed successfully"
      else
        echo "Warning: $key installation failed"
      fi
    done <<< "$other_keys"
  else
    echo "No custom packages to install"
  fi
  
  # 5. Install Fish plugins
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "🐟 Installing Fish shell plugins..."
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  # Check if OMF is installed
  if ! fish -c "command -v omf" &>/dev/null; then
    echo "Warning: Oh My Fish (omf) not found. Install it via 'other.omf' first."
    echo "Skipping fish plugin installation."
  else
    local fish_plugins
    fish_plugins=$(jq -r '.fish_plugins[]' "$packages_file" 2>/dev/null)
    
    if [[ -n "$fish_plugins" ]]; then
      echo "Plugins to install:"
      echo "$fish_plugins" | sed 's/^/  - /'
      echo ""
      
      while IFS= read -r plugin; do
        # Check if it's a known OMF theme
        if [[ "$plugin" =~ ^[a-zA-Z0-9_-]+/[a-zA-Z0-9_.-]+$ ]]; then
          echo "Installing Fisher plugin: $plugin"
          if fish -c "fisher install $plugin"; then
            echo "  ✓ Plugin installed"
          else
            echo "  Warning: Failed to install plugin: $plugin"
          fi
        # Try OMF first, then Fisher
        else
          echo "Installing plugin: $plugin"
          if fish -c "omf install $plugin"; then
            echo "  ✓ Plugin installed (via OMF)"
          elif fish -c "fisher install $plugin"; then
            echo "  ✓ Plugin installed (via Fisher)"
          else
            echo "  Warning: Failed to install plugin: $plugin"
          fi
        fi
      done <<< "$fish_plugins"
      
      echo ""
      echo "✓ Fish plugin installation complete"
    else
      echo "No Fish plugins to install"
    fi
  fi
  
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "✓ Ionix OS package installation complete!"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  cd "$curDir"

  # Copy all the files in ./root/ to /
  echo ""
  echo "Copying default root files to / recursively..."
  local root_files_dir="$SCRIPT_DIR/root"
  # Install root files with "install"
  rsync -a "$root_files_dir"/ /
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

  # Install the actual system of Ionix (lol)
  boot::install_ionix_os

  # Graphics driver setup
  echo ""
  gpu::select_interactive || {
    echo "Warning: Graphics selection failed."
  }
  
  if [[ -n "$GPU_VENDOR" && "$GPU_VENDOR" != "skip" ]]; then
    gpu::install "$GPU_VENDOR" || {
      echo "Warning: Graphics driver installation failed."
    }
  fi

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
