#!/bin/bash
# Install script for Ionix
set -e

source ./lib/software.sh
source ./lib/pacstrap.sh
source ./lib/disk.sh

IONIX_PACMAN_OPTIONS="--noconfirm --needed"

# Check for required software packages
required_packages=("git" "curl" "wget" "pacstrap" "arch-chroot" "genfstab")

for package in "${required_packages[@]}"; do
  if ! sw::is_installed "$package"; then
    echo "Error: $package is not installed."
    if [[ "$package" == "pacstrap" || "$package" == "arch-chroot" || "$package" == "genfstab" ]]; then
      echo "Please install arch-install-scripts: pacman -S arch-install-scripts"
    fi
    exit 1
  fi
done

# ========================================
# Configuration Options
# ========================================

echo ""
echo "=========================================="
echo "  Ionix System Configuration"
echo "=========================================="
echo ""

# Function: Select keyboard layout
select_keyboard_layout() {
  echo "Selecting keyboard layout..."
  
  # Check if fzf is installed
  if ! sw::is_installed "fzf"; then
    echo "Installing fzf for interactive selection..."
    pacman -S --noconfirm fzf || {
      echo "Error: Failed to install fzf. Falling back to manual entry."
      read -p "Enter keyboard layout (e.g., us, de, fr): " KEYMAP
      return 0
    }
  fi
  
  # Get list of available keymaps
  local keymap_dir="/usr/share/kbd/keymaps"
  
  if [[ ! -d "$keymap_dir" ]]; then
    echo "Warning: Keymap directory not found. Using default 'us'."
    KEYMAP="us"
    return 0
  fi
  
  # Find all keymap files and format them nicely
  echo "Finding available keyboard layouts..."
  local keymaps
  keymaps=$(find "$keymap_dir" -name "*.map.gz" -o -name "*.map" 2>/dev/null | \
    sed 's|.*/||' | \
    sed 's/\.map\.gz$//' | \
    sed 's/\.map$//' | \
    sort -u)
  
  if [[ -z "$keymaps" ]]; then
    echo "Warning: No keymaps found. Using default 'us'."
    KEYMAP="us"
    return 0
  fi
  
  # Use fzf for selection
  echo ""
  echo "Select your keyboard layout (type to search, Enter to confirm):"
  KEYMAP=$(echo "$keymaps" | fzf \
    --height=20 \
    --border=rounded \
    --prompt="Keyboard layout > " \
    --header="Common: us, uk, de, fr, es, it, pt, ru, dvorak" \
    --preview="echo 'Layout: {}'" \
    --preview-window=up:3:wrap)
  
  if [[ -z "$KEYMAP" ]]; then
    echo "No layout selected. Using default 'us'."
    KEYMAP="us"
  else
    echo "✓ Selected keyboard layout: $KEYMAP"
    
    # Apply the keymap immediately
    if loadkeys "$KEYMAP" 2>/dev/null; then
      echo "✓ Keyboard layout applied successfully."
    else
      echo "Warning: Failed to apply keyboard layout. Continuing anyway..."
    fi
  fi
}

# Function: Select timezone
select_timezone() {
  echo ""
  echo "Selecting timezone..."
  
  local timezone_dir="/usr/share/zoneinfo"
  
  if [[ ! -d "$timezone_dir" ]]; then
    echo "Warning: Timezone directory not found. Using default 'UTC'."
    TIMEZONE="UTC"
    return 0
  fi
  
  # Get list of timezones (Region/City format)
  echo "Finding available timezones..."
  local timezones
  timezones=$(find "$timezone_dir" -type f -not -path "*/right/*" -not -path "*/posix/*" | \
    grep -E "/[A-Z][a-z_]+/[A-Z]" | \
    sed "s|$timezone_dir/||" | \
    sort)
  
  if [[ -z "$timezones" ]]; then
    echo "Warning: No timezones found. Using default 'UTC'."
    TIMEZONE="UTC"
    return 0
  fi
  
  # Use fzf for selection
  echo ""
  echo "Select your timezone (type to search, Enter to confirm):"
  TIMEZONE=$(echo "$timezones" | fzf \
    --height=20 \
    --border=rounded \
    --prompt="Timezone > " \
    --header="Common: America/New_York, Europe/London, Asia/Tokyo, UTC" \
    --preview="echo 'Timezone: {}'" \
    --preview-window=up:3:wrap)
  
  if [[ -z "$TIMEZONE" ]]; then
    echo "No timezone selected. Using default 'UTC'."
    TIMEZONE="UTC"
  else
    echo "✓ Selected timezone: $TIMEZONE"
  fi
}

