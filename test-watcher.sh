#!/bin/bash
CONTAINER="${1:-ffmpeg-watcher}"
USE_GUI=0
if { [ -n "$DISPLAY" ] || [ -n "$WAYLAND_DISPLAY" ]; } && command -v zenity >/dev/null 2>&1; then
    USE_GUI=1
fi

strip_markup() { echo -e "$1" | sed -e 's/<[^>]*>//g' -e 's/&amp;/\&/g'; }

show_step() {
    local title="$1" body="$2" next_label="${3:-Next Step}"
    if [ "$USE_GUI" -eq 1 ]; then
        zenity --question --title="$title" --width=620 --height=440 --ok-label="$next_label" --cancel-label="Abort & Clean" --text="$body"
    else
        echo -e "\n=== $title ==="
        strip_markup "$body"
        read -rp "Press [Enter] for $next_label, or 'q' to Abort & Clean: " choice
        [[ "$choice" =~ ^[Qq]$ ]] && return 1 || return 0
    fi
}

show_info() {
    if [ "$USE_GUI" -eq 1 ]; then
        zenity --info --title="$1" --width=460 --text="$2"
    else
        echo -e "\n=== $1 ===" && strip_markup "$2"
    fi
}

verify_step() {
    local since_ts="$1" timeout="$2"
    shift 2
    local checks=("$@") elapsed=0 all_passed=0 logs=""
    [ "$USE_GUI" -eq 0 ] && echo "Verifying (up to ${timeout}s)..."

    while [ "$elapsed" -lt "$timeout" ]; do
        all_passed=1
        logs=$(podman logs --since "$since_ts" "$CONTAINER" 2>&1)
        for item in "${checks[@]}"; do
            local c_type="${item%%|*}" rest="${item#*|}"
            local target="${rest%%|*}"
            case "$c_type" in
                log)         echo "$logs" | grep -Fq "$target" || all_passed=0 ;;
                file_exists) podman exec "$CONTAINER" test -f "$target" 2>/dev/null || all_passed=0 ;;
                file_gone)   podman exec "$CONTAINER" test ! -e "$target" 2>/dev/null || all_passed=0 ;;
                dir_gone)    podman exec "$CONTAINER" test ! -d "$target" 2>/dev/null || all_passed=0 ;;
            esac
            [ "$all_passed" -eq 0 ] && break
        done
        [ "$all_passed" -eq 1 ] && break
        sleep 2; elapsed=$((elapsed + 2))
    done

    logs=$(podman logs --since "$since_ts" "$CONTAINER" 2>&1)
    REPORT=""; OVERALL_OK=1
    for item in "${checks[@]}"; do
        local c_type="${item%%|*}" rest="${item#*|}"
        local target="${rest%%|*}" desc="${rest#*|}" passed=0
        case "$c_type" in
            log)         echo "$logs" | grep -Fq "$target" && passed=1 ;;
            file_exists) podman exec "$CONTAINER" test -f "$target" 2>/dev/null && passed=1 ;;
            file_gone)   podman exec "$CONTAINER" test ! -e "$target" 2>/dev/null && passed=1 ;;
            dir_gone)    podman exec "$CONTAINER" test ! -d "$target" 2>/dev/null && passed=1 ;;
        esac
        if [ "$passed" -eq 1 ]; then
            REPORT+="  <span color='#2e7d32'><b>✔ PASS:</b></span> $desc\n"
        else
            REPORT+="  <span color='#c62828'><b>✘ FAIL:</b></span> $desc\n"; OVERALL_OK=0
        fi
    done
    [ "$OVERALL_OK" -eq 1 ] && STATUS_BANNER="<span color='#2e7d32'><b>ALL CHECKS PASSED</b></span>" || STATUS_BANNER="<span color='#c62828'><b>SOME CHECKS FAILED</b></span>"
}

cleanup_all() {
    podman start "$CONTAINER" >/dev/null 2>&1
    podman exec "$CONTAINER" rm -rf /watch/test_codecs /watch/test_lang /watch/test_chars /watch/corrupt_test.mkv /watch/stop_test.mp4 /watch/_failed/corrupt_test.mkv /output/test_codecs /output/test_lang /output/test_chars /output/stop_test.mkv /output/stop_test.part.mkv 2>/dev/null
}

abort_wizard() { cleanup_all; show_info "Test Aborted" "Temporary test files cleaned up."; exit 0; }

if ! podman container exists "$CONTAINER" 2>/dev/null; then
    show_info "Container Not Found" "Cannot find container <b>$CONTAINER</b>.\nUsage: $0 [container_name]"
    exit 1
