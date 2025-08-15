#!/usr/bin/env bash
set -euo pipefail

log_success() { echo -e "\e[32m[✔] $1\e[0m"; }
log_error() { echo -e "\e[31m[✖] $1\e[0m" >&2; }
log_info() { echo -e "\e[34m[*] $1\e[0m"; }

die() { log_error "$1"; exit 1; }
trap 'die "An unexpected error occurred at line $LINENO."' ERR

# -------------------------
# 0. Ask for Flutter URL
# -------------------------
read -rp "Enter Flutter download URL: " FLUTTER_URL
FILENAME=$(basename "$FLUTTER_URL")
[ -n "$FILENAME" ] || die "You must enter a valid URL."

# -------------------------
# 1. Base system update
# -------------------------
log_info "Updating system..."
sudo pacman -Syu --noconfirm || die "System update failed"
log_success "System updated."

# -------------------------
# 2. Install yay (AUR helper) if missing
# -------------------------
if ! command -v yay >/dev/null 2>&1; then
    log_info "Installing yay (AUR helper)..."
    git clone https://aur.archlinux.org/yay.git /tmp/yay || die "Failed to clone yay repo"
    pushd /tmp/yay >/dev/null || die "Cannot enter yay dir"
    makepkg -si --noconfirm || die "yay build failed"
    popd >/dev/null
    rm -rf /tmp/yay
    log_success "yay installed."
else
    log_success "yay is already installed."
fi

# -------------------------
# 3. Dev essentials
# -------------------------
log_info "Installing dev essentials..."
sudo pacman -S --needed --noconfirm base-devel git curl wget unzip fzf tmux zsh go || die "Essential tools install failed"
log_success "Dev essentials installed."

# -------------------------
# 4. Android Studio + SDK (Arch only)
# -------------------------
if grep -qi "arch" /etc/os-release; then
    log_info "Installing Android Studio + SDK (AUR)..."
    yay -S --needed --noconfirm android-studio android-sdk android-sdk-platform-tools android-sdk-build-tools || die "Android Studio or SDK install failed"

    # Install compatibility libraries for Android Studio
    log_info "Installing compatibility libraries for Android Studio..."
    sudo pacman -S --needed --noconfirm ncurses5-compat-libs lib32-libglvnd libglvnd gtk3 || log_error "Some compatibility libraries might be missing: Check them manually if Android Studio fails to run."

    # Set up Android paths
    ANDROID_ENV='export ANDROID_HOME=/opt/android-sdk
export PATH=$ANDROID_HOME/platform-tools:$ANDROID_HOME/tools/bin:$PATH'
    if ! grep -q 'ANDROID_HOME' "$HOME/.zshrc"; then
        echo "$ANDROID_ENV" >> "$HOME/.zshrc"
        log_success "Android paths added to .zshrc"
    fi
    export ANDROID_HOME=/opt/android-sdk
    export PATH=$ANDROID_HOME/platform-tools:$ANDROID_HOME/tools/bin:$PATH

    # Test Android Studio
    log_info "Testing Android Studio launch for missing libraries..."
    STUDIO_BIN="/opt/android-studio/bin/studio.sh"
    if ! [ -x "$STUDIO_BIN" ]; then
        STUDIO_BIN="$(command -v android-studio || true)"
    fi
    if [ -x "$STUDIO_BIN" ]; then
        missing_libs=$(ldd "$STUDIO_BIN" 2>/dev/null | grep "not found" || true)
        if [ -n "$missing_libs" ]; then
            log_error "Android Studio missing libs:"
            echo "$missing_libs"
            die "Please install the missing libraries above (or see output above)."
        else
            log_success "Android Studio's shared library dependencies satisfied."
        fi
    else
        log_error "Could not find Android Studio binary to check libraries."
    fi
else
    log_info "Non-Arch detected — skipping Android Studio auto-install. Please install manually."
fi

# -------------------------
# 5. Flutter install
# -------------------------
log_info "Downloading Flutter..."
curl -L "$FLUTTER_URL" -o "/tmp/$FILENAME" || die "Failed to download Flutter SDK."

