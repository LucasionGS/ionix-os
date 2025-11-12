# Namespace: boot
# Bootloader installation functions for Ionix installation.

# Function: boot::detect_firmware
# Detects whether system is UEFI or BIOS.
# Sets global variable: FIRMWARE_TYPE (either "uefi" or "bios")
boot::detect_firmware() {
  if [[ -d /sys/firmware/efi/efivars ]]; then
    FIRMWARE_TYPE="uefi"
    echo "✓ Detected UEFI firmware."
  else
    FIRMWARE_TYPE="bios"
    echo "✓ Detected BIOS firmware."
  fi
  
  return 0
}

# Function: boot::detect_cpu
# Detects CPU vendor for microcode installation.
# Sets global variable: CPU_VENDOR (either "intel" or "amd")
boot::detect_cpu() {
  local cpu_info
  cpu_info=$(grep -m1 "vendor_id" /proc/cpuinfo | awk '{print $3}')
  
  case "$cpu_info" in
    GenuineIntel)
      CPU_VENDOR="intel"
      echo "✓ Detected Intel CPU."
      ;;
    AuthenticAMD)
      CPU_VENDOR="amd"
      echo "✓ Detected AMD CPU."
      ;;
    *)
      CPU_VENDOR="unknown"
      echo "Warning: Unknown CPU vendor: $cpu_info"
      ;;
  esac
  
  return 0
}

# Function: boot::install_microcode
# Installs CPU microcode updates.
boot::install_microcode() {
  boot::detect_cpu
  
  case "$CPU_VENDOR" in
    intel)
      echo "Installing Intel microcode..."
      if pacman -S --noconfirm --needed intel-ucode; then
        echo "✓ Intel microcode installed."
      else
        echo "Error: Failed to install Intel microcode."
        return 1
      fi
      ;;
    amd)
      echo "Installing AMD microcode..."
      if pacman -S --noconfirm --needed amd-ucode; then
        echo "✓ AMD microcode installed."
      else
        echo "Error: Failed to install AMD microcode."
        return 1
      fi
      ;;
    *)
      echo "Warning: No microcode package available for this CPU."
      ;;
  esac
  
  return 0
}

# Function: boot::install_grub
# Installs and configures GRUB bootloader.
# Arguments:
#   $1 - Device to install GRUB to (e.g., /dev/sda for BIOS, or EFI partition for UEFI)
boot::install_grub() {
  local install_device="$1"
  
  boot::detect_firmware
  
  echo "Installing GRUB bootloader..."
  
  # Install GRUB package and tools
  if [[ "$FIRMWARE_TYPE" == "uefi" ]]; then
    echo "Installing GRUB for UEFI..."
    if ! pacman -S --noconfirm --needed grub efibootmgr; then
      echo "Error: Failed to install GRUB packages."
      return 1
    fi
  else
    echo "Installing GRUB for BIOS..."
    if ! pacman -S --noconfirm --needed grub; then
      echo "Error: Failed to install GRUB package."
      return 1
    fi
  fi
  
  # Install GRUB
  if [[ "$FIRMWARE_TYPE" == "uefi" ]]; then
    # For UEFI, install to EFI partition
    if [[ -z "$install_device" ]]; then
      install_device="/boot/efi"
    fi
    
    # Ensure EFI directory exists
    mkdir -p "$install_device"
    
    if grub-install --target=x86_64-efi --efi-directory="$install_device" --bootloader-id=GRUB; then
      echo "✓ GRUB installed to EFI partition."
    else
      echo "Error: Failed to install GRUB."
      return 1
    fi
  else
    # For BIOS, install to MBR
    if [[ -z "$install_device" ]]; then
      echo "Error: Install device not specified for BIOS."
      return 1
    fi
    
    if grub-install --target=i386-pc "$install_device"; then
      echo "✓ GRUB installed to $install_device."
    else
      echo "Error: Failed to install GRUB."
      return 1
    fi
  fi
  
  # Generate GRUB configuration
  echo "Generating GRUB configuration..."
  if grub-mkconfig -o /boot/grub/grub.cfg; then
    echo "✓ GRUB configuration generated."
  else
    echo "Error: Failed to generate GRUB configuration."
    return 1
  fi
  
  return 0
}

