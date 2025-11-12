# Environment variables
set -gx EDITOR nvim

# bobthefish settings
set -g theme_display_docker_machine yes

# Path
set -gx PATH $HOME/.local/bin $PATH
set -gx PATH /var/lib/snapd/snap/bin $PATH

# vscode

set -Ux ELECTRON_OZONE_PLATFORM_HINT wayland
alias code="code --ozone-platform=wayland --enable-features=UseOzonePlatform,WaylandWindowDecorations"


function wsudo
    sudo /bin/env WAYLAND_DISPLAY="$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"  XDG_RUNTIME_DIR=/user/run/0 $argv
end

function x
    sudo -E $argv
end

if status is-interactive
    # Commands to run in interactive sessions can go here
    set fish_greeting
end

# Source zoxide for the z command
zoxide init fish | source

oh-my-posh init fish --config 'bubbles' | source

alias s="kitten ssh"
