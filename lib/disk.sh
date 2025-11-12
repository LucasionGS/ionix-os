# Namespace: disk
# Disk partitioning and management functions for Ionix installation.

# Function: disk::select_disk
# Interactive disk selection for installation.
# Sets global variable: INSTALL_DISK
disk::select_disk() {
  echo ""
  echo "Selecting installation disk..."
  
  # Get list of disks (not partitions)
  local disks
  disks=$(lsblk -ndo NAME,SIZE,TYPE,MODEL | \
    grep "disk" | \
    awk '{printf "%-15s %-10s %-10s %s\n", "/dev/"$1, $2, $3, $4}')
  
  if [[ -z "$disks" ]]; then
    echo "Error: No disks found."
    return 1
  fi
  
  # Show current disk layout
  echo ""
  echo "Available disks:"
  lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT
  echo ""
  
  # Check if fzf is available
  if ! command -v fzf &> /dev/null; then
    echo "fzf not available, using manual selection."
    echo "$disks"
    read -p "Enter disk path (e.g., /dev/sda): " INSTALL_DISK
  else
    # Use fzf for selection
    echo "Select disk for installation (type to search, Enter to confirm):"
    INSTALL_DISK=$(echo "$disks" | fzf \
      --height=15 \
      --border=rounded \
      --prompt="Installation disk > " \
      --header="⚠ WARNING: This disk will be partitioned!" \
      --preview="lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT | grep -A 10 {1}" \
      --preview-window=up:8:wrap | \
      awk '{print $1}')
  fi
  
  if [[ -z "$INSTALL_DISK" ]]; then
    echo "Error: No disk selected."
    return 1
  fi
  
  # Confirm selection
  echo ""
  echo "⚠  WARNING: Selected disk: $INSTALL_DISK"
  lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT "$INSTALL_DISK" 2>/dev/null || true
  echo ""
  echo "⚠  ALL DATA ON THIS DISK WILL BE DESTROYED!"
  echo ""
  read -p "Type 'DELETE ALL DATA' to confirm: " confirm
  
  if [[ "$confirm" != "DELETE ALL DATA" ]]; then
    echo "Disk selection not confirmed. Exiting."
    return 1
  fi
  
  echo "✓ Disk confirmed: $INSTALL_DISK"
  return 0
}

# Function: disk::partition_auto
# Automatically partition disk with sensible defaults.
# For UEFI: 512M EFI + rest root
# For BIOS: rest root (with BIOS boot if GPT)
disk::partition_auto() {
  local disk="$1"
  
  echo ""
  echo "=========================================="
  echo "  Automatic Partitioning"
  echo "=========================================="
  echo ""
  
  # Detect firmware type
  if [[ -d /sys/firmware/efi/efivars ]]; then
    echo "UEFI system detected - will create EFI partition"
    FIRMWARE_TYPE="uefi"
  else
    echo "BIOS system detected - will create simple partition table"
    FIRMWARE_TYPE="bios"
  fi
  
  echo ""
  echo "Wiping disk $disk..."
  wipefs -af "$disk" || {
    echo "Error: Failed to wipe disk."
    return 1
  }
  
  if [[ "$FIRMWARE_TYPE" == "uefi" ]]; then
    echo "Creating GPT partition table for UEFI..."
    
    # Create GPT table and partitions using parted
    parted -s "$disk" mklabel gpt || return 1
    parted -s "$disk" mkpart primary fat32 1MiB 513MiB || return 1
    parted -s "$disk" set 1 esp on || return 1
    parted -s "$disk" mkpart primary ext4 513MiB 100% || return 1
    
    # Wait for kernel to recognize partitions
    sleep 2
    partprobe "$disk"
    sleep 1
    
    # Determine partition names
    if [[ "$disk" =~ nvme ]]; then
      EFI_PARTITION="${disk}p1"
      ROOT_PARTITION="${disk}p2"
    else
      EFI_PARTITION="${disk}1"
      ROOT_PARTITION="${disk}2"
    fi
    
    echo "✓ Partitions created:"
    echo "  EFI:  $EFI_PARTITION (512M)"
    echo "  Root: $ROOT_PARTITION (remaining space)"
    
    # Format partitions
    echo ""
    echo "Formatting EFI partition..."
    mkfs.fat -F32 "$EFI_PARTITION" || {
      echo "Error: Failed to format EFI partition."
      return 1
    }
    
    echo "Formatting root partition..."
    mkfs.ext4 -F "$ROOT_PARTITION" || {
      echo "Error: Failed to format root partition."
      return 1
    }
    
    echo "✓ Partitions formatted successfully."
    
    # Set global variables for later use
    INSTALL_TARGET="$ROOT_PARTITION"
    EFI_MOUNT="/boot"
    
  else
    # BIOS system - simple MBR
    echo "Creating MBR partition table for BIOS..."
    
    parted -s "$disk" mklabel msdos || return 1
    parted -s "$disk" mkpart primary ext4 1MiB 100% || return 1
    parted -s "$disk" set 1 boot on || return 1
    
    # Wait for kernel to recognize partitions
    sleep 2
    partprobe "$disk"
    sleep 1
    
    # Determine partition name
    if [[ "$disk" =~ nvme ]]; then
      ROOT_PARTITION="${disk}p1"
    else
      ROOT_PARTITION="${disk}1"
    fi
    
    echo "✓ Partition created:"
    echo "  Root: $ROOT_PARTITION (entire disk)"
    
    # Format partition
    echo ""
    echo "Formatting root partition..."
    mkfs.ext4 -F "$ROOT_PARTITION" || {
      echo "Error: Failed to format root partition."
      return 1
    }
    
    echo "✓ Partition formatted successfully."
    
    # Set global variables
    INSTALL_TARGET="$ROOT_PARTITION"
  fi
  
  return 0
}