log_info "Extracting Flutter..."
tar -xf "/tmp/$FILENAME" -C "$HOME" || die "Failed to extract Flutter SDK."

if ! grep -q 'export PATH="$HOME/flutter/bin:$PATH"' "$HOME/.zshrc"; then
    echo 'export PATH="$HOME/flutter/bin:$PATH"' >> "$HOME/.zshrc"
    log_success "Flutter PATH added to .zshrc"
fi
export PATH="$HOME/flutter/bin:$PATH"

log_info "Accepting Android licenses (may require interaction)..."
yes | flutter doctor --android-licenses || log_error "Flutter license acceptance failed."
log_success "Flutter (SDK) setup complete."

# -------------------------
# 6. Zsh + Oh My Zsh + Powerlevel10k + Plugins
# -------------------------
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    log_info "Installing Oh My Zsh..."
    RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended || log_error "Oh My Zsh install failed."
    log_success "Oh My Zsh installed."
else
    log_success "Oh My Zsh already present."
fi

yay -S --needed --noconfirm zsh-theme-powerlevel10k zsh-autosuggestions zsh-syntax-highlighting || log_error "Some Zsh plugins/themes failed to install."

# Append plugins to .zshrc if missing
[ ! -f "$HOME/.zshrc" ] && touch "$HOME/.zshrc"
grep -q 'zsh-autosuggestions' "$HOME/.zshrc" || echo 'source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh' >> "$HOME/.zshrc"
grep -q 'zsh-syntax-highlighting' "$HOME/.zshrc" || echo 'source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh' >> "$HOME/.zshrc"

log_success "Zsh plugins and theme configured."

# -------------------------
# 7. Neovim with your config
# -------------------------
log_info "Installing Neovim..."
sudo pacman -S --needed --noconfirm neovim || log_error "Neovim install failed."
if [ ! -d "$HOME/.config/nvim" ]; then
    git clone https://github.com/SachinBhankhar/init.lua.git "$HOME/.config/nvim" || log_error "Failed to clone Neovim config."
    log_success "Neovim config cloned."
else
    log_success "Neovim config already exists."
fi

# -------------------------
# 8. Tmux + tmux-sessionizer
# -------------------------
mkdir -p ~/.local/bin

cat > ~/.local/bin/tmux-sessionizer <<'EOF'
#!/usr/bin/env bash

if [[ $# -eq 1 ]]; then
    selected=$1
else
    selected=$(find ~/work/builds ~/projects ~/ ~/work ~/personal ~/personal/yt -mindepth 1 -maxdepth 1 -type d 2>/dev/null | fzf)
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

touch ~/.tmux.conf
grep -q 'tmux-sessionizer' ~/.tmux.conf || echo 'bind-key -r f run-shell "tmux neww ~/.local/bin/tmux-sessionizer"' >> ~/.tmux.conf

log_success "Tmux and sessionizer ready."

# -------------------------
# 9. Flutter Watcher Go build
# -------------------------
if [ ! -d "$HOME/flutter-watcher" ]; then
    git clone https://github.com/SachinBhankhar/flutter-watcher.git "$HOME/flutter-watcher" || log_error "Flutter-watcher clone failed."
    log_success "Flutter-watcher cloned."
fi
pushd "$HOME/flutter-watcher" >/dev/null || die "Cannot enter flutter-watcher dir"
go build -o "$HOME/.local/bin/reload" main.go || log_error "Go build failed for flutter-watcher."
chmod +x "$HOME/.local/bin/reload"
popd >/dev/null

log_success "Flutter watcher built and installed."

# -------------------------
# 10. Hyprland + Waybar (Arch only)
# -------------------------
if grep -qi "arch" /etc/os-release; then
    log_info "Installing Hyprland + Waybar..."
    sudo pacman -S --needed --noconfirm hyprland waybar chromium || log_error "Hyprland/Waybar install failed."
    log_success "Hyprland and Waybar installed."
fi

log_success "Post-install setup complete! Please restart your shell or run 'exec zsh'."
