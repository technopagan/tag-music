#!/usr/bin/env sh

###############################################################################
#
# Simple POSIX-compliant music analysis & tagging script.
# Processes MP3 and M4A files to tag BPM, Key and Loudness.
#
# Usage: ./tag-music.sh /path/to/music
#
# The script can also be run without arguments. It will simply find all MP3
# and M4A files in its own directory recursively and process them.
#
###############################################################################
#
# Brief overview of the mode of operation:
#
# This script analyzes audio files and adds metadata tags for:
#   * BPM, using median & rounding
#   * Key, detected using keyfinder-cli harmonic analysis
#   * Loudness, measured using ReplayGain standard for album normalization
#
# The script  uses GNU "parallel" for speed.
# For M4A files, it first optimizes the container to ensure reliable tagging.
# It's non-destructive: only metadata tags are modified.
#
# MetaData tags that will be written:
# - MP3:
#   * BPM (TBPM)
#   * Key (TKEY) called "Initial Key"
#   * REPLAYGAIN_ALBUM_GAIN
#   * REPLAYGAIN_ALBUM_PEAK
#   * REPLAYGAIN_TRACK_GAIN
#   * REPLAYGAIN_TRACK_PEAK
# - M4A:
#   * BPM
#   * Key (written in "Grouping" tag. M4A doesn't support TKEY / "Initial Key")
#   * REPLAYGAIN_ALBUM_GAIN
#   * REPLAYGAIN_ALBUM_PEAK
#   * REPLAYGAIN_TRACK_GAIN
#   * REPLAYGAIN_TRACK_PEAK
#
###############################################################################
#
# Tools that need to be pre-installed:
#
#	* FFmpeg - for M4A container optimization and audio processing
#	 https://ffmpeg.org/
#
#	* KeyFinder CLI - for musical key detection and harmonic analysis
#	 https://github.com/mixxxdj/libkeyfinder
#
#	* mid3v2 - for MP3 ID3v2 tag editing (part of mutagen)
#	 https://mutagen.readthedocs.io/
#
#	* rsgain - for ReplayGain loudness analysis
#	 https://github.com/complexlogic/rsgain
#
#	* GNU parallel - for concurrent file processing
#	 https://www.gnu.org/software/parallel/
#
#	* mp4tags - for M4A/MP4 metadata editing (part of mp4v2)
#	 https://github.com/enzo1982/mp4v2
#
#	* aubiotrack - for beat tracking and BPM detection (part of aubio)
#	 https://aubio.org/
#
# Note: Additional standard tools are required such as "find", "mv", "rm",
# "mktemp", "awk", and a POSIX-compliant shell. These are provided by
# core-utils or similar default packages on most Unix-like systems.
#
###############################################################################
#
# This software is published under The Unlicense
#
# Autor: Tobias Baldauf
# Mail: kontakt@tobias-baldauf.de
# Web: http://www.tobias-baldauf.de/
#
###############################################################################
#
# This is free and unencumbered software released into the public domain.
#
# Anyone is free to copy, modify, publish, use, compile, sell, or
# distribute this software, either in source code form or as a compiled
# binary, for any purpose, commercial or non-commercial, and by any
# means.
#
# In jurisdictions that recognize copyright laws, the author or authors
# of this software dedicate any and all copyright interest in the
# software to the public domain. We make this dedication for the benefit
# of the public at large and to the detriment of our heirs and
# successors. We intend this dedication to be an overt act of
# relinquishment in perpetuity of all present and future rights to this
# software under copyright law.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR
# OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
# ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
# OTHER DEALINGS IN THE SOFTWARE.
#
# For more information, please refer to <https://unlicense.org/>
#
###############################################################################

###############################################################################
# GLOBAL RUNTIME SETTINGS
###############################################################################

export LANG=C LC_NUMERIC=C LC_COLLATE=C
set -eu

###############################################################################
# RUNTIME VARIABLES (usually do not require user interaction)
###############################################################################

MUSIC_DIR="${1:-$PWD}"

###############################################################################
# MAIN PROGRAM
###############################################################################

main() {
    # Calculate CPU cores and set PARALLEL_JOBS
    PARALLEL_JOBS=$(calculate_cpu_cores)

    # Check dependencies and exit if any are missing
    if ! check_dependencies; then
        exit 1
    fi

    printf "Processing music files in: %s\n" "$MUSIC_DIR"

    # Process each format
    for format in mp3 m4a; do
        files=$(find "$MUSIC_DIR" -name "*.$format" -type f)
        if [ -n "$files" ]; then
            count=$(printf "%s\n" "$files" | wc -l)
            printf "Processing %d %s files:\n" "$count" "$(printf "%s" "$format" | tr '[:lower:]' '[:upper:]')"

            # Set format-specific tagging commands
            if [ "$format" = "mp3" ]; then
                bpm_cmd="mid3v2 --TBPM"
                key_cmd="mid3v2 --TKEY"
            else
                bpm_cmd="mp4tags -b"
                key_cmd="mp4tags -G"
            fi

            # M4A repair step
            if [ "$format" = "m4a" ]; then
                repair_m4a_files
            fi

            # BPM analysis
            analyze_bpm "$format" "$bpm_cmd"

            # Key analysis
            analyze_key "$format" "$key_cmd"

            # Loudness analysis
            analyze_loudness "$format"
        fi
    done

    printf "All done!\n"
}

