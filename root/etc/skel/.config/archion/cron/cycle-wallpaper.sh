#!/bin/bash
ARCHION_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/archion"
WALLPAPER_DIR="$ARCHION_DIR/.wallpapers_active"
SWWW_ARGS="--transition-type=wave --transition-duration=2 --transition-fps=60 --transition-step=255"

# Get all available wallpapers
ALL_WALLPAPERS=($(find "$WALLPAPER_DIR" -type f \( -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" -o -name "*.gif" \)))

if [ ${#ALL_WALLPAPERS[@]} -eq 0 ]; then
  echo "No wallpapers found in $WALLPAPER_DIR"
  exit 1
fi

# Get all connected displays
DISPLAYS=($(swww query | grep -oP '(?<=: ).+(?=: \d+x\d+)'))

if [ ${#DISPLAYS[@]} -eq 0 ]; then
  echo "No displays found"
  exit 1
fi

# Get current wallpapers for each display to avoid duplicates
declare -A CURRENT_WALLPAPERS
for display in "${DISPLAYS[@]}"; do
  current_wall=$(swww query | grep "^$display:" | grep -oP '(?<=image: ).*')
  display_name=$(echo "$display" | tr -d ' ')
  if [ -n "$current_wall" ]; then
    CURRENT_WALLPAPERS["$display"]="$(realpath "$current_wall")"
  fi
done

# Shuffle wallpapers for random selection
SHUFFLED_WALLPAPERS=($(printf '%s\n' "${ALL_WALLPAPERS[@]}" | shuf))

# Assign a different wallpaper to each display
wallpaper_index=0
for display in "${DISPLAYS[@]}"; do
  # display_name=$(echo "$display" | tr -d ' ')
  # Find a wallpaper that's not currently being used by this display
  selected_wallpaper=""
  for ((i = wallpaper_index; i < ${#SHUFFLED_WALLPAPERS[@]}; i++)); do
    candidate=$(realpath "${SHUFFLED_WALLPAPERS[$i]}")
    if [ "$candidate" != "${CURRENT_WALLPAPERS[$display]}" ]; then
      selected_wallpaper="$candidate"
      wallpaper_index=$((i + 1))
      break
    fi
  done
  
  # If we couldn't find a different wallpaper, use the next one anyway
  if [ -z "$selected_wallpaper" ]; then
    if [ $wallpaper_index -lt ${#SHUFFLED_WALLPAPERS[@]} ]; then
      selected_wallpaper=$(realpath "${SHUFFLED_WALLPAPERS[$wallpaper_index]}")
      wallpaper_index=$((wallpaper_index + 1))
    else
      # Reset to beginning if we've used all wallpapers
      wallpaper_index=0
      selected_wallpaper=$(realpath "${SHUFFLED_WALLPAPERS[$wallpaper_index]}")
      wallpaper_index=$((wallpaper_index + 1))
    fi
  fi
  
  # Set the wallpaper for this specific display
  echo "Setting wallpaper for $display: $(basename "$selected_wallpaper")"
  swww img $SWWW_ARGS --outputs "$display" "$selected_wallpaper"
done

# Notify the user
# notify-send "Wallpapers Changed" "Random wallpapers set for all displays" -t 2000

# Cron job to run this script every minute
# $ crontab -e
# Add the following line to run the script every minute
# * * * * * hyprctl -i 0 dispatch exec "bash ~/.config/archion/cron/cycle-wallpaper.sh" >/dev/null