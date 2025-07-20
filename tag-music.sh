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
#   * BPM, using median
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

###############################################################################
# GLOBAL RUNTIME SETTINGS
###############################################################################

LANG=C; export LANG
LC_NUMERIC=C; export LC_NUMERIC
LC_COLLATE=C; export LC_COLLATE
set -eu

###############################################################################
# FUNCTIONS
###############################################################################

# Calculate number of CPU cores with fallback and set PARALLEL_JOBS
# Uses subshell for POSIX-compliant local variable scoping
calculate_cpu_cores() (
    # Calculate number of CPU cores with fallback (__cores variable is local to subshell)
    if command -v nproc >/dev/null 2>&1; then
        __cores=$(nproc)
    elif [ -r /proc/cpuinfo ]; then
        __cores=$(grep -c "^processor" /proc/cpuinfo)
    elif command -v sysctl >/dev/null 2>&1; then
        __cores=$(sysctl -n hw.ncpu 2>/dev/null || echo "2")
    else
        __cores=2
    fi

    # Leave 2 cores free, minimum 1 job
    # Note: PARALLEL_JOBS needs to be set in parent shell, so we echo the result
    if [ "$__cores" -gt 2 ]; then
        printf "%d" $((__cores - 2))
    else
        printf "1"
    fi
)

# Check that all required tools are available
# Uses subshell for POSIX-compliant local variable scoping
check_dependencies() (
    # Check dependencies (__tool variable is local to subshell)
    for __tool in ffmpeg keyfinder-cli mid3v2 rsgain parallel mp4tags aubiotrack; do
        if ! command -v "$__tool" >/dev/null 2>&1; then
            printf "Error: %s not found. Please install it.\n" "$__tool"
            return 1
        fi
    done
    return 0
)

# Repair a single M4A file
# Uses subshell for POSIX-compliant local variable scoping
repair_single_m4a() (
    __file="$1"
    __format="$2"
    
    [ "$__format" != "m4a" ] && return 0
    
    if [ -w /tmp ]; then
        __temp_file=$(mktemp /tmp/tmpXXXXXX)
    else
        __temp_file=$(mktemp)
    fi
    __temp_m4a="${__temp_file}.m4a"
    mv "$__temp_file" "$__temp_m4a"
    if ffmpeg -y -v quiet -i "$__file" -c copy -movflags +faststart "$__temp_m4a" 2>/dev/null; then
        mv "$__temp_m4a" "$__file"
    else
        rm -f "$__temp_m4a" 2>/dev/null
    fi
)

# Analyze BPM for a single file
# Uses subshell for POSIX-compliant local variable scoping
analyze_single_bpm() (
    __file="$1"
    __format="$2"
    
    __bpm=$(aubiotrack "$__file" 2>/dev/null | awk '
        NR > 1 { 
            interval = $1 - prev
            if (interval > 0) {
                print interval
            }
        }
        { prev = $1 }' | sort -n | awk '
        { intervals[NR] = $1; count = NR }
        END { 
            if (count > 0) {
                # Calculate median from sorted intervals
                if (count % 2 == 1) {
                    median_interval = intervals[int((count + 1) / 2)]
                } else {
                    median_interval = (intervals[count / 2] + intervals[count / 2 + 1]) / 2
                }
                
                bpm = 60 / median_interval
                printf "%.0f", bpm
            } else {
                print "0"
            }
        }')
    
    if [ "$__bpm" -gt 0 ] 2>/dev/null; then
        case "$__format" in
            mp3) mid3v2 --TBPM="$__bpm" "$__file" ;;
            m4a) mp4tags -b "$__bpm" "$__file" ;;
        esac
    fi
)

# Analyze key for a single file
# Uses subshell for POSIX-compliant local variable scoping
analyze_single_key() (
    __file="$1"
    __format="$2"
    
    __key=$(keyfinder-cli "$__file" 2>/dev/null)
    if [ -n "$__key" ]; then
        case "$__format" in
            mp3) mid3v2 --TKEY="$__key" "$__file" ;;
            m4a) mp4tags -G "$__key" "$__file" ;;
        esac
    fi
)

# Analyze loudness for a single file
# Uses subshell for POSIX-compliant local variable scoping
analyze_single_loudness() (
    __file="$1"
    rsgain custom -a -s i "$__file" >/dev/null 2>&1
)

# Process a single file completely (repair, BPM, key, loudness)
# Uses subshell for POSIX-compliant local variable scoping
process_single_file() (
    __file="$1"
    __format="$2"
    
    # Call individual processing steps
    repair_single_m4a "$__file" "$__format"
    analyze_single_bpm "$__file" "$__format"
    analyze_single_key "$__file" "$__format"
    analyze_single_loudness "$__file"
)

# Process files of a specific format (mp3 or m4a)
# Uses subshell for POSIX-compliant local variable scoping
process_format() (
    __format="$1"
    
    # Store file list in temporary file to avoid multiple find operations
    if [ -w /tmp ]; then
        __filelist=$(mktemp /tmp/tmpXXXXXX)
    else
        __filelist=$(mktemp)
    fi
    find "$MUSIC_DIR" -name "*.$__format" -type f > "$__filelist"
    
    if [ -s "$__filelist" ]; then
        __count=$(wc -l < "$__filelist")
        printf "Processing %d %s files...\n" "$__count" "$__format"

        # Process each file completely in parallel - call script recursively with sh
        parallel -j "$PARALLEL_JOBS" -a "$__filelist" sh "$0" --process-single {} "$__format"
    fi
    
    # Clean up temporary file
    rm -f "$__filelist"
)

###############################################################################
# RUNTIME VARIABLES (usually do not require user interaction)
###############################################################################

# Handle single file processing mode first (before setting other variables)
if [ "${1:-}" = "--process-single" ]; then
    process_single_file "$2" "$3"
    exit 0
fi

# Set music directory (now we know $1 isn't "--process-single")
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
    for __format in mp3 m4a; do
        process_format "$__format"
    done

    printf "All done!\n"
}

###############################################################################
# MAIN PROGRAM EXECUTION
###############################################################################

# Call main function
main