# Function: disk::partition_preset
# Partition with preset configurations (e.g., with swap, home partition).
disk::partition_preset() {
  local disk="$1"
  
  echo ""
  echo "=========================================="
  echo "  Preset Partitioning Schemes"
  echo "=========================================="
  echo ""
  echo "Select a preset:"
  echo "  1) Minimal (EFI/Boot + Root only)"
  echo "  2) Standard (EFI/Boot + Swap + Root)"
  echo "  3) Advanced (EFI/Boot + Swap + Root + Home)"
  echo ""
  
  read -p "Enter choice (1-3): " -n 1 -r
  echo
  
  local preset="$REPLY"
  
  # Detect firmware
  if [[ -d /sys/firmware/efi/efivars ]]; then
    FIRMWARE_TYPE="uefi"
  else
    FIRMWARE_TYPE="bios"
  fi
  
  # Get disk size in GB for swap calculation
  local disk_size_gb
  disk_size_gb=$(lsblk -bno SIZE "$disk" | head -1 | awk '{print int($1/1024/1024/1024)}')
  
  # Calculate swap size (RAM size or 4GB, whichever is smaller, for standard preset)
  local swap_size_gb=4
  local ram_gb
  ram_gb=$(free -g | awk '/^Mem:/{print $2}')
  if [[ $ram_gb -lt 4 ]]; then
    swap_size_gb=$ram_gb
  fi
  
  echo ""
  echo "Wiping disk $disk..."
  wipefs -af "$disk" || return 1
  
  case $preset in
    1)
      # Minimal - same as auto
      echo "Creating minimal partition layout..."
      disk::partition_auto "$disk"
      return $?
      ;;
    
    2)
      # Standard - with swap
      echo "Creating standard partition layout (with ${swap_size_gb}GB swap)..."
      
      if [[ "$FIRMWARE_TYPE" == "uefi" ]]; then
        parted -s "$disk" mklabel gpt || return 1
        parted -s "$disk" mkpart primary fat32 1MiB 513MiB || return 1
        parted -s "$disk" set 1 esp on || return 1
        parted -s "$disk" mkpart primary linux-swap 513MiB $((513 + swap_size_gb * 1024))MiB || return 1
        parted -s "$disk" mkpart primary ext4 $((513 + swap_size_gb * 1024))MiB 100% || return 1
        
        sleep 2
        partprobe "$disk"
        sleep 1
        
        if [[ "$disk" =~ nvme ]]; then
          EFI_PARTITION="${disk}p1"
          SWAP_PARTITION="${disk}p2"
          ROOT_PARTITION="${disk}p3"
        else
          EFI_PARTITION="${disk}1"
          SWAP_PARTITION="${disk}2"
          ROOT_PARTITION="${disk}3"
        fi
        
        mkfs.fat -F32 "$EFI_PARTITION" || return 1
        mkswap "$SWAP_PARTITION" || return 1
        mkfs.ext4 -F "$ROOT_PARTITION" || return 1
        
        EFI_MOUNT="/boot"
      else
        parted -s "$disk" mklabel msdos || return 1
        parted -s "$disk" mkpart primary linux-swap 1MiB $((1 + swap_size_gb * 1024))MiB || return 1
        parted -s "$disk" mkpart primary ext4 $((1 + swap_size_gb * 1024))MiB 100% || return 1
        parted -s "$disk" set 2 boot on || return 1
        
        sleep 2
        partprobe "$disk"
        sleep 1
        
        if [[ "$disk" =~ nvme ]]; then
          SWAP_PARTITION="${disk}p1"
          ROOT_PARTITION="${disk}p2"
        else
          SWAP_PARTITION="${disk}1"
          ROOT_PARTITION="${disk}2"
        fi
        
        mkswap "$SWAP_PARTITION" || return 1
        mkfs.ext4 -F "$ROOT_PARTITION" || return 1
      fi
      
      echo "✓ Swap partition created: $SWAP_PARTITION (${swap_size_gb}GB)"
      INSTALL_TARGET="$ROOT_PARTITION"
      ;;
    
    3)
      # Advanced - with swap and home
      echo "Creating advanced partition layout (with ${swap_size_gb}GB swap + separate home)..."
      
      # For home, use 40% of remaining space for root, 60% for home
      if [[ "$FIRMWARE_TYPE" == "uefi" ]]; then
        local remaining_space=$((disk_size_gb - 1 - swap_size_gb))
        local root_size=$((remaining_space * 40 / 100))
        
        parted -s "$disk" mklabel gpt || return 1
        parted -s "$disk" mkpart primary fat32 1MiB 513MiB || return 1
        parted -s "$disk" set 1 esp on || return 1
        parted -s "$disk" mkpart primary linux-swap 513MiB $((513 + swap_size_gb * 1024))MiB || return 1
        parted -s "$disk" mkpart primary ext4 $((513 + swap_size_gb * 1024))MiB $((513 + swap_size_gb * 1024 + root_size * 1024))MiB || return 1
        parted -s "$disk" mkpart primary ext4 $((513 + swap_size_gb * 1024 + root_size * 1024))MiB 100% || return 1
        
        sleep 2
        partprobe "$disk"
        sleep 1
        
        if [[ "$disk" =~ nvme ]]; then
          EFI_PARTITION="${disk}p1"
          SWAP_PARTITION="${disk}p2"
          ROOT_PARTITION="${disk}p3"
          HOME_PARTITION="${disk}p4"
        else
          EFI_PARTITION="${disk}1"
          SWAP_PARTITION="${disk}2"
          ROOT_PARTITION="${disk}3"
          HOME_PARTITION="${disk}4"
        fi
        
        mkfs.fat -F32 "$EFI_PARTITION" || return 1
        mkswap "$SWAP_PARTITION" || return 1
        mkfs.ext4 -F "$ROOT_PARTITION" || return 1
        mkfs.ext4 -F "$HOME_PARTITION" || return 1
        
        EFI_MOUNT="/boot"
      else
        local remaining_space=$((disk_size_gb - swap_size_gb))
        local root_size=$((remaining_space * 40 / 100))
        
        parted -s "$disk" mklabel msdos || return 1
        parted -s "$disk" mkpart primary linux-swap 1MiB $((1 + swap_size_gb * 1024))MiB || return 1
        parted -s "$disk" mkpart primary ext4 $((1 + swap_size_gb * 1024))MiB $((1 + swap_size_gb * 1024 + root_size * 1024))MiB || return 1
        parted -s "$disk" set 2 boot on || return 1
        parted -s "$disk" mkpart primary ext4 $((1 + swap_size_gb * 1024 + root_size * 1024))MiB 100% || return 1
        
        sleep 2
        partprobe "$disk"
        sleep 1
        
        if [[ "$disk" =~ nvme ]]; then
          SWAP_PARTITION="${disk}p1"
          ROOT_PARTITION="${disk}p2"
          HOME_PARTITION="${disk}p3"
        else
          SWAP_PARTITION="${disk}1"
          ROOT_PARTITION="${disk}2"
          HOME_PARTITION="${disk}3"
        fi
        
        mkswap "$SWAP_PARTITION" || return 1
        mkfs.ext4 -F "$ROOT_PARTITION" || return 1
        mkfs.ext4 -F "$HOME_PARTITION" || return 1
      fi
      
      echo "✓ Swap partition: $SWAP_PARTITION (${swap_size_gb}GB)"
      echo "✓ Home partition: $HOME_PARTITION"
      INSTALL_TARGET="$ROOT_PARTITION"
      ;;
    
    *)
      echo "Invalid choice."
      return 1
      ;;
  esac
  
  echo "✓ Partitions created and formatted successfully."
  return 0
}

