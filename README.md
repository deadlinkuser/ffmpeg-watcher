# FFmpeg Watcher (Automated Podman Video Transcoder)

An automated, containerized FFmpeg watch-folder pipeline built for rootless Podman on Debian Linux. Drop video files (or entire nested season folders) into your **Watch** folder, and a background worker automatically converts, validates, and saves clean, space-saving Matroska (`.mkv`) files into your **Output** folder. DISCLOSURE - AI was used heavily in creating this repo as well as testing and modifying my personal container for use on other systems.

---

## 🚀 Quick Install (One-Line Command)

> **Prerequisite:** Make sure Podman is installed on your Debian machine (`sudo apt update && sudo apt install -y podman`).

Open your terminal (as your normal user—**do not use `sudo`**), copy and paste the command below, and press **Enter**:

```bash
G="github"; U="$Gusercontent.com"; bash <(curl -fsSL "https://raw.${U}/deadlinkuser/ffmpeg-watcher/refs/heads/main/install.sh")
```

### What Happens During Setup
The setup wizard walks you through 4 simple questions. **You can simply press `Enter` at every prompt** to accept the recommended defaults inside your own home folder:
1. **Container Name:** Defaults to `ffmpeg-watcher` (or enter any custom name).
2. **Watch & Output Folders:** Defaults to `~/ffmpeg-watcher/watch` and `~/ffmpeg-watcher/output`.
3. **CPU Performance:** If your PC has **16 or more CPU threads**, the wizard offers to cap container CPU usage (e.g., `total threads - 2`) so your desktop stays responsive while videos encode.
4. **Desktop Test Shortcut:** On XFCE/graphical desktops, offers to place a clickable **Test FFmpeg Watcher** icon on your Desktop.

---

## 📂 How to Use It Daily

1. **Drop videos in:** Copy or move video files (or nested show/season folders) into your **Watch** folder (`~/ffmpeg-watcher/watch`).
2. **Wait for automatic conversion:** The background worker detects new files once they finish copying, converts them, and places the finished `.mkv` files into your **Output** folder (`~/ffmpeg-watcher/output`) with the exact same folder structure.
3. **Automatic cleanup:** Once an output file passes validation, the original file in **Watch** is removed and empty subfolders are cleaned up. If a file is corrupted or unreadable, it is safely moved to `watch/_failed` so it never blocks the queue.

---

## ✨ What This Script Does

* **Standardized Matroska (`.mkv`) Output:** Scans `/watch` (and all nested subfolders) for `.mkv`, `.mp4`, `.avi`, `.mov`, and `.m4v` files, outputting standardized `.mkv` files while preserving your exact folder hierarchy in `/output`.
* **10-Bit HEVC (`x265`) Video Encoding:** Encodes video streams into 10-bit HEVC (`yuv420p10le`, CRF 20, `fast` preset with tuned `x265` parameters) at the source resolution.
* **High-Core CPU Optimization (16+ Threads):** Caps `x265` worker thread pools at 16 (`pools=16`) to prevent diminishing encoding returns and quality loss on high-thread CPUs, while the installer also lets you set a Podman CPU core limit (`--cpus`) so your desktop stays responsive during heavy encodes.
* **Smart HEVC Passthrough (≤ 500 MiB):** Automatically detects files that are already encoded in HEVC (`H.265`) and are **500 MiB or smaller**, copying the video stream directly (`-c:v copy`) without quality loss or re-encoding delay.
* **AAC Audio Passthrough & Conversion:** Copies existing `AAC` audio streams untouched (`-c:a copy`), while converting other formats (such as `AC3`, `EAC3`, `DTS`, `MP3`, or `FLAC`) to `256 kbps AAC`.
* **English Track Filtering with Smart Fallback:** Strips non-English audio and subtitle tracks when English (`eng`) tracks are present. If a file has no tracks tagged as English (such as foreign-language or untagged media), it falls back to keeping all tracks so you never end up with silent video.
* **Subtitle Compatibility Handling:** Copies standard Matroska-compatible subtitles (`SRT`, `ASS`, `PGS`, `VobSub`) directly, while automatically converting incompatible text formats (`mov_text`, `tx3g`, `webvtt`, `eia_608`) into clean `SRT`.
* **Metadata & Chapter Preservation:** Retains original file metadata tags and chapter markers (`-map_metadata 0 -map_chapters 0`).
* **Write-Safety & Atomic Outputs:** Waits until incoming file sizes stabilize before processing, writes to temporary `.part.mkv` files during encoding, and only moves the final `.mkv` into place upon completion.
* **Post-Encode Validation & Quarantine:** Verifies that every finished file is larger than 100 KB, contains a valid video stream, and matches the source duration within 2 seconds. Healthy source files are deleted automatically, while failed or corrupt files are quarantined in `/watch/_failed` without stalling the queue.
* **Automatic Empty Folder Cleanup:** Once a batch queue finishes, empty source subfolders inside `/watch` are removed bottom-up while protecting `/watch/_failed`.
* **Graceful Stop Protection:** Cleanly handles `podman stop` signals—finishing idle loops immediately or cleaning up incomplete `.part.mkv` files mid-encode without falsely flagging healthy source files as failed.

---

## 🧪 Built-In Automated Verification Suite

Want to make sure everything works before dropping in your real media? Run the built-in test suite, which generates sample videos, tests every feature above, and automatically checks container logs and output folders for `PASS` / `FAIL` results:

* **XFCE / Graphical Desktop Users:** Double-click the **Test FFmpeg Watcher** icon on your Desktop (uses `zenity` GUI popups if installed, or runs in terminal).
* **GNOME / KDE / Headless Debian Users:** Run this in your terminal:
  ```bash
  ~/.local/share/ffmpeg-watcher/test-watcher.sh ffmpeg-watcher
  ```

---

## 🛠️ Useful Podman Commands

* **View live encoding progress:** `podman logs -f ffmpeg-watcher`
* **Stop the background worker:** `podman stop ffmpeg-watcher`
* **Start the background worker:** `podman start ffmpeg-watcher`
* **Remove the container:** `podman rm -f ffmpeg-watcher`