###############################################################################
# FUNCTIONS
###############################################################################

# Calculate number of CPU cores with fallback and set PARALLEL_JOBS
# Uses subshell for POSIX-compliant local variable scoping
calculate_cpu_cores() (
    # Calculate number of CPU cores with fallback (cores variable is local to subshell)
    if command -v nproc >/dev/null 2>&1; then
        cores=$(nproc)
    elif [ -r /proc/cpuinfo ]; then
        cores=$(grep -c "^processor" /proc/cpuinfo)
    else
        cores=2
    fi

    # Leave 2 cores free, minimum 1 job
    # Note: PARALLEL_JOBS needs to be set in parent shell, so we echo the result
    printf "%d" "${PARALLEL_JOBS:-$((cores > 2 ? cores - 2 : 1))}"
)

# Check that all required tools are available
# Uses subshell for POSIX-compliant local variable scoping
check_dependencies() (
    # Check dependencies (tool variable is local to subshell)
    for tool in ffmpeg keyfinder-cli mid3v2 rsgain parallel mp4tags aubiotrack; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            printf "Error: %s not found. Please install it.\n" "$tool"
            return 1
        fi
    done
    return 0
)

# Repair M4A container structure for reliable metadata tagging
# Uses subshell for POSIX-compliant local variable scoping
repair_m4a_files() (
    # Repair M4A files using ffmpeg (temp_file and temp_m4a variables are local to subshell)
    find "$MUSIC_DIR" -name "*.m4a" -type f -print0 | parallel -0 -j "$PARALLEL_JOBS" "
        # Use /tmp for better performance (often tmpfs), fallback to default temp
        if [ -w /tmp ]; then
            temp_file=\$(mktemp -p /tmp)
        else
            temp_file=\$(mktemp)
        fi
        temp_m4a=\"\${temp_file}.m4a\"
        mv \"\$temp_file\" \"\$temp_m4a\"
        if ffmpeg -y -v quiet -i {} -c copy -movflags +faststart \"\$temp_m4a\" 2>/dev/null; then
            mv \"\$temp_m4a\" {}
        else
            rm -f \"\$temp_m4a\" 2>/dev/null
        fi
    " 2>/dev/null
)

# Analyze and tag BPM using aubiotrack with median calculation and even rounding
# Uses subshell for POSIX-compliant local variable scoping
analyze_bpm() (
    format="$1"
    bpm_cmd="$2"

    # BPM analysis (bmp variable and awk variables are local to subshell)
    printf "  BPM analysis...\n"
    find "$MUSIC_DIR" -name "*.$format" -type f -print0 | parallel -0 -j "$PARALLEL_JOBS" "
        bpm=\$(aubiotrack {} 2>/dev/null | awk '
            BEGIN { count = 0 }
            NR > 1 { 
                interval = \$1 - prev
                if (interval > 0) {
                    intervals[count++] = interval
                }
            }
            { prev = \$1 }
            END { 
                if (count > 0) {
                    # Sort intervals array (simple bubble sort)
                    for (i = 0; i < count - 1; i++) {
                        for (j = 0; j < count - 1 - i; j++) {
                            if (intervals[j] > intervals[j + 1]) {
                                temp = intervals[j]
                                intervals[j] = intervals[j + 1]
                                intervals[j + 1] = temp
                            }
                        }
                    }
                    
                    # Calculate median
                    if (count % 2 == 1) {
                        median_interval = intervals[int(count / 2)]
                    } else {
                        median_interval = (intervals[count / 2 - 1] + intervals[count / 2]) / 2
                    }
                    
                    bpm = 60 / median_interval
                    even_bpm = int((bpm + 1) / 2) * 2
                    printf \"%.0f\", even_bpm
                } else {
                    print \"0\"
                }
            }')
        [ \"\$bpm\" -gt 0 ] 2>/dev/null && $bpm_cmd \"\$bpm\" {}
    " 2>/dev/null
)

# Analyze and tag musical key using keyfinder-cli harmonic analysis
# Uses subshell for POSIX-compliant local variable scoping
analyze_key() (
    format="$1"
    key_cmd="$2"

    # Key analysis (key variable is local to subshell)
    printf "  Key analysis...\n"
    find "$MUSIC_DIR" -name "*.$format" -type f -print0 | parallel -0 -j "$PARALLEL_JOBS" "
        key=\$(keyfinder-cli {} 2>/dev/null)
        [ -n \"\$key\" ] && $key_cmd \"\$key\" {}
    " 2>/dev/null
)

# Analyze and tag loudness using rsgain ReplayGain standard
# Uses subshell for POSIX-compliant local variable scoping
analyze_loudness() (
    format="$1"

    # Loudness analysis (all variables are local to subshell)
    printf "  Loudness analysis...\n"
    find "$MUSIC_DIR" -name "*.$format" -type f -print0 | parallel -0 -j "$PARALLEL_JOBS" "
        rsgain custom -a -s i {} >/dev/null 2>&1
    " 2>/dev/null
)

###############################################################################
# MAIN PROGRAM EXECUTION
###############################################################################

# Call main function
main
