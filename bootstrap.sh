#!/bin/bash
# bootstrap.sh for remote execution directly from github, to install the repository and run install.sh

set -e
# Download and run the install script
sudo pacman -Sy --noconfirm --needed git curl wget
git clone https://github.com/LucasionGS/ionix-os.git
cd ionix-os

chmod +x install.sh
./install.sh

# How to use
# curl -sSL https://raw.githubusercontent.com/LucasionGS/ionix-os/main/bootstrap.sh | bash