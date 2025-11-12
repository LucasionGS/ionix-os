# GTKGreet Custom Theme

This directory contains custom styling for GTKGreet login manager to match the Ion theme used throughout the system.

## Usage

The style is automatically applied to GTKGreet through the `-s` flag in the Hyprland greeter configuration.

## Customization

To customize the GTKGreet appearance:

1. Edit the `style.css` file in this directory
2. Key colors used:
   - Background: #1b1e2f
   - Foreground: #f1f1f1
   - Accent: #4e27b1
   - Secondary: #c46e12
   - Border radius: 7px

## Testing Changes

To test your changes without restarting:

```bash
# As root
systemctl restart greetd
```

## Troubleshooting

If your custom theme is not applied:
1. Check that the style path in `/etc/greetd/hyprland-greet.conf` is correct
2. Ensure the CSS file has the correct permissions
3. Verify the syntax of your CSS file
