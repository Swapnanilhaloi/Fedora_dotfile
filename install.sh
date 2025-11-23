#!/bin/bash

set -e

# ============================================================================
# Colors and Configuration
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$SCRIPT_DIR"

# ============================================================================
# Helper Functions
# ============================================================================

check_root() {
  if [ "$EUID" -ne 0 ]; then
    echo -e "${YELLOW}⚠${NC}  This script requires root privileges for system setup."
    echo -e "${YELLOW}⚠${NC}  Running with sudo..."
    echo ""
    exec sudo bash "$0" "$@"
  fi
}

check_sudo_user() {
  if [ -z "$SUDO_USER" ]; then
    echo -e "${RED}❌${NC} SUDO_USER not set. Please run with: sudo -E $0"
    exit 1
  fi
  USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
  I3_CONFIG_DIR="$USER_HOME/.config/i3"
  I3_CONFIG_FILE="$I3_CONFIG_DIR/config"
}

install_if_missing() {
  local package=$1
  if ! dnf list installed "$package" &> /dev/null; then
    if ! dnf install -y "$package"; then
      echo -e "${YELLOW}⚠${NC}  Could not install $package (not available or failed), skipping"
    fi
  else
    echo "   ✅ $package already installed"
  fi
}

link_file() {
  local src="$1"
  local dst="$2"
  
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
      echo -e "${GREEN}✓${NC} $dst already linked"
      return
    fi
    echo -e "${YELLOW}⚠${NC}  $dst exists, backing up to ${dst}.backup"
    mv "$dst" "${dst}.backup"
  fi
  
  echo -e "${GREEN}✓${NC} Linking $dst"
  ln -s "$src" "$dst"
}

# ============================================================================
# Hardware Detection
# ============================================================================

detect_graphics() {
  echo "🔍 Detecting graphics chipset..."
  local pci_output=$(lspci | grep -i "vga\|3d\|display" 2>/dev/null || true)
  
  if echo "$pci_output" | grep -qi "intel"; then
    GRAPHICS_CHIPSET="intel"
    echo "   Detected: Intel graphics"
    [ -d /sys/class/backlight/intel_backlight ] && BRIGHTNESS_DEVICE="intel_backlight" || \
    [ -d /sys/class/backlight/acpi_video0 ] && BRIGHTNESS_DEVICE="acpi_video0" || \
    BRIGHTNESS_DEVICE=$(ls /sys/class/backlight/ 2>/dev/null | head -n 1)
    BRIGHTNESS_METHOD="brightnessctl"
  elif echo "$pci_output" | grep -qi "amd\|ati\|radeon"; then
    GRAPHICS_CHIPSET="amd"
    echo "   Detected: AMD graphics"
    [ -d /sys/class/backlight/amdgpu_bl0 ] && BRIGHTNESS_DEVICE="amdgpu_bl0" || \
    [ -d /sys/class/backlight/acpi_video0 ] && BRIGHTNESS_DEVICE="acpi_video0" || \
    BRIGHTNESS_DEVICE=$(ls /sys/class/backlight/ 2>/dev/null | head -n 1)
    BRIGHTNESS_METHOD="brightnessctl"
  elif echo "$pci_output" | grep -qi "nvidia"; then
    GRAPHICS_CHIPSET="nvidia"
    echo "   Detected: NVIDIA graphics"
    if [ -d /sys/class/backlight/acpi_video0 ]; then
      BRIGHTNESS_DEVICE="acpi_video0"
      BRIGHTNESS_METHOD="brightnessctl"
    elif command -v xbacklight &> /dev/null; then
      BRIGHTNESS_METHOD="xbacklight"
    else
      BRIGHTNESS_DEVICE=$(ls /sys/class/backlight/ 2>/dev/null | head -n 1)
      BRIGHTNESS_METHOD="brightnessctl"
    fi
  else
    echo "   ⚠️  Could not detect graphics chipset, using default"
    BRIGHTNESS_DEVICE=$(ls /sys/class/backlight/ 2>/dev/null | head -n 1)
    BRIGHTNESS_METHOD="brightnessctl"
  fi
  
  if [ -n "$BRIGHTNESS_DEVICE" ]; then
    echo "   ✅ Brightness device: $BRIGHTNESS_DEVICE"
  else
    echo "   ⚠️  No backlight device found, brightness control may not work"
  fi
}