# Function: Select locale
select_locale() {
  echo ""
  echo "Selecting locale..."
  
  local locale_file="/etc/locale.gen"
  
  if [[ ! -f "$locale_file" ]]; then
    echo "Warning: locale.gen not found. Using default 'en_US.UTF-8'."
    LOCALE="en_US.UTF-8"
    return 0
  fi
  
  # Get list of available locales (commented out ones from locale.gen)
  echo "Finding available locales..."
  local locales
  locales=$(grep -E "^#?[a-zA-Z]" "$locale_file" | \
    sed 's/^#//' | \
    awk '{print $1}' | \
    grep -E "UTF-8$" | \
    sort -u)
  
  if [[ -z "$locales" ]]; then
    echo "Warning: No locales found. Using default 'en_US.UTF-8'."
    LOCALE="en_US.UTF-8"
    return 0
  fi
  
  # Use fzf for selection
  echo ""
  echo "Select your locale (type to search, Enter to confirm):"
  LOCALE=$(echo "$locales" | fzf \
    --height=20 \
    --border=rounded \
    --prompt="Locale > " \
    --header="Common: en_US.UTF-8, en_GB.UTF-8, de_DE.UTF-8, fr_FR.UTF-8" \
    --preview="echo 'Locale: {}'" \
    --preview-window=up:3:wrap)
  
  if [[ -z "$LOCALE" ]]; then
    echo "No locale selected. Using default 'en_US.UTF-8'."
    LOCALE="en_US.UTF-8"
  else
    echo "✓ Selected locale: $LOCALE"
  fi
}

# Function: Set hostname
select_hostname() {
  # Disable errors temporarily
  set +e
  echo ""
  echo "Setting hostname..."
  
  # Interactive prompt for hostname
  while true; do
    read -p "Enter hostname for this system: " HOSTNAME
    
    if [[ -z "$HOSTNAME" ]]; then
      echo "Error: Hostname cannot be empty."
      continue
    fi
    
    # Validate hostname (RFC 1178)
    if [[ ! "$HOSTNAME" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]]; then
      echo "Error: Invalid hostname. Use only letters, numbers, and hyphens."
      echo "       Must start and end with a letter or number."
      continue
    fi
    
    echo "✓ Hostname set to: $HOSTNAME"
    break
  done
  # Re-enable error handling
  set -e
}

