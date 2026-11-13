            if [ "$out_size" -gt 102400 ] && echo "$out_probe" | grep -q "codec_type=video" && [ "$diff" -le 2 ]; then
                elapsed_sec=$((SECONDS - job_start_sec))
                elapsed_fmt=$(format_duration "$elapsed_sec")
                echo "Verified ($out_dur sec, $((out_size / 1048576))MB, $elapsed_fmt): $filename. Removing original."

                update_folder_summary \
                    "$target_dir" \
                    "${base}.mkv" \
                    "$out_size" \
                    "$elapsed_fmt" \
                    "$v_log_summary" \
                    "$a_log_summary" \
                    "$s_log_summary" \
                    "$out_dur"

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

    if [ "$files_processed" -gt 0 ] || [ "$files_failed" -gt 0 ]; then
        echo "Queue complete. Cleaning up empty folders in $WATCH_DIR..."
        find "$WATCH_DIR" -mindepth 1 -depth -not -path "$FAILED_DIR*" -type d -empty -delete
    fi

    if [ "$STOP_REQUESTED" -eq 1 ]; then
        exit 0
    fi

    sleep 5
done
