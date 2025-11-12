# Pacstrap functionality to initialize Ionix installation on a target system.
# Namespace: pacstrap
source ./lib/software.sh

# Installs the base Ionix system into the specified target directory.
# Arguments:
#   $1 - Target directory for pacstrap installation.
pacstrap::install_base_system() {
  local target_dir="$1"
  local base_packages=("base" "linux" "linux-firmware" "vim" "networkmanager")
  
  # Validate target directory
  if [[ -z "$target_dir" ]]; then
    echo "Error: Target directory not specified."
    return 1
  fi
  
  # Create target directory if it doesn't exist
  if [[ ! -d "$target_dir" ]]; then
    echo "Creating target directory: $target_dir"
    mkdir -p "$target_dir" || {
      echo "Error: Failed to create target directory."
      return 1
    }
  fi
  
  # Check if pacstrap is available
  if ! sw::is_installed "pacstrap"; then
    echo "Error: pacstrap is not installed. Please install arch-install-scripts."
    return 1
  fi
  
  # Check if target is a mount point (safety check)
  if mountpoint -q "$target_dir"; then
    echo "✓ Target directory is a mount point."
  else
    echo "Warning: Target directory is not a mount point."
    echo "This may install to your current filesystem instead of a new partition."
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      echo "Installation cancelled."
      return 1
    fi
  fi
  
  # Perform pacstrap installation
  echo "Installing base Ionix system to $target_dir..."
  echo "Packages: ${base_packages[*]}"
  
  if pacstrap -K "$target_dir" "${base_packages[@]}"; then
    echo "✓ Base system installed successfully."
  else
    echo "Error: pacstrap failed."
    return 1
  fi
  
  # Generate fstab
  echo "Generating fstab..."
  if genfstab -U "$target_dir" >> "$target_dir/etc/fstab"; then
    echo "✓ fstab generated successfully."
  else
    echo "Error: Failed to generate fstab."
    return 1
  fi
  
  # Copy Ionix scripts to the new system
  local ionix_dir="$target_dir/root/ionix"
  echo "Copying Ionix installation scripts to $ionix_dir..."
  mkdir -p "$ionix_dir"
  
  # Copy all scripts (assuming we're in the ionix repo root)
  if [[ -d "$(pwd)/lib" ]]; then
    cp -r "$(pwd)/lib" "$ionix_dir/" && \
    cp -r "$(pwd)"/*.sh "$ionix_dir/" 2>/dev/null || true
    echo "✓ Ionix scripts copied."
  else
    echo "Warning: Could not copy Ionix scripts."
  fi
  
  echo ""
  echo "=========================================="
  echo "Base Ionix system installation complete!"
  echo "=========================================="
  echo ""
  echo "Next steps:"
  echo "  1. arch-chroot $target_dir"
  echo "  2. cd /root/ionix"
  echo "  3. Run post-installation scripts"
  echo ""
  
  return 0
}