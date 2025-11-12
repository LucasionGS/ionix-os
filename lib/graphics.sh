# Namespace: gpu
# Graphics driver detection and installation functions for Ionix.

# Function: gpu::detect
# Detects graphics hardware and sets GPU_VENDOR variable.
# Sets: GPU_VENDOR (nvidia, amd, intel, vm, or unknown)
gpu::detect() {
  echo "Detecting graphics hardware..."
  
  local vga_info
  vga_info=$(lspci -nnk | grep -EA3 'VGA|3D|Display' 2>/dev/null || true)
  
  GPU_VENDOR="unknown"
  
  if echo "$vga_info" | grep -qi nvidia; then 
    GPU_VENDOR="nvidia"
  elif echo "$vga_info" | grep -qi "amd\|ati"; then 
    GPU_VENDOR="amd"
  elif echo "$vga_info" | grep -qi intel; then 
    GPU_VENDOR="intel"
  elif systemd-detect-virt -q 2>/dev/null; then 
    GPU_VENDOR="vm"
  fi
  
  if [[ "$GPU_VENDOR" != "unknown" ]]; then
    echo "✓ Detected graphics: $GPU_VENDOR"
    if [[ -n "$vga_info" ]]; then
      echo "  Hardware info:"
      echo "$vga_info" | sed 's/^/    /'
    fi
  else
    echo "⚠ Could not auto-detect graphics vendor"
  fi
  
  return 0
}

# Function: gpu::select_interactive
# Interactive graphics driver selection.
# Sets: GPU_VENDOR
gpu::select_interactive() {
  echo ""
  echo "=========================================="
  echo "  Graphics Driver Selection"
  echo "=========================================="
  echo ""
  
  # Detect first
  gpu::detect
  
  echo ""
  echo "Select graphics driver to install:"
  echo "  1) NVIDIA    - NVIDIA GeForce/Quadro/Tesla cards"
  echo "  2) AMD       - AMD Radeon/RDNA cards"
  echo "  3) Intel     - Intel integrated graphics"
  echo "  4) Virtual   - Virtual machine graphics"
  echo "  5) Skip      - Don't install graphics drivers now"
  echo ""
  
  while true; do
    read -p "Choose driver type [1-5]: " -n 1 -r
    echo
    
    case $REPLY in
      1) GPU_VENDOR="nvidia"; break;;
      2) GPU_VENDOR="amd"; break;;
      3) GPU_VENDOR="intel"; break;;
      4) GPU_VENDOR="vm"; break;;
      5) GPU_VENDOR="skip"; break;;
      *) echo "Invalid choice. Please select 1-5.";;
    esac
  done
  
  if [[ "$GPU_VENDOR" == "skip" ]]; then
    echo "⚠ Skipping graphics driver installation"
    return 0
  fi
  
  echo "✓ Selected: $GPU_VENDOR"
  
  # Confirm
  read -p "Proceed with $GPU_VENDOR driver installation? (Y/n): " -n 1 -r
  echo
  
  if [[ $REPLY =~ ^[Nn]$ ]]; then
    echo "Installation cancelled."
    GPU_VENDOR="skip"
    return 0
  fi
  
  return 0
}