# ============================================================================
# Configuration Generation
# ============================================================================

generate_audio_brightness_config() {
  echo "⚙️  Generating brightness and volume control configuration..."
  
  # Generate brightness config
  if [ "$BRIGHTNESS_METHOD" = "brightnessctl" ] && [ -n "$BRIGHTNESS_DEVICE" ]; then
    BRIGHTNESS_CONFIG="# Brightness control (Intel/AMD/NVIDIA via brightnessctl)
bindsym XF86MonBrightnessUp exec --no-startup-id brightnessctl -d $BRIGHTNESS_DEVICE set +10%
bindsym XF86MonBrightnessDown exec --no-startup-id brightnessctl -d $BRIGHTNESS_DEVICE set 10%-"
  elif [ "$BRIGHTNESS_METHOD" = "xbacklight" ]; then
    BRIGHTNESS_CONFIG="# Brightness control (NVIDIA via xbacklight)
bindsym XF86MonBrightnessUp exec --no-startup-id xbacklight -inc 10
bindsym XF86MonBrightnessDown exec --no-startup-id xbacklight -dec 10"
  else
    BRIGHTNESS_CONFIG="# Brightness control (generic)
bindsym XF86MonBrightnessUp exec --no-startup-id brightnessctl set +10%
bindsym XF86MonBrightnessDown exec --no-startup-id brightnessctl set 10%-"
  fi
  
  # Generate volume config (default: pulseaudio/pactl)
  VOLUME_CONFIG="# Volume control (PulseAudio/PipeWire via pactl)
set \$refresh_i3status killall -SIGUSR1 i3status
bindsym XF86AudioRaiseVolume exec --no-startup-id pactl set-sink-volume @DEFAULT_SINK@ +10% && \$refresh_i3status
bindsym XF86AudioLowerVolume exec --no-startup-id pactl set-sink-volume @DEFAULT_SINK@ -10% && \$refresh_i3status
bindsym XF86AudioMute exec --no-startup-id pactl set-sink-mute @DEFAULT_SINK@ toggle && \$refresh_i3status
bindsym XF86AudioMicMute exec --no-startup-id pactl set-source-mute @DEFAULT_SOURCE@ toggle && \$refresh_i3status"
  
  # Save configuration
  sudo -u "$SUDO_USER" mkdir -p "$I3_CONFIG_DIR"
  CONFIG_FILE="$I3_CONFIG_DIR/audio-brightness.conf"
  sudo -u "$SUDO_USER" bash -c "cat > '$CONFIG_FILE'" <<EOF
# Auto-generated brightness and volume control configuration
# Graphics: $GRAPHICS_CHIPSET
# Brightness device: ${BRIGHTNESS_DEVICE:-auto}

$BRIGHTNESS_CONFIG

$VOLUME_CONFIG
EOF
  echo "   ✅ Configuration saved to: $CONFIG_FILE"
}

