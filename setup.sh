#!/usr/bin/env bash
set -e

# -------------------------
# 0. Ask for Flutter URL
# -------------------------
read -p "Enter Flutter download URL: " FLUTTER_URL
FILENAME=$(basename "$FLUTTER_URL")

# -------------------------
# 1. Base system update
# -------------------------
echo "[*] Updating system..."
sudo pacman -Syu --noconfirm

# -------------------------
# 2. Install yay (AUR helper) if missing
# -------------------------
if ! command -v yay >/dev/null; then
    echo "[*] Installing yay (AUR helper)..."
    git clone https://aur.archlinux.org/yay.git /tmp/yay
    cd /tmp/yay
    makepkg -si --noconfirm
    cd - >/dev/null
fi

# -------------------------
# 3. Dev essentials
# -------------------------
echo "[*] Installing dev essentials..."
sudo pacman -S --noconfirm base-devel git curl wget unzip fzf tmux zsh go

# -------------------------
# 4. Android Studio + SDK (Arch only)
# -------------------------
if grep -qi "arch" /etc/os-release; then
    echo "[*] Installing Android Studio + SDK (AUR)..."
    yay -S --noconfirm android-studio android-sdk android-sdk-platform-tools android-sdk-build-tools

    # Set up Android paths
    if ! grep -q 'ANDROID_HOME' "$HOME/.zshrc"; then
        echo 'export ANDROID_HOME=/opt/android-sdk' >> "$HOME/.zshrc"
        echo 'export PATH=$ANDROID_HOME/platform-tools:$ANDROID_HOME/tools/bin:$PATH' >> "$HOME/.zshrc"
    fi
    export ANDROID_HOME=/opt/android-sdk
    export PATH=$ANDROID_HOME/platform-tools:$ANDROID_HOME/tools/bin:$PATH
else
    echo "[!] Non-Arch detected — skipping Android Studio auto-install. Please install manually."
fi

# -------------------------
# 5. Flutter install
# -------------------------
echo "[*] Downloading Flutter..."
curl -L "$FLUTTER_URL" -o "/tmp/$FILENAME"
echo "[*] Extracting Flutter..."
tar -xf "/tmp/$FILENAME" -C "$HOME"

if ! grep -q 'export PATH="$HOME/flutter/bin:$PATH"' "$HOME/.zshrc"; then
    echo 'export PATH="$HOME/flutter/bin:$PATH"' >> "$HOME/.zshrc"
fi
export PATH="$HOME/flutter/bin:$PATH"

# Accept Android licenses
yes | flutter doctor --android-licenses || true

# -------------------------
# 6. Zsh + Oh My Zsh + Powerlevel10k + Plugins
# -------------------------
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    echo "[*] Installing Oh My Zsh..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi
yay -S --noconfirm zsh-theme-powerlevel10k zsh-autosuggestions zsh-syntax-highlighting
if ! grep -q 'source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh' "$HOME/.zshrc"; then
    echo 'source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh' >> "$HOME/.zshrc"
fi
if ! grep -q 'source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh' "$HOME/.zshrc"; then
    echo 'source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh' >> "$HOME/.zshrc"
fi

# -------------------------
# 7. Neovim with your config
# -------------------------
sudo pacman -S --noconfirm neovim
if [ ! -d "$HOME/.config/nvim" ]; then
    git clone https://github.com/SachinBhankhar/init.lua.git "$HOME/.config/nvim"
fi

# -------------------------
# 8. Tmux + tmux-sessionizer
# -------------------------
cat > ~/.local/bin/tmux-sessionizer <<'EOF'
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
chmod +x ~/.local/bin/tmux-sessionizer
if ! grep -q 'bind-key -r f run-shell "tmux neww ~/.local/bin/tmux-sessionizer"' ~/.tmux.conf 2>/dev/null; then
    echo 'bind-key -r f run-shell "tmux neww ~/.local/bin/tmux-sessionizer"' >> ~/.tmux.conf
fi

# -------------------------
# 9. Flutter Watcher Go build
# -------------------------
if [ ! -d "$HOME/flutter-watcher" ]; then
    git clone https://github.com/SachinBhankhar/flutter-watcher.git "$HOME/flutter-watcher"
fi
cd "$HOME/flutter-watcher"
go build -o "$HOME/.local/bin/reload" main.go
chmod +x "$HOME/.local/bin/reload"
cd - >/dev/null

# -------------------------
# 10. Hyprland + Waybar (Arch only)
# -------------------------
if grep -qi "arch" /etc/os-release; then
    echo "[*] Installing Hyprland + Waybar..."
    sudo pacman -S --noconfirm hyprland waybar chromium
    # (Extra config for Waybar would go here)
fi

echo "[*] Done! Please restart your shell."