# Function: gpu::install_nvidia
# Installs NVIDIA proprietary drivers.
gpu::install_nvidia() {
  echo ""
  echo "Installing NVIDIA drivers..."
  
  local packages_json="$SCRIPT_DIR/../config/packages.json"
  local packages=()
  
  if [[ -f "$packages_json" ]]; then
    mapfile -t packages < <(jq -r '.graphics.nvidia[]' "$packages_json" 2>/dev/null)
  fi
  
  if [[ ${#packages[@]} -eq 0 ]]; then
    echo "Warning: No NVIDIA packages found in packages.json, using defaults"
    packages=("nvidia" "nvidia-utils" "nvidia-settings")
  fi
  
  if pacman -S --noconfirm --needed "${packages[@]}"; then
    echo "✓ NVIDIA drivers installed"
  else
    echo "Error: Failed to install NVIDIA drivers"
    return 1
  fi
  
  # Check for LTS kernel
  if pacman -Q linux-lts &>/dev/null; then
    echo "LTS kernel detected, installing nvidia-lts..."
    pacman -S --noconfirm --needed nvidia-lts || {
      echo "Warning: Failed to install nvidia-lts"
    }
  fi
  
  # Enable DRM modeset
  echo "Configuring NVIDIA DRM modeset..."
  if [[ -f /etc/default/grub ]]; then
    if ! grep -q "nvidia-drm.modeset=1" /etc/default/grub; then
      sed -i '/^GRUB_CMDLINE_LINUX=/ s/"$/ nvidia-drm.modeset=1"/' /etc/default/grub
      echo "✓ DRM modeset added to GRUB config"
      
      # Regenerate GRUB config
      if command -v grub-mkconfig &>/dev/null; then
        grub-mkconfig -o /boot/grub/grub.cfg &>/dev/null && \
          echo "✓ GRUB configuration updated"
      fi
    else
      echo "✓ DRM modeset already configured"
    fi
  fi
  
  # Rebuild initramfs
  echo "Rebuilding initramfs..."
  if mkinitcpio -P &>/dev/null; then
    echo "✓ Initramfs rebuilt"
  else
    echo "Warning: Failed to rebuild initramfs"
  fi
  
  return 0
}

# Function: gpu::install_amd
# Installs AMD open-source drivers.
gpu::install_amd() {
  echo ""
  echo "Installing AMD drivers..."
  
  local packages_json="$SCRIPT_DIR/../config/packages.json"
  local packages=()
  
  if [[ -f "$packages_json" ]]; then
    mapfile -t packages < <(jq -r '.graphics.amd[]' "$packages_json" 2>/dev/null)
  fi
  
  if [[ ${#packages[@]} -eq 0 ]]; then
    echo "Warning: No AMD packages found in packages.json, using defaults"
    packages=(
      "mesa"
      "lib32-mesa"
      "libva-mesa-driver"
      "lib32-libva-mesa-driver"
      "mesa-vdpau"
      "lib32-mesa-vdpau"
      "vulkan-radeon"
      "lib32-vulkan-radeon"
      "xf86-video-amdgpu"
    )
  fi
  
  if pacman -S --noconfirm --needed "${packages[@]}"; then
    echo "✓ AMD drivers installed"
  else
    echo "Error: Failed to install AMD drivers"
    return 1
  fi
  
  return 0
}

# Function: gpu::install_intel
# Installs Intel open-source drivers.
gpu::install_intel() {
  echo ""
  echo "Installing Intel drivers..."
  
  local packages_json="$SCRIPT_DIR/../config/packages.json"
  local packages=()
  
  if [[ -f "$packages_json" ]]; then
    mapfile -t packages < <(jq -r '.graphics.intel[]' "$packages_json" 2>/dev/null)
  fi
  
  if [[ ${#packages[@]} -eq 0 ]]; then
    echo "Warning: No Intel packages found in packages.json, using defaults"
    packages=(
      "mesa"
      "lib32-mesa"
      "vulkan-intel"
      "lib32-vulkan-intel"
      "intel-media-driver"
      "intel-gpu-tools"
      "mesa-vdpau"
      "lib32-mesa-vdpau"
    )
  fi
  
  if pacman -S --noconfirm --needed "${packages[@]}"; then
    echo "✓ Intel drivers installed"
  else
    echo "Error: Failed to install Intel drivers"
    return 1
  fi
  
  return 0
}

# Function: gpu::install_vm
# Installs virtual machine graphics drivers.
gpu::install_vm() {
  echo ""
  echo "=========================================="
  echo "  Virtual Machine Graphics"
  echo "=========================================="
  echo ""
  echo "Select virtualization platform:"
  echo "  1) QEMU with Spice/QXL"
  echo "  2) QEMU with VirtIO-GPU/VirGL"
  echo "  3) VMware Workstation/ESXi"
  echo "  4) VirtualBox"
  echo "  5) Skip VM drivers"
  echo ""
  
  local packages_json="$SCRIPT_DIR/../config/packages.json"
  
  while true; do
    read -p "Select platform [1-5]: " -n 1 -r
    echo
    
    case $REPLY in
      1)
        echo "Installing QEMU Spice/QXL drivers..."
        local packages=()
        if [[ -f "$packages_json" ]]; then
          mapfile -t packages < <(jq -r '.graphics.vm_qxl[]' "$packages_json" 2>/dev/null)
        fi
        [[ ${#packages[@]} -eq 0 ]] && packages=("xf86-video-qxl" "qemu-guest-agent" "spice-vdagent")
        pacman -S --noconfirm --needed "${packages[@]}" && \
          echo "✓ QEMU Spice/QXL drivers installed"
        break
        ;;
      2)
        echo "Installing VirtIO-GPU/VirGL drivers..."
        local packages=()
        if [[ -f "$packages_json" ]]; then
          mapfile -t packages < <(jq -r '.graphics.vm_virtio[]' "$packages_json" 2>/dev/null)
        fi
        [[ ${#packages[@]} -eq 0 ]] && packages=("mesa" "virglrenderer" "qemu-guest-agent" "spice-vdagent")
        pacman -S --noconfirm --needed "${packages[@]}" && \
          echo "✓ VirtIO-GPU/VirGL drivers installed"
        break
        ;;
      3)
        echo "Installing VMware tools..."
        local packages=()
        if [[ -f "$packages_json" ]]; then
          mapfile -t packages < <(jq -r '.graphics.vm_vmware[]' "$packages_json" 2>/dev/null)
        fi
        [[ ${#packages[@]} -eq 0 ]] && packages=("open-vm-tools" "xf86-video-vmware")
        pacman -S --noconfirm --needed "${packages[@]}" && \
          echo "✓ VMware tools installed"
        systemctl enable vmtoolsd 2>/dev/null && echo "✓ VMware service enabled"
        break
        ;;
      4)
        echo "Installing VirtualBox guest additions..."
        local packages=()
        if [[ -f "$packages_json" ]]; then
          mapfile -t packages < <(jq -r '.graphics.vm_virtualbox[]' "$packages_json" 2>/dev/null)
        fi
        [[ ${#packages[@]} -eq 0 ]] && packages=("virtualbox-guest-utils")
        pacman -S --noconfirm --needed "${packages[@]}" && \
          echo "✓ VirtualBox guest additions installed"
        systemctl enable vboxservice 2>/dev/null && echo "✓ VirtualBox service enabled"
        break
        ;;
      5)
        echo "Skipping VM driver installation"
        break
        ;;
      *)
        echo "Invalid choice. Please select 1-5."
        ;;
    esac
  done
  
  return 0
}

# Function: gpu::install
# Main graphics driver installation function.
# Uses GPU_VENDOR variable to determine which driver to install.
gpu::install() {
  local vendor="${1:-$GPU_VENDOR}"
  
  if [[ -z "$vendor" || "$vendor" == "unknown" ]]; then
    echo "Warning: No graphics vendor specified"
    return 1
  fi
  
  if [[ "$vendor" == "skip" ]]; then
    echo "Skipping graphics driver installation"
    return 0
  fi
  
  echo ""
  echo "=========================================="
  echo "  Installing $vendor Graphics Drivers"
  echo "=========================================="
  
  case "$vendor" in
    nvidia)
      gpu::install_nvidia
      ;;
    amd)
      gpu::install_amd
      ;;
    intel)
      gpu::install_intel
      ;;
    vm)
      gpu::install_vm
      ;;
    *)
      echo "Error: Unknown graphics vendor: $vendor"
      return 1
      ;;
  esac
  
  if [[ $? -eq 0 ]]; then
    echo ""
    echo "✓ Graphics drivers installed successfully"
    return 0
  else
    echo ""
    echo "⚠ Graphics driver installation encountered issues"
    return 1
  fi
}
