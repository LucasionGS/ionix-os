# Namespace: sw
# Software-related utility functions for Ionix installation scripts.

# Checks if a given software package is installed on the system.
# Arguments:
#   $1 - Name of the software package to check.
sw::is_installed() {
  local package_name="$1"
  if command -v "$package_name" &> /dev/null; then
    return 0
  else
    return 1
  fi
}

# Installs a given software package using the system's package manager.
# Arguments:
#   List of software packages to install.
sw::install() {
  local packages=("$@")
  if [ "$IONIX_PACKAGE_MANAGER" = "pacman" ] || [ -z "$IONIX_PACKAGE_MANAGER" ]; then
    sudo pacman -Syu $IONIX_PACMAN_OPTIONS "${packages[@]}"
  elif [ "$IONIX_PACKAGE_MANAGER" = "yay" ]; then
    yay -Syu $IONIX_PACMAN_OPTIONS "${packages[@]}"
  else
    echo "Error: Unsupported package manager '$IONIX_PACKAGE_MANAGER'."
    exit 1
  fi
}