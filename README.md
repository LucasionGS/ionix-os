# Ionix

A custom Arch Linux installation system with automated setup scripts.

## Overview

Ionix provides a streamlined way to install and configure Arch Linux on a fresh system. Instead of using the traditional Arch ISO, these scripts are designed to run on a clean Arch Linux boot drive and help you build a complete custom system.

## Prerequisites

Before running the installation:

1. **Boot into a live Arch Linux environment** (e.g., from USB)
2. **Ensure you have internet connectivity**
3. **Have `git`, `curl`, and `wget` installed** (or the script will notify you)
4. **Partition your disk** and know which partition to use

## Installation Process

### Quick Start

1. **Boot into a live Arch Linux environment** (e.g., from USB)
2. **Ensure you have internet connectivity**
3. **Have `curl` installed** (sudo pacman -Sy curl)
4. **Execute**
```bash
bash -i <(curl -fsSL https://raw.githubusercontent.com/LucasionGS/ionix-os/main/bootstrap.sh)
```

### Manual Steps

### Step 1: Clone the Repository

```bash
git clone https://github.com/yourusername/ionix.git
cd ionix
```

### Step 2: Run the Main Installer

```bash
chmod +x install.sh
./install.sh
```

The installer will guide you through:

1. **Keyboard Layout Selection** - Fuzzy search through all available layouts
2. **Timezone Configuration** - Select your timezone (e.g., America/New_York)
3. **Locale Selection** - Choose your system locale (e.g., en_US.UTF-8)
4. **Hostname Setup** - Set your computer's hostname
5. **Partition Selection** - Choose the target partition for installation

After configuration, the installer will:
- Mount your selected partition to `/mnt`
- Run `pacstrap` to install the base system
- Generate `fstab`
- Copy all Ionix scripts to `/mnt/root/ionix`
- Save your configuration for the chroot environment

### Step 3: Enter Chroot and Complete Setup

```bash
arch-chroot /mnt
cd /root/ionix
./chroot-setup.sh
```

The chroot setup script will:
- Apply timezone, locale, keymap, and hostname configuration
- Enable NetworkManager
- Install essential packages (`base-devel`, `sudo`)
- Set up user accounts (root password + optional user)
- Configure sudo access for the wheel group
- Install and configure a bootloader (GRUB or systemd-boot)
- Install CPU microcode (Intel or AMD)
- Regenerate initramfs

### Step 4: Finalize and Reboot

```bash
exit                    # Exit chroot
umount -R /mnt         # Unmount all partitions
reboot                 # Reboot into your new system
```

## Project Structure

```
ionix/
├── install.sh              # Main installation script (pre-chroot)
├── chroot-setup.sh         # System configuration script (inside chroot)
├── config/                 # Installation configuration files (not dotfiles)
├── lib/
│   ├── software.sh         # Software utility functions
│   ├── pacstrap.sh         # Pacstrap and base installation
│   ├── configure.sh        # System configuration (timezone, locale, etc.)
│   ├── users.sh            # User and authentication management
│   └── bootloader.sh       # Bootloader installation (GRUB/systemd-boot)
├── root/                   # Files to copy to target system root
└── README.md              # This file
```

## Library Functions

### `lib/software.sh`
- `sw::is_installed()` - Check if a command/package is installed

### `lib/pacstrap.sh`
- `pacstrap::install_base_system()` - Install base Arch system to target

### `lib/configure.sh`
- `cfg::set_timezone()` - Configure system timezone
- `cfg::set_locale()` - Configure system locale
- `cfg::set_keymap()` - Configure console keyboard layout
- `cfg::set_hostname()` - Configure system hostname
- `cfg::enable_networkmanager()` - Enable NetworkManager service
- `cfg::regenerate_initramfs()` - Regenerate initramfs images

### `lib/users.sh`
- `user::set_root_password()` - Set root password
- `user::create_user()` - Create a new user account
- `user::configure_sudo()` - Configure sudo access
- `user::setup_interactive()` - Interactive user setup wizard

### `lib/bootloader.sh`
- `boot::detect_firmware()` - Detect UEFI or BIOS
- `boot::detect_cpu()` - Detect Intel or AMD CPU
- `boot::install_microcode()` - Install CPU microcode
- `boot::install_grub()` - Install and configure GRUB
- `boot::install_systemd_boot()` - Install and configure systemd-boot
- `boot::setup_interactive()` - Interactive bootloader setup wizard

## Features

- **Interactive Configuration** - Fuzzy-searchable selection menus using `fzf`
- **Safety Checks** - Validates mount points and requires explicit confirmation
- **Modular Design** - Organized into namespaced library functions
- **Error Handling** - Comprehensive error checking and informative messages
- **Flexible Bootloader** - Choose between GRUB (BIOS/UEFI) or systemd-boot (UEFI)
- **Automatic Detection** - Detects firmware type (UEFI/BIOS) and CPU vendor

## Configuration File

After running `install.sh`, your configuration is saved to `/mnt/root/ionix/ionix.conf`:

```bash
KEYMAP="us"
TIMEZONE="America/New_York"
LOCALE="en_US.UTF-8"
HOSTNAME="ionix-system"
INSTALL_TARGET="/dev/sda2"
MOUNT_POINT="/mnt"
```

This file is automatically loaded by `chroot-setup.sh` to apply your settings inside the chroot environment.

## Customization

You can modify the base packages by editing `lib/pacstrap.sh`:

```bash
local base_packages=("base" "linux" "linux-firmware" "vim" "networkmanager")
```

Add any additional packages you want installed during the initial `pacstrap` phase.

## Troubleshooting

### fzf not installed
The script will automatically attempt to install `fzf`. If it fails, you can install it manually:
```bash
pacman -S fzf
```

### Bootloader installation fails
Make sure:
- For UEFI: Your EFI partition is mounted (usually to `/boot/efi`)
- For BIOS: You're specifying the disk device (e.g., `/dev/sda`), not a partition

### NetworkManager not starting
After reboot, manually start NetworkManager:
```bash
systemctl start NetworkManager
systemctl enable NetworkManager
```

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

## License

This project is provided as-is for personal use.

## Acknowledgments

Built for Arch Linux installation automation, inspired by the Arch installation guide. 