# Function: Select installation partition
select_partition() {
  echo ""
  echo "Selecting installation partition..."
  
  # Get list of block devices
  if ! sw::is_installed "lsblk"; then
    echo "Error: lsblk not found."
    return 1
  fi
  
  echo "Scanning for available block devices..."
  
  # Get list of partitions only (not whole disks)
  local partitions
  partitions=$(lsblk -no NAME,SIZE,TYPE,MOUNTPOINT | \
    grep -E "part" | \
    awk '{printf "%-15s %-10s %-10s %s\n", "/dev/"$1, $2, $3, $4}')
  
  if [[ -z "$partitions" ]]; then
    echo "Error: No partitions found."
    return 1
  fi
  
  # Show current partition layout
  echo ""
  echo "Current disk layout:"
  lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT
  echo ""
  
  # Use fzf for selection
  echo "Select installation target (type to search, Enter to confirm):"
  INSTALL_TARGET=$(echo "$partitions" | fzf \
    --height=15 \
    --border=rounded \
    --prompt="Install target > " \
    --header="⚠ WARNING: This will be used for installation!" \
    --preview="lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT | grep -A 2 {1}" \
    --preview-window=up:5:wrap | \
    awk '{print $1}')
  
  if [[ -z "$INSTALL_TARGET" ]]; then
    echo "Error: No partition selected."
    return 1
  fi
  
  # Confirm selection
  echo ""
  echo "⚠  WARNING: You selected: $INSTALL_TARGET"
  echo "   This partition will be used for Ionix installation."
  echo ""
  read -p "Confirm this selection? (yes/NO): " -r
  
  if [[ ! "$REPLY" == "yes" ]]; then
    echo "Installation target not confirmed. Exiting."
    return 1
  fi
  
  echo "✓ Installation target confirmed: $INSTALL_TARGET"
  
  # Determine parent disk device (for GRUB BIOS installation)
  # e.g., /dev/sda2 -> /dev/sda, /dev/nvme0n1p2 -> /dev/nvme0n1
  if [[ "$INSTALL_TARGET" =~ ^(/dev/[a-z]+) ]]; then
    INSTALL_DISK="${BASH_REMATCH[1]}"
  elif [[ "$INSTALL_TARGET" =~ ^(/dev/nvme[0-9]+n[0-9]+) ]]; then
    INSTALL_DISK="${BASH_REMATCH[1]}"
  else
    INSTALL_DISK="$INSTALL_TARGET"
  fi
  echo "✓ Parent disk detected: $INSTALL_DISK"
  
  # Set mount point
  MOUNT_POINT="/mnt"
  echo "✓ Will mount at: $MOUNT_POINT"
}

# ========================================
# Execution starts here
# ========================================

# Run all configuration selectors
select_keyboard_layout
select_timezone
select_locale
select_hostname

# Disk partitioning
disk::partition_interactive || {
  echo "Error: Disk partitioning failed."
  exit 1
}

# If user chose to use existing partitions, let them select
if [[ -z "$INSTALL_TARGET" ]]; then
  select_partition || {
    echo "Error: Partition selection failed."
    exit 1
  }
fi

# Ensure INSTALL_DISK is set for bootloader
if [[ -z "$INSTALL_DISK" ]]; then
  # Determine parent disk device (for GRUB BIOS installation)
  if [[ "$INSTALL_TARGET" =~ ^(/dev/[a-z]+) ]]; then
    INSTALL_DISK="${BASH_REMATCH[1]}"
  elif [[ "$INSTALL_TARGET" =~ ^(/dev/nvme[0-9]+n[0-9]+) ]]; then
    INSTALL_DISK="${BASH_REMATCH[1]}"
  else
    INSTALL_DISK="$INSTALL_TARGET"
  fi
fi

# Set mount point if not already set
MOUNT_POINT="${MOUNT_POINT:-/mnt}"

# Display configuration summary
echo ""
echo "=========================================="
echo "  Configuration Summary"
echo "=========================================="
echo "Keyboard Layout: $KEYMAP"
echo "Timezone:        $TIMEZONE"
echo "Locale:          $LOCALE"
echo "Hostname:        $HOSTNAME"
echo "Install Target:  $INSTALL_TARGET"
echo "Parent Disk:     $INSTALL_DISK"
echo "Mount Point:     $MOUNT_POINT"
[[ -n "$EFI_PARTITION" ]] && echo "EFI Partition:   $EFI_PARTITION -> $EFI_MOUNT"
[[ -n "$SWAP_PARTITION" ]] && echo "Swap Partition:  $SWAP_PARTITION"
[[ -n "$HOME_PARTITION" ]] && echo "Home Partition:  $HOME_PARTITION"
echo "=========================================="
echo ""
read -p "Proceed with installation? (yes/NO): " -r

