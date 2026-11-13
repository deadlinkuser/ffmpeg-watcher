# FFmpeg Watcher (Podman Automated Media Transcoder)

An automated, containerized FFmpeg watch-folder pipeline built for rootless Podman on Debian Linux. Drop video files or nested season folders into your watch folder, and the container automatically analyzes, transcodes, validates, and organizes clean Matroska (`.mkv`) outputs.

---

## 🚀 Quick Install (One-Line Command)

Copy and paste this command into your Debian terminal to set up your folders, scripts, and Podman container interactively:

```bash
bash <(curl -fsSL https://githubusercontent.com)
```

During setup, the installer safely configures everything inside your own `$HOME` directory and lets you:
1. Choose a custom **container name** (defaults to `ffmpeg-watcher`).
2. Choose custom **Watch** and **Output** folder paths (defaults to `~/ffmpeg-watcher/watch` and `~/ffmpeg-watcher/output`).
3. Automatically configure a **CPU core limit** if you have 16+ CPU threads so your desktop stays responsive.
4. Optionally add a clickable **Test FFmpeg Watcher** icon to your Desktop (on XFCE/graphical desktops).

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

## 🧪 Automated Verification Suite

The installer includes **`test-watcher.sh`**, an automated verification tool that tests codecs, passthrough, language filtering, special characters, corrupt-file quarantine, and graceful container stops—automatically checking container logs and output files for `PASS` / `FAIL` results.

* **XFCE / Graphical Desktop Users:** Double-click the **Test FFmpeg Watcher** icon on your Desktop for a step-by-step GUI wizard (requires `zenity`).
* **GNOME / KDE / Headless Debian Users:** Run `~/.local/share/ffmpeg-watcher/test-watcher.sh <container_name>` in your terminal for an interactive CLI test runner.
