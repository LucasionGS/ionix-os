#!/bin/bash
# Install script for Ionix
set -e

source ./lib/software.sh
source ./lib/pacstrap.sh

IONIX_PACMAN_OPTIONS="--noconfirm --needed"

# Check for required software packages
required_packages=("git" "curl" "wget")

for package in "${required_packages[@]}"; do
  if ! sw::is_installed "$package"; then
    echo "Error: $package is not installed."
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
  
  # Get list of partitions with size info
  local partitions
  partitions=$(lsblk -no NAME,SIZE,TYPE,MOUNTPOINT | \
    grep -E "part|disk" | \
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
select_partition

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
echo "Mount Point:     $MOUNT_POINT"
echo "=========================================="
echo ""
read -p "Proceed with installation? (yes/NO): " -r

if [[ ! "$REPLY" == "yes" ]]; then
  echo "Installation cancelled."
  exit 0
fi

echo ""
echo "Starting Ionix installation..."