fi
[ "$(podman inspect -f '{{.State.Running}}' "$CONTAINER")" != "true" ] && podman start "$CONTAINER" >/dev/null 2>&1 && sleep 2
show_step "FFmpeg Watcher — Automated Verification Suite" \
"Runs 5 live tests against <b>$CONTAINER</b> and automatically verifies logs &amp; output files.\n\n• Step 1: H.264/Xvid encoding, HEVC passthrough &amp; folder cleanup\n• Step 2: English track filtering, non-English fallback &amp; SRT conversion\n• Step 3: Special characters, spaces &amp; brackets\n• Step 4: Corrupt file quarantine (_failed)\n• Step 5: Mid-encode graceful stop safety" "Start Test 1" || exit 0

# STEP 1
STEP_START=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
podman exec "$CONTAINER" sh -c 'mkdir -p /tmp/test_codecs/nested_folder && ffmpeg -y -v error -f lavfi -i testsrc=duration=10:size=1280x720:rate=24 -f lavfi -i sine=frequency=440:duration=10 -c:v libx264 -c:a aac -metadata:s:a:0 language=eng /tmp/test_codecs/h264_aac.mp4 && ffmpeg -y -v error -f lavfi -i testsrc=duration=10:size=1280x720:rate=24 -f lavfi -i sine=frequency=550:duration=10 -c:v libx265 -tag:v hvc1 -c:a aac -metadata:s:a:0 language=eng /tmp/test_codecs/hevc_passthru.mkv && ffmpeg -y -v error -f lavfi -i testsrc=duration=10:size=1280x720:rate=24 -f lavfi -i sine=frequency=660:duration=10 -c:v mpeg4 -c:a libmp3lame /tmp/test_codecs/nested_folder/legacy_xvid.avi && mv /tmp/test_codecs /watch/'
verify_step "$STEP_START" 40 \
    "log|Encoding 10-bit x265|H.264/Xvid encoded to 10-bit x265" \
    "log|HEVC <= 500MB|HEVC stream passthrough verified" \
    "log|mp3 -> AAC 256k|Legacy MP3 converted to AAC 256k" \
    "file_exists|/output/test_codecs/h264_aac.mkv|Output h264_aac.mkv created" \
    "file_exists|/output/test_codecs/hevc_passthru.mkv|Output hevc_passthru.mkv created" \
    "file_exists|/output/test_codecs/nested_folder/legacy_xvid.mkv|Nested legacy_xvid.mkv created" \
    "dir_gone|/watch/test_codecs|Empty /watch/test_codecs auto-deleted"
show_step "Step 1 of 5: Codecs & Folder Cleanup" "Status: $STATUS_BANNER\n\n$REPORT" "Next: Language & Subtitles" || abort_wizard

# STEP 2
STEP_START=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
podman exec "$CONTAINER" sh -c 'mkdir -p /tmp/test_lang && printf "1\n00:00:01,000 --> 00:00:08,000\nEng\n" > /tmp/en.srt && printf "1\n00:00:01,000 --> 00:00:08,000\nJpn\n" > /tmp/ja.srt && ffmpeg -y -v error -f lavfi -i testsrc=duration=10:size=1280x720:rate=24 -f lavfi -i sine=frequency=440:duration=10 -f lavfi -i sine=frequency=880:duration=10 -i /tmp/en.srt -i /tmp/ja.srt -map 0:v -map 1:a -map 2:a -map 3:s -map 4:s -c:v libx264 -c:a aac -c:s srt -metadata:s:a:0 language=jpn -metadata:s:a:1 language=eng -metadata:s:s:0 language=eng -metadata:s:s:1 language=jpn /tmp/test_lang/dual_eng_jpn.mkv && ffmpeg -y -v error -f lavfi -i testsrc=duration=10:size=1280x720:rate=24 -f lavfi -i sine=frequency=500:duration=10 -i /tmp/en.srt -c:v libx264 -c:a ac3 -c:s mov_text -metadata:s:a:0 language=jpn -metadata:s:s:0 language=eng /tmp/test_lang/jpn_fallback_mov_subs.mov && rm -f /tmp/en.srt /tmp/ja.srt && mv /tmp/test_lang /watch/'
verify_step "$STEP_START" 40 \
    "log|Audio #0 (stream 2, eng)|Dual-audio kept English & dropped Japanese" \
    "log|Audio #0 (stream 1, jpn): ac3 -> AAC 256k|Fallback kept Japanese audio & converted AC3" \
    "log|Converting text subtitles to SRT|mov_text subtitles converted to SRT" \
    "file_exists|/output/test_lang/dual_eng_jpn.mkv|Output dual_eng_jpn.mkv created" \
    "file_exists|/output/test_lang/jpn_fallback_mov_subs.mkv|Output jpn_fallback_mov_subs.mkv created" \
    "dir_gone|/watch/test_lang|Empty /watch/test_lang auto-deleted"
