#!/bin/bash
set -e

GITHUB_USER="deadlinkuser"
G="github"
U="${G}usercontent.com"
REPO_RAW="https://raw.${U}/${GITHUB_USER}/ffmpeg-watcher/refs/heads/main"
IMAGE="docker.io/linuxserver/ffmpeg:latest"

echo "=================================================================="
echo " FFmpeg Watcher — Automated Setup Wizard"
echo "=================================================================="
echo " This installer will set up a background video converter that"
echo " automatically converts videos dropped into your Watch folder into"
echo " clean, space-saving .mkv files inside your Output folder."
echo ""
echo " Tip: Press [Enter] at any prompt to accept the suggested default."
echo "      Press [Ctrl+C] at any time to cancel safely."
echo "=================================================================="
echo ""

# 1. Verify Podman is installed
if ! command -v podman >/dev/null 2>&1; then
    echo "ERROR: Podman is not installed on this system."
    echo "Please install Podman first by running:"
    echo "  sudo apt update && sudo apt install -y podman"
    exit 1
fi

# 2. Prompt for custom container name
echo "STEP 1 of 4: Container Name"
echo "Choose a name for this background worker in Podman."
read -rp "Container name [Press Enter for: ffmpeg-watcher]: " CONTAINER_NAME
CONTAINER_NAME="${CONTAINER_NAME:-ffmpeg-watcher}"

if podman container exists "$CONTAINER_NAME" 2>/dev/null; then
    echo ""
    read -rp "A container named '$CONTAINER_NAME' already exists. Replace it? (y/N): " REPLACE
    if [[ "$REPLACE" =~ ^[Yy]$ ]]; then
        podman rm -f "$CONTAINER_NAME" >/dev/null
    else
        echo "Installation cancelled. Existing container was not modified."
        exit 0
    fi
fi
echo ""

# 3. Prompt for Watch & Output directories (safely inside user's $HOME)
DEFAULT_BASE="$HOME/ffmpeg-watcher"
echo "STEP 2 of 4: Folder Locations"
echo "Where should you drop videos to be converted (Watch folder),"
echo "and where should finished .mkv videos be saved (Output folder)?"
read -rp "Watch folder  [Press Enter for: $DEFAULT_BASE/watch]: " WATCH_HOST
WATCH_HOST="${WATCH_HOST:-$DEFAULT_BASE/watch}"

read -rp "Output folder [Press Enter for: $DEFAULT_BASE/output]: " OUTPUT_HOST
OUTPUT_HOST="${OUTPUT_HOST:-$DEFAULT_BASE/output}"

SCRIPT_DIR="$HOME/.local/share/ffmpeg-watcher"
mkdir -p "$WATCH_HOST" "$OUTPUT_HOST" "$SCRIPT_DIR"
echo ""

# 4. High-core CPU optimization prompt (16+ threads)
TOTAL_THREADS=$(nproc 2>/dev/null || echo 4)
CPU_FLAG=()
echo "STEP 3 of 4: CPU Performance"
if [ "$TOTAL_THREADS" -ge 16 ]; then
    SUGGESTED_CPUS=$((TOTAL_THREADS - 2))
    echo "Your computer has $TOTAL_THREADS CPU threads. Limiting the converter to"
    echo "$SUGGESTED_CPUS threads keeps your desktop smooth while videos encode."
    read -rp "Max CPU threads to use [Press Enter for: $SUGGESTED_CPUS, or type 'all']: " CPU_CHOICE
    CPU_CHOICE="${CPU_CHOICE:-$SUGGESTED_CPUS}"
    if [[ "$CPU_CHOICE" =~ ^[0-9]+$ ]] && [ "$CPU_CHOICE" -gt 0 ]; then
        CPU_FLAG=("--cpus=$CPU_CHOICE")
    fi
else
    echo "Detected $TOTAL_THREADS CPU threads (no manual limit needed)."
fi
echo ""

# 5. Download watch.sh and test-watcher.sh from GitHub
echo "STEP 4 of 4: Downloading & Starting Worker..."
echo "Downloading watcher and test scripts to $SCRIPT_DIR..."
curl -fsSL "$REPO_RAW/watch.sh" -o "$SCRIPT_DIR/watch.sh"
curl -fsSL "$REPO_RAW/test-watcher.sh" -o "$SCRIPT_DIR/test-watcher.sh"
chmod +x "$SCRIPT_DIR/watch.sh" "$SCRIPT_DIR/test-watcher.sh"

# 6. Pull image and launch Podman container
echo "Downloading FFmpeg container image ($IMAGE)..."
echo "(This first download may take 1-2 minutes depending on internet speed)"
podman pull "$IMAGE"

echo "Starting background container '$CONTAINER_NAME'..."
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
DESKTOP_CREATED=0
if { [ -n "$DISPLAY" ] || [ -n "$WAYLAND_DISPLAY" ]; } && [ -d "$HOME/Desktop" ]; then
    echo ""
    read -rp "Create a clickable 'Test FFmpeg Watcher' icon on your Desktop? [Press Enter for Yes, or 'n' for No]: " MAKE_ICON
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
        DESKTOP_CREATED=1
    fi
fi

echo ""
echo "=================================================================="
echo " Setup Complete! Your video converter is running in the background."
echo "=================================================================="
echo " How to use it:"
echo "  1. Drop any video file (or season folder) into:"
echo "     $WATCH_HOST"
echo "  2. Finished .mkv videos will automatically appear in:"
echo "     $OUTPUT_HOST"
echo "  3. Note: Original files are removed from Watch once verified."
echo "     Any broken/unreadable files are moved to: $WATCH_HOST/_failed"
echo ""
echo " How to test that everything works:"
if [ "$DESKTOP_CREATED" -eq 1 ]; then
    echo "  -> Double-click 'Test FFmpeg Watcher ($CONTAINER_NAME)' on your Desktop"
    echo "     (or run: $SCRIPT_DIR/test-watcher.sh $CONTAINER_NAME)"
else
    echo "  -> Run this command in your terminal:"
    echo "     $SCRIPT_DIR/test-watcher.sh $CONTAINER_NAME"
fi
echo ""
echo " Useful Podman commands:"
echo "  -> View live progress : podman logs -f $CONTAINER_NAME"
echo "  -> Stop converter     : podman stop $CONTAINER_NAME"
echo "  -> Start converter    : podman start $CONTAINER_NAME"
echo "=================================================================="
