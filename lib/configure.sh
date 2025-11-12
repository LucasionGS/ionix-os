# Namespace: cfg
# System configuration functions for Ionix installation (runs inside chroot).

# Function: cfg::set_timezone
# Sets the system timezone.
# Arguments:
#   $1 - Timezone (e.g., America/New_York, Europe/London)
cfg::set_timezone() {
  local timezone="$1"
  
  if [[ -z "$timezone" ]]; then
    echo "Error: Timezone not specified."
    return 1
  fi
  
  local timezone_file="/usr/share/zoneinfo/$timezone"
  
  if [[ ! -f "$timezone_file" ]]; then
    echo "Error: Timezone file not found: $timezone_file"
    return 1
  fi
  
  echo "Setting timezone to $timezone..."
  
  # Create symlink
  ln -sf "$timezone_file" /etc/localtime || {
    echo "Error: Failed to create timezone symlink."
    return 1
  }
  
  # Generate /etc/adjtime
  if hwclock --systohc 2>/dev/null; then
    echo "✓ Timezone set and hardware clock synchronized."
  else
    echo "Warning: Could not sync hardware clock (may not be available in chroot)."
    echo "✓ Timezone set."
  fi
  
  return 0
}

# Function: cfg::set_locale
# Configures system locale.
# Arguments:
#   $1 - Locale (e.g., en_US.UTF-8)
cfg::set_locale() {
  local locale="$1"
  
  if [[ -z "$locale" ]]; then
    echo "Error: Locale not specified."
    return 1
  fi
  
  echo "Configuring locale: $locale..."
  
  # Uncomment locale in locale.gen
  if [[ -f /etc/locale.gen ]]; then
    # Remove existing uncommented line if it exists
    sed -i "s/^${locale}/#${locale}/" /etc/locale.gen
    # Uncomment the locale
    sed -i "s/^#${locale}/${locale}/" /etc/locale.gen
  else
    echo "Error: /etc/locale.gen not found."
    return 1
  fi
  
  # Generate locales
  if locale-gen; then
    echo "✓ Locales generated."
  else
    echo "Error: Failed to generate locales."
    return 1
  fi
  
  # Set LANG in locale.conf
  echo "LANG=${locale}" > /etc/locale.conf
  echo "✓ Locale set in /etc/locale.conf"
  
  return 0
}

# Function: cfg::set_keymap
# Sets the console keyboard layout.
# Arguments:
#   $1 - Keymap (e.g., us, de, fr)
cfg::set_keymap() {
  local keymap="$1"
  
  if [[ -z "$keymap" ]]; then
    echo "Error: Keymap not specified."
    return 1
  fi
  
  echo "Setting console keymap to $keymap..."
  
  # Create vconsole.conf
  echo "KEYMAP=${keymap}" > /etc/vconsole.conf
  echo "✓ Keymap set in /etc/vconsole.conf"
  
  return 0
}

# Function: cfg::set_hostname
# Sets the system hostname.
# Arguments:
#   $1 - Hostname
cfg::set_hostname() {
  local hostname="$1"
  
  if [[ -z "$hostname" ]]; then
    echo "Error: Hostname not specified."
    return 1
  fi
  
  echo "Setting hostname to $hostname..."
  
  # Create /etc/hostname
  echo "$hostname" > /etc/hostname
  echo "✓ Hostname set in /etc/hostname"
  
  # Configure /etc/hosts
  cat > /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${hostname}.localdomain ${hostname}
EOF
  
  echo "✓ Hosts file configured."
  
  return 0
}

# Function: cfg::enable_networkmanager
# Enables NetworkManager service.
cfg::enable_networkmanager() {
  echo "Enabling NetworkManager service..."
  
  if systemctl enable NetworkManager 2>/dev/null; then
    echo "✓ NetworkManager enabled."
  else
    echo "Error: Failed to enable NetworkManager."
    return 1
  fi
  
  return 0
}

# Function: cfg::regenerate_initramfs
# Regenerates initramfs images.
cfg::regenerate_initramfs() {
  echo "Regenerating initramfs..."
  
  if mkinitcpio -P; then
    echo "✓ Initramfs regenerated."
  else
    echo "Error: Failed to regenerate initramfs."
    return 1
  fi
  
  return 0
}
