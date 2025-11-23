# Fedora Dotfiles

Personal dotfiles for Fedora Linux with i3 window manager.

## What's Included

Note: The installer previously referenced the `exfat-utils` package which was
removed/renamed in newer Fedora releases. The script now installs `exfatprogs`.
# Fedora Dotfiles

Personal dotfiles for Fedora Linux with i3 window manager.

## What's Included

- **i3** - Tiling window manager configuration
- **Kitty** - Terminal emulator
- **Rofi** - Application launcher
- **Dunst** - Notification daemon
- **Picom** - Compositor for transparency and effects
- **Feh** - Lightweight image viewer and wallpaper setter
- **FiraCode Nerd Font** - Programming font with ligatures
- **Shell configs** - Bash aliases and configuration

## Installation

### Complete Installation

The `install.sh` script does everything in one go:

```bash
git clone <your-repo-url> ~/dotfiles
cd ~/dotfiles
chmod +x install.sh
sudo ./install.sh
```

This will:
- Install all required packages (kitty, rofi, i3, dunst, picom, feh, etc.)
- Detect your hardware (graphics/audio)
- Configure brightness and volume controls automatically
- Set up wallpapers
- Install fonts
- Link all dotfiles to your home directory

**Note:** The script will automatically request sudo privileges if needed.

## Structure

```
.
├── install.sh              # Unified installation script (does everything)
├── .config/                # Application configs
│   ├── i3/                 # i3 window manager
│   ├── kitty/              # Terminal
│   ├── rofi/               # App launcher
│   ├── dunst/              # Notifications
│   ├── picom/              # Compositor
│   └── i3blocks/           # Status bar blocks
├── .zsh/                   # Zsh configuration
├── .zshrc                  # Zsh config file
├── FiraCode/               # Fonts (if included)
├── wallpapers/             # Wallpapers
└── bin/                    # Custom scripts
```

## Features

- **Hardware Detection** - Automatically detects graphics and audio
- **Auto Configuration** - Sets up brightness and volume controls
- **Wallpaper Management** - Automatic wallpaper setup with feh
- **Font Installation** - Installs FiraCode Nerd Font (if included)

## Key Bindings

- `Mod+Return` - Open terminal (Kitty)
- `Mod+d` - Application launcher (Rofi)
- `Mod+h/j/k/l` - Focus windows (vim-style)
- `Mod+Shift+h/j/k/l` - Move windows
- `Mod+1-10` - Switch workspaces
- `Mod+Shift+c` - Reload i3 config
- `Mod+Shift+r` - Restart i3

## Requirements

- Fedora Linux
- i3 window manager
- Kitty terminal
- Rofi
- Dunst
- Picom
- Feh

## Packages Installed

The installation script will install the following packages via `dnf`:

- **Main packages**: kitty, feh, rofi, thunar, thunar-volman, gvfs, udisks2, ntfs-3g, exfat-utils, dosfstools
- **Utilities**: brightnessctl, xss-lock, NetworkManager, network-manager-applet, alsa-utils, dex, scrot, xclip, picom, fastfetch
- **i3 components**: i3lock, i3status
- **Audio**: pipewire/pulseaudio (depending on what's detected)

## Differences from Arch Version

- Uses `dnf` instead of `pacman` for package management
- Package names may differ (e.g., `exfat-utils` instead of `exfatprogs`)
- No AUR helper (yay) installation
- NetworkManager package name is capitalized

## License

MIT

