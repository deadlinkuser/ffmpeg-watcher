#!/bin/bash
WATCH_DIR="/watch"
OUTPUT_DIR="/output"
FAILED_DIR="$WATCH_DIR/_failed"
STOP_REQUESTED=0
MAX_HEVC_PASSTHRU_BYTES=524288000  # 500 MiB

# Trap Podman stop signals (SIGTERM/SIGINT) for graceful exit
trap 'echo "Stop signal received. Finishing current job before exiting..."; STOP_REQUESTED=1' SIGTERM SIGINT

quarantine_file() {
    local src="$1"
    local failed_out="$2"
    mkdir -p "$FAILED_DIR"
    [ -n "$failed_out" ] && [ -f "$failed_out" ] && mv -f "$failed_out" "$FAILED_DIR/"
    mv -f "$src" "$FAILED_DIR/"
    ((files_failed++))
}

echo "Watching $WATCH_DIR (and subfolders) for new files..."

while true; do
    # Exit cleanly if podman stop was triggered while idle
    if [ "$STOP_REQUESTED" -eq 1 ]; then
        echo "Graceful stop triggered. Exiting..."
        exit 0
    fi

    files_processed=0
    files_failed=0

    while IFS= read -r -d '' file; do
        [ ! -f "$file" ] && continue

        # Skip files still being copied/written
        size1=$(stat -c%s "$file" 2>/dev/null) || continue
        sleep 3
        size2=$(stat -c%s "$file" 2>/dev/null) || continue
        [ "$size1" -ne "$size2" ] && continue

        # Calculate relative subfolder path and create it in OUTPUT_DIR
        rel_path="${file#$WATCH_DIR/}"
        rel_dir=$(dirname -- "$rel_path")
        if [ "$rel_dir" = "." ]; then
            target_dir="$OUTPUT_DIR"
        else
            target_dir="$OUTPUT_DIR/$rel_dir"
        fi
        mkdir -p "$target_dir"

        filename=$(basename -- "$file")
        base="${filename%.*}"
        temp_output="$target_dir/${base}.part.mkv"
        final_output="$target_dir/${base}.mkv"

        echo "Analyzing streams (single-pass) for: $rel_path"

        # Single ffprobe call captures duration + all stream details
        probe_data=$(ffprobe -v error -analyzeduration 100M -probesize 100M \
            -show_entries format=duration:stream=index,codec_type,codec_name:stream_tags=language \
            -of compact=p=0:nk=0 "$file")

        src_dur=$(echo "$probe_data" | grep "^duration=" | cut -d= -f2 | cut -d. -f1)

        # 1. Video selection (Passthru if already HEVC and <= 500 MiB)
        v_codec=$(echo "$probe_data" | grep "codec_type=video" | head -n1 | sed -n 's/.*codec_name=\([^|]*\).*/\1/p')
        map_args=("-map" "0:v:0")

        if [ "$v_codec" = "hevc" ] && [ "$size2" -le "$MAX_HEVC_PASSTHRU_BYTES" ]; then
            echo "  -> Video: HEVC <= 500MB ($((size2 / 1048576))MB). Passthru."
            video_args=("-c:v" "copy")
        else
            echo "  -> Video: ${v_codec:-unknown} ($((size2 / 1048576))MB). Encoding 10-bit x265 (fast + weightp)."
            video_args=(
                "-c:v" "libx265"
                "-pix_fmt" "yuv420p10le"
                "-crf" "20"
                "-preset" "fast"
                "-x265-params" "aq-mode=3:strong-intra-smoothing=0:no-sao=1:weightp=1:pools=16"
            )
        fi

        # 2. Audio selection (English preferred, fallback to all)
        audio_lines=$(echo "$probe_data" | grep "codec_type=audio")
        eng_audio=$(echo "$audio_lines" | grep "tag:language=eng")
        selected_audio="${eng_audio:-$audio_lines}"

        audio_args=()
        a_idx=0
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            s_index=$(echo "$line" | sed -n 's/.*index=\([^|]*\).*/\1/p')
            s_codec=$(echo "$line" | sed -n 's/.*codec_name=\([^|]*\).*/\1/p')
            s_lang=$(echo "$line" | sed -n 's/.*tag:language=\([^|]*\).*/\1/p')

            map_args+=("-map" "0:$s_index")
            if [ "$s_codec" = "aac" ]; then
                echo "  -> Audio #$a_idx (stream $s_index, ${s_lang:-und}): AAC Passthru"
                audio_args+=("-c:a:$a_idx" "copy")
            else
                echo "  -> Audio #$a_idx (stream $s_index, ${s_lang:-und}): $s_codec -> AAC 256k"
                audio_args+=("-c:a:$a_idx" "aac" "-b:a:$a_idx" "256k")
            fi
            ((a_idx++))
        done <<< "$selected_audio"

        # 3. Subtitle selection (English preferred, fallback to all)
        sub_lines=$(echo "$probe_data" | grep "codec_type=subtitle")
        eng_subs=$(echo "$sub_lines" | grep "tag:language=eng")
        selected_subs="${eng_subs:-$sub_lines}"

        sub_args=()
        needs_srt=0
        has_subs=0
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            has_subs=1
            s_index=$(echo "$line" | sed -n 's/.*index=\([^|]*\).*/\1/p')
            s_codec=$(echo "$line" | sed -n 's/.*codec_name=\([^|]*\).*/\1/p')
            s_lang=$(echo "$line" | sed -n 's/.*tag:language=\([^|]*\).*/\1/p')

            echo "  -> Subtitle (stream $s_index, ${s_lang:-und}): $s_codec"
            map_args+=("-map" "0:$s_index")
            if [[ "$s_codec" =~ ^(mov_text|tx3g|webvtt|eia_608)$ ]]; then
                needs_srt=1
            fi
        done <<< "$selected_subs"

        if [ "$has_subs" -eq 1 ]; then
            if [ "$needs_srt" -eq 1 ]; then
                echo "  -> Subtitles: Converting text subtitles to SRT"
                sub_args=("-c:s" "srt")
            else
                echo "  -> Subtitles: Passthru"
                sub_args=("-c:s" "copy")
            fi
        fi

        echo "Encoding: $rel_path -> $final_output"

        ffmpeg -y -nostdin -hide_banner -loglevel warning -stats \
            -analyzeduration 100M -probesize 100M \
            -i "$file" \
            "${map_args[@]}" \
            -map_metadata 0 \
            -map_chapters 0 \
            "${video_args[@]}" \
            "${audio_args[@]}" \
            "${sub_args[@]}" \
            -f matroska "$temp_output"
        ffmpeg_rc=$?

        # If container stop was requested mid-encode, clean temp file and leave source untouched
        if [ "$STOP_REQUESTED" -eq 1 ] && [ "$ffmpeg_rc" -ne 0 ]; then
            echo "Interrupted by stop signal. Removing partial output and leaving source in queue."
            rm -f "$temp_output"
            break
        fi

        if [ "$ffmpeg_rc" -eq 0 ]; then
            mv -f "$temp_output" "$final_output"
            echo "Running lightweight validation checks on: $filename"

            out_size=$(stat -c%s "$final_output" 2>/dev/null || echo 0)
            out_probe=$(ffprobe -v error -show_entries format=duration:stream=codec_type \
                -of compact=p=0:nk=0 "$final_output")
            out_dur=$(echo "$out_probe" | grep "^duration=" | cut -d= -f2 | cut -d. -f1)

            diff=$(( ${src_dur:-0} - ${out_dur:-0} ))
            diff=${diff#-}

            if [ "$out_size" -gt 102400 ] && echo "$out_probe" | grep -q "codec_type=video" && [ "$diff" -le 2 ]; then
                echo "Verified ($out_dur sec, $((out_size / 1048576))MB): $filename. Removing original."
                rm -f "$file"
                ((files_processed++))
            else
                echo "Validation FAILED for $filename! (Size: ${out_size}B | Src Dur: ${src_dur}s | Out Dur: ${out_dur}s)"
                mv -f "$final_output" "$target_dir/${base}_FAILED_OUTPUT.mkv" 2>/dev/null || true
                quarantine_file "$file" "$target_dir/${base}_FAILED_OUTPUT.mkv"
            fi
        else
            echo "Error encoding $filename. Cleaning temp file and moving source to _failed."
            rm -f "$temp_output"
            quarantine_file "$file" ""
        fi

        if [ "$STOP_REQUESTED" -eq 1 ]; then
            echo "Graceful stop triggered. Exiting..."
            break
        fi

    done < <(find "$WATCH_DIR" -path "$FAILED_DIR" -prune -o -type f ! -name "*.part.mkv" \( -iname "*.mkv" -o -iname "*.mp4" -o -iname "*.avi" -o -iname "*.mov" -o -iname "*.m4v" \) -print0)

    # One-time cleanup of empty subfolders after the entire queue finishes
    if [ "$files_processed" -gt 0 ] || [ "$files_failed" -gt 0 ]; then
        echo "Queue complete. Cleaning up empty folders in $WATCH_DIR..."
        find "$WATCH_DIR" -mindepth 1 -depth -not -path "$FAILED_DIR*" -type d -empty -delete
    fi

    if [ "$STOP_REQUESTED" -eq 1 ]; then
        exit 0
    fi

    sleep 5
done