# Function: disk::partition_custom
# Guide user through custom partitioning with cfdisk.
disk::partition_custom() {
  local disk="$1"
  
  echo ""
  echo "=========================================="
  echo "  Custom Partitioning"
  echo "=========================================="
  echo ""
  echo "You will now use cfdisk to manually partition the disk."
  echo ""
  
  # Detect firmware for guidance
  if [[ -d /sys/firmware/efi/efivars ]]; then
    echo "UEFI system detected. Recommended layout:"
    echo "  1. EFI System Partition: 512M, Type: EFI System"
    echo "  2. Root partition: remaining space, Type: Linux filesystem"
    echo "  Optional: Swap partition (RAM size)"
  else
    echo "BIOS system detected. Recommended layout:"
    echo "  1. Root partition: entire disk, Type: Linux, bootable"
    echo "  Optional: Swap partition (RAM size)"
  fi
  
  echo ""
  read -p "Press Enter to open cfdisk..." 
  
  # Launch cfdisk
  cfdisk "$disk"
  
  if [[ $? -ne 0 ]]; then
    echo "Error: cfdisk exited with error."
    return 1
  fi
  
  echo ""
  echo "Partitioning complete. New partition layout:"
  lsblk -o NAME,SIZE,TYPE,FSTYPE "$disk"
  echo ""
  
  # Now ask user to format partitions
  echo "Now you need to format your partitions."
  echo ""
  
  # Get list of partitions on the disk
  local partitions
  if [[ "$disk" =~ nvme ]]; then
    partitions=$(lsblk -no NAME "$disk" | grep "${disk##*/}p" | sed "s|^|/dev/|")
  else
    partitions=$(lsblk -no NAME "$disk" | grep -v "^${disk##*/}$" | sed "s|^|/dev/|")
  fi
  
  echo "Available partitions:"
  lsblk -o NAME,SIZE,TYPE "$disk"
  echo ""
  
  # Ask for root partition
  read -p "Enter root partition (e.g., /dev/sda2): " ROOT_PARTITION
  if [[ ! -b "$ROOT_PARTITION" ]]; then
    echo "Error: Invalid partition."
    return 1
  fi
  
  echo "Formatting root partition as ext4..."
  mkfs.ext4 -F "$ROOT_PARTITION" || return 1
  echo "✓ Root partition formatted."
  
  INSTALL_TARGET="$ROOT_PARTITION"
  
  # Ask for EFI partition if UEFI
  if [[ -d /sys/firmware/efi/efivars ]]; then
    echo ""
    read -p "Enter EFI partition (e.g., /dev/sda1): " EFI_PARTITION
    if [[ ! -b "$EFI_PARTITION" ]]; then
      echo "Warning: Invalid EFI partition. You'll need to configure bootloader manually."
    else
      echo "Formatting EFI partition as FAT32..."
      mkfs.fat -F32 "$EFI_PARTITION" || {
        echo "Warning: Failed to format EFI partition."
      }
      echo "✓ EFI partition formatted."
      EFI_MOUNT="/boot"
    fi
  fi
  
  # Ask about swap
  echo ""
  read -p "Do you have a swap partition? (y/N): " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    read -p "Enter swap partition (e.g., /dev/sda3): " SWAP_PARTITION
    if [[ -b "$SWAP_PARTITION" ]]; then
      echo "Setting up swap..."
      mkswap "$SWAP_PARTITION" || {
        echo "Warning: Failed to setup swap."
      }
      echo "✓ Swap configured."
    fi
  fi
  
  # Ask about home
  echo ""
  read -p "Do you have a separate home partition? (y/N): " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    read -p "Enter home partition (e.g., /dev/sda4): " HOME_PARTITION
    if [[ -b "$HOME_PARTITION" ]]; then
      echo "Formatting home partition as ext4..."
      mkfs.ext4 -F "$HOME_PARTITION" || {
        echo "Warning: Failed to format home partition."
      }
      echo "✓ Home partition formatted."
    fi
  fi
  
  return 0
}

# Function: disk::partition_interactive
# Main interactive partitioning function.
disk::partition_interactive() {
  echo ""
  echo "=========================================="
  echo "  Disk Partitioning"
  echo "=========================================="
  echo ""
  echo "Choose partitioning method:"
  echo "  1) Automatic (recommended for most users)"
  echo "  2) Preset schemes (with swap, home partition, etc.)"
  echo "  3) Custom (manual partitioning with cfdisk)"
  echo "  4) Use existing partitions (skip partitioning)"
  echo ""
  
  while true; do
    read -p "Enter choice (1-4): " -n 1 -r
    echo
    
    case $REPLY in
      1|2|3)
        # Need to select disk first
        disk::select_disk || return 1
        
        case $REPLY in
          1)
            disk::partition_auto "$INSTALL_DISK" || return 1
            ;;
          2)
            disk::partition_preset "$INSTALL_DISK" || return 1
            ;;
          3)
            disk::partition_custom "$INSTALL_DISK" || return 1
            ;;
        esac
        break
        ;;
      4)
        echo "Skipping partitioning. You will select existing partitions."
        return 0
        ;;
      *)
        echo "Invalid choice. Please enter 1-4."
        ;;
    esac
  done
  
  return 0
}
