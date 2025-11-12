# Namespace: user
# User and authentication management functions for Ionix installation.

# Function: user::set_root_password
# Sets the root password interactively.
user::set_root_password() {
  echo "Setting root password..."
  
  if passwd; then
    echo "✓ Root password set successfully."
  else
    echo "Error: Failed to set root password."
    return 1
  fi
  
  return 0
}

# Function: user::create_user
# Creates a new user account with home directory.
# Arguments:
#   $1 - Username
#   $2 - Full name (optional)
user::create_user() {
  local username="$1"
  local fullname="$2"
  
  if [[ -z "$username" ]]; then
    echo "Error: Username not specified."
    return 1
  fi
  
  echo "Creating user: $username..."
  
  # Create user with home directory
  local useradd_opts=(-m -G wheel,audio,video,optical,storage)
  
  if [[ -n "$fullname" ]]; then
    useradd_opts+=(-c "$fullname")
  fi
  
  if useradd "${useradd_opts[@]}" "$username"; then
    echo "✓ User $username created."
  else
    echo "Error: Failed to create user $username."
    return 1
  fi
  
  # Set password for user
  echo "Setting password for $username..."
  if passwd "$username"; then
    echo "✓ Password set for $username."
  else
    echo "Error: Failed to set password for $username."
    return 1
  fi
  
  return 0
}

# Function: user::configure_sudo
# Configures sudo access for wheel group.
user::configure_sudo() {
  echo "Configuring sudo access..."
  
  # Check if sudo is installed
  if ! command -v sudo &> /dev/null; then
    echo "Error: sudo is not installed."
    return 1
  fi
  
  # Uncomment wheel group in sudoers using sed
  if sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers; then
    echo "✓ Sudo access configured for wheel group."
  else
    echo "Error: Failed to configure sudo."
    return 1
  fi
  
  return 0
}

# Function: user::setup_interactive
# Interactive user setup wizard.
user::setup_interactive() {
  echo ""
  echo "=========================================="
  echo "  User Account Setup"
  echo "=========================================="
  echo ""
  
  # Root password
  user::set_root_password || return 1
  
  echo ""
  read -p "Create a new user account? (Y/n): " -n 1 -r
  echo
  
  if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    # Get username
    while true; do
      read -p "Enter username: " username
      
      if [[ -z "$username" ]]; then
        echo "Error: Username cannot be empty."
        continue
      fi
      
      # Validate username
      if [[ ! "$username" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        echo "Error: Invalid username. Use lowercase letters, numbers, underscores, and hyphens."
        echo "       Must start with a letter or underscore."
        continue
      fi
      
      break
    done
    
    # Get full name (optional)
    read -p "Enter full name (optional): " fullname
    
    # Create user
    user::create_user "$username" "$fullname" || return 1
    
    # Configure sudo
    user::configure_sudo || return 1
  fi
  
  return 0
}