# Function: boot::install_systemd_boot
# Installs and configures systemd-boot (UEFI only).
boot::install_systemd_boot() {
  boot::detect_firmware
  
  if [[ "$FIRMWARE_TYPE" != "uefi" ]]; then
    echo "Error: systemd-boot requires UEFI firmware."
    return 1
  fi
  
  echo "Installing systemd-boot..."
  
  # Install systemd-boot
  if bootctl install; then
    echo "✓ systemd-boot installed."
  else
    echo "Error: Failed to install systemd-boot."
    return 1
  fi
  
  # Get root partition UUID
  local root_uuid
  root_uuid=$(findmnt -no UUID /)
  
  if [[ -z "$root_uuid" ]]; then
    echo "Error: Could not detect root partition UUID."
    return 1
  fi
  
  # Create loader configuration
  cat > /boot/loader/loader.conf <<EOF
default arch.conf
timeout 3
console-mode max
editor no
EOF
  
  echo "✓ Loader configuration created."
  
  # Detect microcode
  boot::detect_cpu
  local microcode_line=""
  if [[ "$CPU_VENDOR" == "intel" ]] && [[ -f /boot/intel-ucode.img ]]; then
    microcode_line="initrd  /intel-ucode.img"
  elif [[ "$CPU_VENDOR" == "amd" ]] && [[ -f /boot/amd-ucode.img ]]; then
    microcode_line="initrd  /amd-ucode.img"
  fi
  
  # Create boot entry
  cat > /boot/loader/entries/arch.conf <<EOF
title   Arch Linux (Ionix)
linux   /vmlinuz-linux
${microcode_line}
initrd  /initramfs-linux.img
options root=UUID=${root_uuid} rw
EOF
  
  echo "✓ Boot entry created."
  
  return 0
}

# Function: boot::setup_interactive
# Interactive bootloader setup wizard.
boot::setup_interactive() {
  echo ""
  echo "=========================================="
  echo "  Bootloader Setup"
  echo "=========================================="
  echo ""
  
  boot::detect_firmware
  
  # Install microcode
  boot::install_microcode
  
  echo ""
  echo "Select bootloader:"
  echo "  1) GRUB (recommended for BIOS, works with UEFI)"
  echo "  2) systemd-boot (UEFI only, simpler)"
  echo ""
  
  while true; do
    read -p "Enter choice (1 or 2): " -n 1 -r
    echo
    
    case $REPLY in
      1)
        # GRUB
        if [[ "$FIRMWARE_TYPE" == "bios" ]]; then
          # Use INSTALL_DISK if available, otherwise ask
          if [[ -n "$INSTALL_DISK" ]]; then
            echo ""
            echo "Using detected disk: $INSTALL_DISK"
            grub_device="$INSTALL_DISK"
          else
            echo ""
            lsblk -o NAME,SIZE,TYPE
            echo ""
            read -p "Enter device to install GRUB to (e.g., /dev/sda): " grub_device
          fi
          boot::install_grub "$grub_device"
        else
          # UEFI - ask for EFI partition mount point
          echo ""
          echo "Common EFI mount points: /boot (recommended) or /boot/efi"
          read -p "Enter EFI partition mount point (default: /boot): " efi_mount
          efi_mount=${efi_mount:-/boot}
          boot::install_grub "$efi_mount"
        fi
        break
        ;;
      2)
        # systemd-boot
        if [[ "$FIRMWARE_TYPE" == "bios" ]]; then
          echo "Error: systemd-boot requires UEFI. Please select GRUB."
          continue
        fi
        boot::install_systemd_boot
        break
        ;;
      *)
        echo "Invalid choice. Please enter 1 or 2."
        ;;
    esac
  done
  
  return 0
}
