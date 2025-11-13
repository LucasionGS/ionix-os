# Ionix

Is an opinionated Arch Linux-based system

## Overview

This Ionix installer provides a set of scripts to automate the installation of the system. It is designed to be run from a live Arch Linux environment and will guide you through the installation process to make sure you have everything you need.

## Prerequisites

Before running the installation:

1. **Boot into a live Arch Linux environment** (e.g., from USB)
2. **Ensure you have internet connectivity**
3. **Have `git`, `curl`, and `wget` installed**

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
git clone https://github.com/LucasionGS/ionix.git
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
5. **Partition Selection** - Choose the target disk/partition for installation

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

## License

This project is provided as-is for personal use. It is built as a personal system tailored to my preferences. Feel free to fork, modify and adapt it for your own needs.
If you do use it, credit is much appreciated!

## Credits
- Arch Linux - For being an amazing base system
- All of the open-source projects used within Ionix (All packages can be found in `config/packages.json`)
- Me - For building this thing like legos + some software built for this project