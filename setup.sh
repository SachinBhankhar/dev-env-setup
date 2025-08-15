#!/usr/bin/env bash
set -e

echo "[*] Starting Post-Install Dev Environment Setup..."

# -------------------------
# 0. Ask for Flutter URL
# -------------------------
read -p "Enter Flutter download URL: " FLUTTER_URL
FILENAME=$(basename "$FLUTTER_URL")
FLUTTER_VERSION=$(echo "$FILENAME" | grep -oP '\d+\.\d+\.\d+')
echo "[*] Detected Flutter version: $FLUTTER_VERSION"

# -------------------------
# 1. System update
# -------------------------
echo "[*] Updating system..."
sudo pacman -Syu --noconfirm

# -------------------------
# 2. Install essentials
# -------------------------
echo "[*] Installing base dev tools..."
sudo pacman -S --noconfirm \
    git base-devel wget curl unzip zip fzf \
    zsh tmux neovim go \
    htop ripgrep fd

# -------------------------
# 3. Install Android Studio + SDK
# -------------------------
echo "[*] Installing Android Studio + SDK..."
sudo pacman -S --noconfirm android-studio android-sdk android-sdk-platform-tools android-sdk-build-tools

# -------------------------
# 4. Install Flutter from URL
# -------------------------
echo "[*] Downloading Flutter $FLUTTER_VERSION..."
curl -L "$FLUTTER_URL" -o "/tmp/$FILENAME"

echo "[*] Extracting Flutter..."
tar -xf "/tmp/$FILENAME" -C "$HOME"

# Ensure path is set in .zshrc and current shell
if ! grep -q 'export PATH="$HOME/flutter/bin:$PATH"' "$HOME/.zshrc"; then
    echo 'export PATH="$HOME/flutter/bin:$PATH"' >> "$HOME/.zshrc"
fi
export PATH="$HOME/flutter/bin:$PATH"

# Accept Android licenses now that Flutter is installed
yes | flutter doctor --android-licenses || true

# -------------------------
# 5. Neovim Config
# -------------------------
echo "[*] Setting up Neovim config..."
NVIM_CONFIG_DIR="$HOME/.config/nvim"
if [[ -d "$NVIM_CONFIG_DIR" ]]; then
    mv "$NVIM_CONFIG_DIR" "$NVIM_CONFIG_DIR.bak"
fi
git clone https://github.com/SachinBhankhar/init.lua.git "$NVIM_CONFIG_DIR"

# -------------------------
# 6. Tmux + Sessionizer
# -------------------------
echo "[*] Setting up tmux config and tmux-sessionizer..."
cat > "$HOME/.tmux.conf" <<'EOF'
set -g mouse on
bind-key -r f run-shell "~/.local/bin/tmux-sessionizer"
EOF

mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/tmux-sessionizer" <<'EOF'
#!/usr/bin/env bash
if [[ $# -eq 1 ]]; then
    selected=$1
else
    selected=$(find ~/work/builds ~/projects ~/ ~/work ~/personal ~/personal/yt -mindepth 1 -maxdepth 1 -type d | fzf)
fi
if [[ -z $selected ]]; then
    exit 0
fi
selected_name=$(basename "$selected" | tr . _)
tmux_running=$(pgrep tmux)
if [[ -z $TMUX ]] && [[ -z $tmux_running ]]; then
    tmux new-session -s $selected_name -c $selected
    exit 0
fi
if ! tmux has-session -t=$selected_name 2> /dev/null; then
    tmux new-session -ds $selected_name -c $selected
fi
tmux switch-client -t $selected_name
EOF
chmod +x "$HOME/.local/bin/tmux-sessionizer"

# -------------------------
# 7. Zsh + Oh My Zsh + Plugins
# -------------------------
echo "[*] Installing Oh My Zsh..."
if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi
echo "[*] Installing Powerlevel10k..."
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
echo "[*] Installing zsh plugins..."
git clone https://github.com/zsh-users/zsh-autosuggestions "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions"
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting"

sed -i 's|ZSH_THEME=".*"|ZSH_THEME="powerlevel10k/powerlevel10k"|' "$HOME/.zshrc"
sed -i 's|plugins=(.*)|plugins=(git zsh-autosuggestions zsh-syntax-highlighting)|' "$HOME/.zshrc"
grep -qxF 'export PATH="$HOME/.local/bin:$PATH"' "$HOME/.zshrc" || echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.zshrc"

# -------------------------
# 8. Flutter Watcher Build
# -------------------------
echo "[*] Building Flutter Watcher..."
TMP_DIR=$(mktemp -d)
git clone https://github.com/SachinBhankhar/flutter-watcher.git "$TMP_DIR/flutter-watcher"
cd "$TMP_DIR/flutter-watcher"
go build -o "$HOME/.local/bin/reload" main.go
chmod +x "$HOME/.local/bin/reload"
cd - >/dev/null
rm -rf "$TMP_DIR"

# -------------------------
# 9. Hyprland + Waybar
# -------------------------
echo "[*] Installing Hyprland + Waybar..."
sudo pacman -S --noconfirm hyprland waybar rofi wl-clipboard

mkdir -p "$HOME/.config/waybar"
cat > "$HOME/.config/waybar/config.jsonc" <<'EOF'
{
  "layer": "top",
  "position": "top",
  "modules-left": ["workspaces"],
  "modules-center": ["cpu", "memory", "network"],
  "modules-right": ["clock"],
  "cpu": { "format": "{usage}%" },
  "memory": { "format": "{}%" },
  "network": { "format-wifi": "{essid} ({signalStrength}%)", "format-ethernet": "{ifname}: {ipaddr}" }
}
EOF

cat > "$HOME/.config/waybar/style.css" <<'EOF'
* {
    border-radius: 8px;
    font-family: "JetBrainsMono Nerd Font", monospace;
    font-size: 12px;
}
EOF

# -------------------------
# 10. Chrome (AUR)
# -------------------------
if ! command -v yay >/dev/null; then
    echo "[*] Installing yay (AUR helper)..."
    git clone https://aur.archlinux.org/yay.git /tmp/yay
    cd /tmp/yay
    makepkg -si --noconfirm
    cd - >/dev/null
fi

echo "[*] Installing Google Chrome..."
yay -S --noconfirm google-chrome

mkdir -p "$HOME/.local/share/applications"
cat > "$HOME/.local/share/applications/google-chrome.desktop" <<'EOF'
[Desktop Entry]
Name=Google Chrome
Exec=google-chrome-stable
Icon=google-chrome
Type=Application
Categories=Network;WebBrowser;
EOF

echo "[✔] Setup complete! Please reboot or log out and back in."