if [[ ! "$REPLY" == "yes" ]]; then
  echo "Installation cancelled."
  exit 0
fi

echo ""
echo "Starting Ionix installation..."

# ========================================
# Mount partitions
# ========================================

echo ""
echo "Mounting partitions..."

# Create mount point if it doesn't exist
mkdir -p "$MOUNT_POINT"

# Mount root partition
if mount "$INSTALL_TARGET" "$MOUNT_POINT"; then
  echo "✓ Root partition mounted to $MOUNT_POINT"
else
  echo "Error: Failed to mount root partition."
  exit 1
fi

# Mount EFI partition if it exists
if [[ -n "$EFI_PARTITION" && -n "$EFI_MOUNT" ]]; then
  echo "Mounting EFI partition..."
  mkdir -p "$MOUNT_POINT$EFI_MOUNT"
  if mount "$EFI_PARTITION" "$MOUNT_POINT$EFI_MOUNT"; then
    echo "✓ EFI partition mounted to $MOUNT_POINT$EFI_MOUNT"
  else
    echo "Warning: Failed to mount EFI partition."
  fi
fi

# Mount home partition if it exists
if [[ -n "$HOME_PARTITION" ]]; then
  echo "Mounting home partition..."
  mkdir -p "$MOUNT_POINT/home"
  if mount "$HOME_PARTITION" "$MOUNT_POINT/home"; then
    echo "✓ Home partition mounted to $MOUNT_POINT/home"
  else
    echo "Warning: Failed to mount home partition."
  fi
fi

# Enable swap if it exists
if [[ -n "$SWAP_PARTITION" ]]; then
  echo "Enabling swap..."
  if swapon "$SWAP_PARTITION"; then
    echo "✓ Swap enabled on $SWAP_PARTITION"
  else
    echo "Warning: Failed to enable swap."
  fi
fi

# ========================================
# Run pacstrap
# ========================================

echo ""
pacstrap::install_base_system "$MOUNT_POINT" || {
  echo "Error: Failed to install base system."
  exit 1
}

# ========================================
# Save configuration for chroot
# ========================================

echo ""
echo "Saving configuration for chroot setup..."

cat > "$MOUNT_POINT/root/ionix/ionix.conf" <<EOF
# Ionix Configuration
# Generated by install.sh on $(date)

KEYMAP="$KEYMAP"
TIMEZONE="$TIMEZONE"
LOCALE="$LOCALE"
HOSTNAME="$HOSTNAME"
INSTALL_TARGET="$INSTALL_TARGET"
INSTALL_DISK="$INSTALL_DISK"
MOUNT_POINT="$MOUNT_POINT"
EFI_PARTITION="${EFI_PARTITION:-}"
EFI_MOUNT="${EFI_MOUNT:-}"
SWAP_PARTITION="${SWAP_PARTITION:-}"
HOME_PARTITION="${HOME_PARTITION:-}"
EOF

echo "✓ Configuration saved to $MOUNT_POINT/root/ionix/ionix.conf"

# Create chroot marker
touch "$MOUNT_POINT/.chroot_ionix_marker"

# Make chroot-setup.sh executable
chmod +x "$MOUNT_POINT/root/ionix/chroot-setup.sh"

# ========================================
# Installation complete
# ========================================

echo ""
echo "=========================================="
echo "  Base System Installation Complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo ""
echo "  1. Enter the chroot environment:"
echo "     arch-chroot $MOUNT_POINT"
echo ""
echo "  2. Run the chroot setup script:"
echo "     cd /root/ionix"
echo "     ./chroot-setup.sh"
echo ""
echo "  3. After setup is complete:"
echo "     exit"
echo "     umount -R $MOUNT_POINT"
echo "     reboot"
echo ""
echo "=========================================="
echo ""