setup_wallpaper() {
  echo "🖼️ Setting up wallpaper..."
  WALLPAPER_DIR="$USER_HOME/Pictures/wallpapers"
  
  # Find wallpaper in wallpapers directory or root
  WALLPAPER_FILE=""
  if [ -d "$SCRIPT_DIR/wallpapers" ]; then
    WALLPAPER_FILE=$(find "$SCRIPT_DIR/wallpapers" -maxdepth 1 -type f \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.webp" \) | head -n 1)
  fi
  
  if [ -z "$WALLPAPER_FILE" ]; then
    WALLPAPER_FILE=$(find "$SCRIPT_DIR" -maxdepth 1 -type f \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.webp" \) | head -n 1)
  fi
  
  if [ -n "$WALLPAPER_FILE" ] && [ -f "$WALLPAPER_FILE" ]; then
    echo "   Found wallpaper: $(basename "$WALLPAPER_FILE")"
    sudo -u "$SUDO_USER" mkdir -p "$WALLPAPER_DIR"
    sudo -u "$SUDO_USER" cp "$WALLPAPER_FILE" "$WALLPAPER_DIR/"
    WALLPAPER_PATH="$WALLPAPER_DIR/$(basename "$WALLPAPER_FILE")"
    
    # Set wallpaper if X is running
    if [ -n "$DISPLAY" ] || pgrep -x Xorg > /dev/null || pgrep -x X > /dev/null; then
      sudo -u "$SUDO_USER" feh --bg-fill "$WALLPAPER_PATH" 2>/dev/null || \
        echo "   ⚠️  Could not set wallpaper immediately (X may not be running)"
    fi
    
    # Create .fehbg script
    WALLPAPER_SCRIPT="$USER_HOME/.fehbg"
    sudo -u "$SUDO_USER" bash -c "cat > '$WALLPAPER_SCRIPT'" <<EOF
#!/bin/sh
feh --bg-fill "$WALLPAPER_PATH"
EOF
    sudo -u "$SUDO_USER" chmod +x "$WALLPAPER_SCRIPT"
    
    echo "   ✅ Wallpaper set up at: $WALLPAPER_PATH"
  else
    echo "   ⚠️  No wallpaper file found"
  fi
}

# ============================================================================
# Main Installation Script
# ============================================================================

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   Dotfiles Installation Script${NC}"
echo -e "${BLUE}   (Fedora Edition)${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check root and get user info
check_root
check_sudo_user

# ============================================================================
# Step 1: System Setup (Package Installation)
# ============================================================================

echo -e "${GREEN}Step 1/3:${NC} System Setup (Package Installation)"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Update system
echo "🔄 Updating system packages..."
dnf update -y

# Install main packages (install individually for clearer logs)
echo "📦 Installing main packages..."
main_packages=(
  kitty
  thunar
  thunar-volman
  gvfs
  udisks2
  ntfs-3g
  exfatprogs
  dosfstools
  feh
  rofi
)

for pkg in "${main_packages[@]}"; do
  install_if_missing "$pkg"
done

# Install essential utilities
echo "📦 Installing essential utilities..."
install_if_missing brightnessctl
install_if_missing xss-lock
install_if_missing NetworkManager
install_if_missing network-manager-applet
install_if_missing alsa-utils
install_if_missing dex
install_if_missing scrot
install_if_missing xclip
install_if_missing picom
install_if_missing fastfetch

# Install i3 components
echo "🔒 Installing i3 components..."
install_if_missing i3lock
install_if_missing i3status

# Install audio system
echo "🔊 Installing audio system..."
if systemctl --user is-active --quiet pipewire 2>/dev/null || pgrep -x pipewire > /dev/null; then
  echo "   Installing PipeWire..."
  dnf install -y pipewire pipewire-pulseaudio pipewire-alsa wireplumber
elif ! command -v pactl &> /dev/null; then
  echo "   Installing PulseAudio..."
  dnf install -y pulseaudio pulseaudio-utils
else
  echo "   ✅ Audio system already available"
fi

# ============================================================================
# Step 2: Hardware Detection & Configuration
# ============================================================================

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${GREEN}Step 2/3:${NC} Hardware Detection & Configuration"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

detect_graphics

# Generate brightness config
generate_audio_brightness_config

# Setup wallpaper
setup_wallpaper

# ============================================================================
# Step 3: Link Dotfiles
# ============================================================================

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${GREEN}Step 3/3:${NC} Linking Dotfiles"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Switch to user for dotfiles linking
sudo -u "$SUDO_USER" bash <<EOF
set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

DOTFILES_DIR="$DOTFILES_DIR"
USER_HOME="$USER_HOME"

# Create necessary directories
mkdir -p ~/.config
mkdir -p ~/.local/bin
mkdir -p ~/Pictures/wallpapers

# Link config files
echo -e "\${GREEN}Linking configuration files...\${NC}"

# i3 config
if [ -d "\$DOTFILES_DIR/.config/i3" ]; then
  if [ -e ~/.config/i3 ] || [ -L ~/.config/i3 ]; then
    if [ -L ~/.config/i3 ] && [ "\$(readlink ~/.config/i3)" = "\$DOTFILES_DIR/.config/i3" ]; then
      echo -e "\${GREEN}✓\${NC} ~/.config/i3 already linked"
    else
      echo -e "\${YELLOW}⚠\${NC}  ~/.config/i3 exists, backing up"
      mv ~/.config/i3 ~/.config/i3.backup
      ln -s "\$DOTFILES_DIR/.config/i3" ~/.config/i3
    fi
  else
    echo -e "\${GREEN}✓\${NC} Linking ~/.config/i3"
    ln -s "\$DOTFILES_DIR/.config/i3" ~/.config/i3
  fi
fi

# Rofi config
if [ -d "\$DOTFILES_DIR/.config/rofi" ]; then
  if [ -e ~/.config/rofi ] || [ -L ~/.config/rofi ]; then
    if [ -L ~/.config/rofi ] && [ "\$(readlink ~/.config/rofi)" = "\$DOTFILES_DIR/.config/rofi" ]; then
      echo -e "\${GREEN}✓\${NC} ~/.config/rofi already linked"
    else
      echo -e "\${YELLOW}⚠\${NC}  ~/.config/rofi exists, backing up"
      mv ~/.config/rofi ~/.config/rofi.backup 2>/dev/null || true
      ln -s "\$DOTFILES_DIR/.config/rofi" ~/.config/rofi
    fi
  else
    echo -e "\${GREEN}✓\${NC} Linking ~/.config/rofi"
    ln -s "\$DOTFILES_DIR/.config/rofi" ~/.config/rofi
  fi
fi

# i3blocks config
if [ -d "\$DOTFILES_DIR/.config/i3blocks" ]; then
  if [ -e ~/.config/i3blocks ] || [ -L ~/.config/i3blocks ]; then
    if [ -L ~/.config/i3blocks ] && [ "\$(readlink ~/.config/i3blocks)" = "\$DOTFILES_DIR/.config/i3blocks" ]; then
      echo -e "\${GREEN}✓\${NC} ~/.config/i3blocks already linked"
    else
      echo -e "\${YELLOW}⚠\${NC}  ~/.config/i3blocks exists, backing up"
      mv ~/.config/i3blocks ~/.config/i3blocks.backup 2>/dev/null || true
      ln -s "\$DOTFILES_DIR/.config/i3blocks" ~/.config/i3blocks
    fi
  else
    echo -e "\${GREEN}✓\${NC} Linking ~/.config/i3blocks"
    ln -s "\$DOTFILES_DIR/.config/i3blocks" ~/.config/i3blocks
  fi
fi

# Dunst config
if [ -d "\$DOTFILES_DIR/.config/dunst" ]; then
  if [ -e ~/.config/dunst ] || [ -L ~/.config/dunst ]; then
    if [ -L ~/.config/dunst ] && [ "\$(readlink ~/.config/dunst)" = "\$DOTFILES_DIR/.config/dunst" ]; then
      echo -e "\${GREEN}✓\${NC} ~/.config/dunst already linked"
    else
      echo -e "\${YELLOW}⚠\${NC}  ~/.config/dunst exists, backing up"
      mv ~/.config/dunst ~/.config/dunst.backup 2>/dev/null || true
      ln -s "\$DOTFILES_DIR/.config/dunst" ~/.config/dunst
    fi
  else
    echo -e "\${GREEN}✓\${NC} Linking ~/.config/dunst"
    ln -s "\$DOTFILES_DIR/.config/dunst" ~/.config/dunst
  fi
fi

# Picom config
if [ -d "\$DOTFILES_DIR/.config/picom" ]; then
  if [ -e ~/.config/picom ] || [ -L ~/.config/picom ]; then
    if [ -L ~/.config/picom ] && [ "\$(readlink ~/.config/picom)" = "\$DOTFILES_DIR/.config/picom" ]; then
      echo -e "\${GREEN}✓\${NC} ~/.config/picom already linked"
    else
      echo -e "\${YELLOW}⚠\${NC}  ~/.config/picom exists, backing up"
      mv ~/.config/picom ~/.config/picom.backup 2>/dev/null || true
      ln -s "\$DOTFILES_DIR/.config/picom" ~/.config/picom
    fi
  else
    echo -e "\${GREEN}✓\${NC} Linking ~/.config/picom"
    ln -s "\$DOTFILES_DIR/.config/picom" ~/.config/picom
  fi
fi

# Kitty config
if [ -d "\$DOTFILES_DIR/.config/kitty" ]; then
  if [ -e ~/.config/kitty ] || [ -L ~/.config/kitty ]; then
    if [ -L ~/.config/kitty ] && [ "\$(readlink ~/.config/kitty)" = "\$DOTFILES_DIR/.config/kitty" ]; then
      echo -e "\${GREEN}✓\${NC} ~/.config/kitty already linked"
    else
      echo -e "\${YELLOW}⚠\${NC}  ~/.config/kitty exists, backing up"
      mv ~/.config/kitty ~/.config/kitty.backup 2>/dev/null || true
      ln -s "\$DOTFILES_DIR/.config/kitty" ~/.config/kitty
    fi
  else
    echo -e "\${GREEN}✓\${NC} Linking ~/.config/kitty"
    ln -s "\$DOTFILES_DIR/.config/kitty" ~/.config/kitty
  fi
fi

# Zsh configs
if [ -f "\$DOTFILES_DIR/.zshrc" ]; then
  if [ -L ~/.zshrc ] && [ "\$(readlink ~/.zshrc)" = "\$DOTFILES_DIR/.zshrc" ]; then
    echo -e "\${GREEN}✓\${NC} ~/.zshrc already linked"
  else
    [ -e ~/.zshrc ] && mv ~/.zshrc ~/.zshrc.backup
    echo -e "\${GREEN}✓\${NC} Linking ~/.zshrc"
    ln -s "\$DOTFILES_DIR/.zshrc" ~/.zshrc
  fi
fi

if [ -d "\$DOTFILES_DIR/.zsh" ]; then
  if [ -L ~/.zsh ] && [ "\$(readlink ~/.zsh)" = "\$DOTFILES_DIR/.zsh" ]; then
    echo -e "\${GREEN}✓\${NC} ~/.zsh already linked"
  else
    [ -e ~/.zsh ] && mv ~/.zsh ~/.zsh.backup
    echo -e "\${GREEN}✓\${NC} Linking ~/.zsh"
    ln -s "\$DOTFILES_DIR/.zsh" ~/.zsh
  fi
fi

# Wgetrc
if [ -f "\$DOTFILES_DIR/.wgetrc" ]; then
  if [ -L ~/.wgetrc ] && [ "\$(readlink ~/.wgetrc)" = "\$DOTFILES_DIR/.wgetrc" ]; then
    echo -e "\${GREEN}✓\${NC} ~/.wgetrc already linked"
  else
    [ -e ~/.wgetrc ] && mv ~/.wgetrc ~/.wgetrc.backup
    echo -e "\${GREEN}✓\${NC} Linking ~/.wgetrc"
    ln -s "\$DOTFILES_DIR/.wgetrc" ~/.wgetrc
  fi
fi

# Bin scripts
if [ -d "\$DOTFILES_DIR/bin" ]; then
  echo -e "\${GREEN}Linking bin scripts...\${NC}"
  for script in "\$DOTFILES_DIR/bin"/*; do
    if [ -f "\$script" ]; then
      script_name=\$(basename "\$script")
      if [ -L ~/.local/bin/"\$script_name" ] && [ "\$(readlink ~/.local/bin/\$script_name)" = "\$script" ]; then
        echo -e "\${GREEN}✓\${NC} ~/.local/bin/\$script_name already linked"
      else
        [ -e ~/.local/bin/"\$script_name" ] && mv ~/.local/bin/"\$script_name" ~/.local/bin/"\$script_name".backup
        echo -e "\${GREEN}✓\${NC} Linking ~/.local/bin/\$script_name"
        ln -s "\$script" ~/.local/bin/"\$script_name"
      fi
    fi
  done
fi

# Link shell configs
echo -e "\${GREEN}Linking shell configuration...\${NC}"

# Aliases
if [ -f "\$DOTFILES_DIR/.aliases" ]; then
  if [ -L ~/.aliases ] && [ "\$(readlink ~/.aliases)" = "\$DOTFILES_DIR/.aliases" ]; then
    echo -e "\${GREEN}✓\${NC} ~/.aliases already linked"
  else
    [ -e ~/.aliases ] && mv ~/.aliases ~/.aliases.backup
    echo -e "\${GREEN}✓\${NC} Linking ~/.aliases"
    ln -s "\$DOTFILES_DIR/.aliases" ~/.aliases
  fi
fi

# Bashrc
if [ -f "\$DOTFILES_DIR/.bashrc" ]; then
  if [ -L ~/.bashrc ] && [ "\$(readlink ~/.bashrc)" = "\$DOTFILES_DIR/.bashrc" ]; then
    echo -e "\${GREEN}✓\${NC} ~/.bashrc already linked"
  else
    [ -e ~/.bashrc ] && mv ~/.bashrc ~/.bashrc.backup
    echo -e "\${GREEN}✓\${NC} Linking ~/.bashrc"
    ln -s "\$DOTFILES_DIR/.bashrc" ~/.bashrc
  fi
  # Source aliases in bashrc if not already there
  if ! grep -q "source ~/.aliases" ~/.bashrc 2>/dev/null; then
    echo -e "\n# Source aliases\nsource ~/.aliases" >> ~/.bashrc
  fi
fi

# Xresources
if [ -f "\$DOTFILES_DIR/.Xresources" ]; then
  if [ -L ~/.Xresources ] && [ "\$(readlink ~/.Xresources)" = "\$DOTFILES_DIR/.Xresources" ]; then
    echo -e "\${GREEN}✓\${NC} ~/.Xresources already linked"
  else
    [ -e ~/.Xresources ] && mv ~/.Xresources ~/.Xresources.backup
    echo -e "\${GREEN}✓\${NC} Linking ~/.Xresources"
    ln -s "\$DOTFILES_DIR/.Xresources" ~/.Xresources
  fi
fi

# Copy wallpapers
if [ -d "\$DOTFILES_DIR/wallpapers" ]; then
  echo -e "\${GREEN}Copying wallpapers...\${NC}"
  cp -r "\$DOTFILES_DIR/wallpapers/"* ~/Pictures/wallpapers/ 2>/dev/null || true
fi

# Install fonts
if [ -d "\$DOTFILES_DIR/FiraCode" ]; then
  echo -e "\${GREEN}Installing fonts...\${NC}"
  mkdir -p ~/.local/share/fonts
  cp -r "\$DOTFILES_DIR/FiraCode/"* ~/.local/share/fonts/ 2>/dev/null || true
  fc-cache -fv ~/.local/share/fonts/ 2>/dev/null || true
  echo -e "\${GREEN}✓\${NC} Fonts installed"
fi

# Add audio-brightness.conf include to i3 config if not present
if [ -f ~/.config/i3/config ]; then
  if ! grep -q "include audio-brightness.conf" ~/.config/i3/config; then
    if grep -q "exec --no-startup-id ~/.fehbg" ~/.config/i3/config; then
      sed -i '/exec --no-startup-id ~\/\.fehbg/a include audio-brightness.conf' ~/.config/i3/config
    else
      echo -e '\n# Include auto-generated audio and brightness control\ninclude audio-brightness.conf' >> ~/.config/i3/config
    fi
    echo -e "\${GREEN}✓\${NC} Added 'include audio-brightness.conf' to i3 config"
  fi
fi

EOF

# ============================================================================
# Summary
# ============================================================================

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${GREEN}✅${NC} Installation Complete!"
echo ""
echo -e "${YELLOW}📊 Detected Hardware:${NC}"
echo -e "   - Graphics: $GRAPHICS_CHIPSET"
echo -e "   - Brightness device: ${BRIGHTNESS_DEVICE:-auto}"
echo ""
echo -e "${YELLOW}📁 Configuration Files:${NC}"
echo -e "   - i3: ~/.config/i3/config"
echo -e "   - Kitty: ~/.config/kitty/kitty.conf"
echo -e "   - Rofi: ~/.config/rofi/"
echo -e "   - Dunst: ~/.config/dunst/"
echo -e "   - Picom: ~/.config/picom/"
echo -e "   - Audio/Brightness: ~/.config/i3/audio-brightness.conf"
echo ""
echo -e "${YELLOW}📝 Next steps:${NC}"
echo -e "   1. Restart i3 (Mod+Shift+R) or reboot"
echo -e "   2. Run 'source ~/.bashrc' or restart terminal"
echo -e "   3. Enjoy your new setup! 🎉"
echo ""
echo -e "${BLUE}========================================${NC}"

