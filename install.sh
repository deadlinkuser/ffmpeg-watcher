#!/bin/bash
set -e

G="github"
U="${G}usercontent.com"
REPO_RAW="https://raw.${U}/deadlinkuser/ffmpeg-watcher/refs/heads/main"


IMAGE="docker.io/linuxserver/ffmpeg:latest"

echo "=================================================================="
echo " FFmpeg Watcher — Podman Automated Installer"
echo "=================================================================="

# 1. Verify Podman is installed
if ! command -v podman >/dev/null 2>&1; then
    echo "Error: Podman is not installed. Install it first with: sudo apt install -y podman"
    exit 1
fi

# 2. Prompt for custom container name
read -rp "Enter container name [ffmpeg-watcher]: " CONTAINER_NAME
CONTAINER_NAME="${CONTAINER_NAME:-ffmpeg-watcher}"

if podman container exists "$CONTAINER_NAME" 2>/dev/null; then
    read -rp "Container '$CONTAINER_NAME' already exists. Replace it? (y/N): " REPLACE
    if [[ "$REPLACE" =~ ^[Yy]$ ]]; then
        podman rm -f "$CONTAINER_NAME" >/dev/null
    else
        echo "Installation cancelled."
        exit 0
    fi
fi

# 3. Prompt for Watch & Output directories (safely inside user's $HOME by default)
DEFAULT_BASE="$HOME/ffmpeg-watcher"
read -rp "Watch folder path [$DEFAULT_BASE/watch]: " WATCH_HOST
WATCH_HOST="${WATCH_HOST:-$DEFAULT_BASE/watch}"

read -rp "Output folder path [$DEFAULT_BASE/output]: " OUTPUT_HOST
OUTPUT_HOST="${OUTPUT_HOST:-$DEFAULT_BASE/output}"

SCRIPT_DIR="$HOME/.local/share/ffmpeg-watcher"
mkdir -p "$WATCH_HOST" "$OUTPUT_HOST" "$SCRIPT_DIR"

# 4. High-core CPU optimization prompt (16+ threads)
TOTAL_THREADS=$(nproc 2>/dev/null || echo 4)
CPU_FLAG=()
if [ "$TOTAL_THREADS" -ge 16 ]; then
    SUGGESTED_CPUS=$((TOTAL_THREADS - 2))
    echo "Detected $TOTAL_THREADS CPU threads (16+ thread optimization available)."
    read -rp "Limit container CPU cores to keep desktop responsive? [$SUGGESTED_CPUS or 'all']: " CPU_CHOICE
    CPU_CHOICE="${CPU_CHOICE:-$SUGGESTED_CPUS}"
    if [[ "$CPU_CHOICE" =~ ^[0-9]+$ ]] && [ "$CPU_CHOICE" -gt 0 ]; then
        CPU_FLAG=("--cpus=$CPU_CHOICE")
    fi
fi

# 5. Download watch.sh and test-watcher.sh from GitHub
echo "Downloading scripts to $SCRIPT_DIR..."
curl -fsSL "$REPO_RAW/watch.sh" -o "$SCRIPT_DIR/watch.sh"
curl -fsSL "$REPO_RAW/test-watcher.sh" -o "$SCRIPT_DIR/test-watcher.sh"
chmod +x "$SCRIPT_DIR/watch.sh" "$SCRIPT_DIR/test-watcher.sh"

# 6. Pull image and launch Podman container
echo "Pulling FFmpeg container image ($IMAGE)..."
podman pull "$IMAGE"

echo "Starting container '$CONTAINER_NAME'..."
podman run -d \
    --name "$CONTAINER_NAME" \
    --restart unless-stopped \
    --userns=keep-id \
    --entrypoint /bin/bash \
    "${CPU_FLAG[@]}" \
    -v "$WATCH_HOST:/watch:Z" \
    -v "$OUTPUT_HOST:/output:Z" \
    -v "$SCRIPT_DIR/watch.sh:/watch.sh:ro,Z" \
    "$IMAGE" /watch.sh >/dev/null

# 7. Optional Desktop Launcher (for XFCE / graphical desktops)
if { [ -n "$DISPLAY" ] || [ -n "$WAYLAND_DISPLAY" ]; } && [ -d "$HOME/Desktop" ]; then
    read -rp "Create clickable 'Test FFmpeg Watcher' icon on Desktop? (Y/n): " MAKE_ICON
    if [[ ! "$MAKE_ICON" =~ ^[Nn]$ ]]; then
        DESKTOP_FILE="$HOME/Desktop/Test-${CONTAINER_NAME}.desktop"
        cat << EOF > "$DESKTOP_FILE"
[Desktop Entry]
Version=1.0
Type=Application
Name=Test FFmpeg Watcher ($CONTAINER_NAME)
Comment=Run automated verification tests for $CONTAINER_NAME
Exec=$SCRIPT_DIR/test-watcher.sh $CONTAINER_NAME
Icon=video-x-generic
Terminal=false
Categories=Utility;AudioVideo;
EOF
        chmod +x "$DESKTOP_FILE"
        echo "Desktop launcher created at: $DESKTOP_FILE"
    fi
fi

echo ""
echo "=================================================================="
echo " Installation Complete!"
echo "=================================================================="
echo " Container Name : $CONTAINER_NAME"
echo " Watch Folder   : $WATCH_HOST"
echo " Output Folder  : $OUTPUT_HOST"
echo " Test Command   : $SCRIPT_DIR/test-watcher.sh $CONTAINER_NAME"
echo " View Logs      : podman logs -f $CONTAINER_NAME"
echo "=================================================================="