show_step "Step 2 of 5: Language & Subtitles" "Status: $STATUS_BANNER\n\n$REPORT" "Next: Special Characters" || abort_wizard

# STEP 3
STEP_START=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
TRICKY_NAME=$(printf 'Test & Show\x27s (1080p) [x264]')
podman exec "$CONTAINER" sh -c "mkdir -p '/tmp/test_chars/Season 01' && ffmpeg -y -v error -f lavfi -i testsrc=duration=10:size=1280x720:rate=24 -f lavfi -i sine=frequency=440:duration=10 -c:v libx264 -c:a aac '/tmp/test_chars/Season 01/${TRICKY_NAME}.mp4' && mv /tmp/test_chars /watch/"
verify_step "$STEP_START" 35 \
    "log|${TRICKY_NAME}.mp4|Parsed spaces, &, apostrophe, (), and []" \
    "file_exists|/output/test_chars/Season 01/${TRICKY_NAME}.mkv|Output created with special characters" \
    "dir_gone|/watch/test_chars|Empty /watch/test_chars auto-deleted"
show_step "Step 3 of 5: Special Characters" "Status: $STATUS_BANNER\n\n$REPORT" "Next: Corrupt File Test" || abort_wizard

# STEP 4
STEP_START=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
podman exec "$CONTAINER" sh -c 'echo "not a valid matroska video" > /watch/corrupt_test.mkv'
verify_step "$STEP_START" 25 \
    "log|Error encoding corrupt_test.mkv|Caught corrupt header without crashing" \
    "file_exists|/watch/_failed/corrupt_test.mkv|Quarantined in /watch/_failed/" \
    "file_gone|/watch/corrupt_test.mkv|Removed from root /watch"
show_step "Step 4 of 5: Corrupt File Quarantine" "Status: $STATUS_BANNER\n\n$REPORT" "Next: Graceful Stop Test" || abort_wizard

# STEP 5
STEP_START=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
podman exec "$CONTAINER" sh -c 'ffmpeg -y -v error -f lavfi -i testsrc=duration=60:size=1920x1080:rate=24 -f lavfi -i sine=frequency=440:duration=60 -c:v libx264 -c:a aac /tmp/stop_test.mp4 && mv /tmp/stop_test.mp4 /watch/stop_test.mp4'
for _ in $(seq 1 15); do
    podman logs --since "$STEP_START" "$CONTAINER" 2>&1 | grep -Fq "Encoding: stop_test.mp4" && break
    sleep 1
done
podman stop "$CONTAINER" >/dev/null 2>&1
STOP_LOGS=$(podman logs --since "$STEP_START" "$CONTAINER" 2>&1)
podman start "$CONTAINER" >/dev/null 2>&1; sleep 2

REPORT=""; OVERALL_OK=1
echo "$STOP_LOGS" | grep -Fq "Interrupted by stop signal. Removing partial output" && REPORT+="  <span color='#2e7d32'><b>✔ PASS:</b></span> Graceful stop logged\n" || { REPORT+="  <span color='#c62828'><b>✘ FAIL:</b></span> Stop message missing\n"; OVERALL_OK=0; }
podman exec "$CONTAINER" test ! -f "/output/stop_test.part.mkv" && REPORT+="  <span color='#2e7d32'><b>✔ PASS:</b></span> Partial output cleaned up\n" || { REPORT+="  <span color='#c62828'><b>✘ FAIL:</b></span> Partial output left behind\n"; OVERALL_OK=0; }
podman exec "$CONTAINER" test ! -f "/watch/_failed/stop_test.mp4" && REPORT+="  <span color='#2e7d32'><b>✔ PASS:</b></span> Source not falsely quarantined\n" || { REPORT+="  <span color='#c62828'><b>✘ FAIL:</b></span> Source wrongly moved to _failed\n"; OVERALL_OK=0; }
[ "$OVERALL_OK" -eq 1 ] && STATUS_BANNER="<span color='#2e7d32'><b>ALL CHECKS PASSED</b></span>" || STATUS_BANNER="<span color='#c62828'><b>SOME CHECKS FAILED</b></span>"

show_step "Step 5 of 5: Graceful Stop Safety" "Status: $STATUS_BANNER\n\n$REPORT\nClick <b>Clean & Finish</b> to wipe all test files." "Clean & Finish" || abort_wizard

cleanup_all
show_info "All Tests Verified & Cleaned!" "All temporary test files wiped. <b>$CONTAINER</b> is ready for real media!"

