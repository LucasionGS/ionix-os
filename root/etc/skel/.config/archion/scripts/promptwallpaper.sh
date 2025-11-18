#!/bin/bash
ARCHION_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/archion"

SWWW_ARGS="--transition-type=wave --transition-duration=2 --transition-fps=60 --transition-step=255"

# Show usage if help is requested
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
  echo "Usage: $0 [file1] [file2] ..."
  echo "       $0"
  echo ""
  echo "Set wallpaper(s) using swww."
  echo "If file paths are provided as arguments, they will be used directly."
  echo "If no arguments are provided, a file selection dialog will be shown."
  echo ""
  echo "Examples:"
  echo "  $0 ~/Pictures/wallpaper.jpg"
  echo "  $0 ~/Pictures/wall1.jpg ~/Pictures/wall2.png"
  echo "  $0  # Shows file selection dialog"
  exit 0
fi

clean_cache() {
  # Remove old wallpapers from the active directory
  rm -f $ARCHION_DIR/.wallpapers_active/*
}

mkdir -p "$HOME/Pictures/Wallpapers"
mkdir -p "$ARCHION_DIR/.wallpapers_active"

# Check if files were passed as command line arguments
if [ $# -gt 0 ]; then
  # Use command line arguments as file paths
  FILE_ARRAY=("$@")
  
  # Validate that all files exist
  for file in "${FILE_ARRAY[@]}"; do
    if [ ! -f "$file" ]; then
      echo "Error: File '$file' does not exist" >&2
      exit 1
    fi
  done
  
  # Join the array elements with | separator for consistency
  FILE_PATHS=$(IFS='|'; echo "${FILE_ARRAY[*]}")
else
  # Ask for file path using zenity
  FILE_PATHS=$(zenity --file-selection --multiple --title="Select a Wallpaper Image(s)" --file-filter="*.jpg *.jpeg *.png *.gif" --separator="|" --filename="$HOME/Pictures/Wallpapers/" --width=800 --height=600)
  
  # Check if the user selected any files
  if [ -z "$FILE_PATHS" ]; then
    exit 1
  fi
  
  # Convert the selected file paths into an array
  IFS='|' read -r -a FILE_ARRAY <<< "$FILE_PATHS"
fi
# Select the first file from the array
FILE_PATH="${FILE_ARRAY[0]}"

# If multiple files were selected, copy them to the active wallpapers directory
if [ ${#FILE_ARRAY[@]} -gt 0 ]; then
  clean_cache
  for file in "${FILE_ARRAY[@]}"; do
    cp "$file" "$ARCHION_DIR/.wallpapers_active/"
  done
# else
#   # If only one file was selected, copy it to the active wallpapers directory
#   cp "$FILE_PATH" "$ARCHION_DIR/.wallpapers_active/"
fi

if [ -n "$FILE_PATH" ]; then
  # Set the wallpaper using swww
  swww img $SWWW_ARGS "$FILE_PATH"
fi