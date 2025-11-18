#!/usr/bin/env bash

SELECT=false
REVERSE=false
NAV=false
OPEN_STATE="$(astal window-manager state)"
echo "Current state: $OPEN_STATE"


# Close if open (alt only)
if [[ " $* " == *" --alt-only "* ]]; then
  if [ "$OPEN_STATE" = "open" ]; then
    astal window-manager select
    astal window-manager hide
  fi
  exit 0
fi

if [[ " $* " == *" --nav "* ]]; then NAV=true; fi

if [[ " $* " == *" --reverse "* ]]; then REVERSE=true; fi

if [[ " $* " == *" --select "* ]]; then SELECT=true; fi

# Check state 
if [ -z "$OPEN_STATE" ]; then
  OPEN_STATE="closed" # Default to closed
fi

if [ "$OPEN_STATE" = "open" ]; then
  # If the window manager is open, close it
  if $REVERSE; then
    astal window-manager previous
  else
    astal window-manager next
  fi
elif [ $NAV = false ]; then
  # If the window manager is closed, open it
  astal window-manager show
  astal window-manager next
fi