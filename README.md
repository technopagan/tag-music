# 🎵 tag-music

> **Simple POSIX-compliant music analysis & tagging script**  
> Automatically analyzes and tags MP3 and M4A files with BPM, musical key, and loudness metadata.

[![POSIX Compliant](https://img.shields.io/badge/POSIX-compliant-brightgreen.svg)](https://en.wikipedia.org/wiki/POSIX)
[![License: Unlicense](https://img.shields.io/badge/license-Unlicense-blue.svg)](http://unlicense.org/)
[![Shell Script](https://img.shields.io/badge/shell-sh-89e051.svg)](https://en.wikipedia.org/wiki/Bourne_shell)

## ✨ Features

- **🎯 Automatic Analysis**: Detects BPM, musical key, and loudness for your music files
- **⚡ Fast Processing**: Uses GNU parallel for concurrent file processing
- **🔧 Non-destructive**: Only modifies metadata tags, never touches audio data
- **📁 Batch Processing**: Recursively processes entire music directories
- **🎼 Format Support**: Works with both MP3 and M4A audio files
- **🛠️ POSIX Compliant**: Runs on any Unix-like system with standard tools

## 📊 Metadata Tags Added

### MP3 Files

- **BPM** (`TBPM`) - Beats per minute using median calculation
- **Key** (`TKEY`) - Musical key detection via harmonic analysis
- **ReplayGain** - Album and track gain/peak for loudness normalization
    - `REPLAYGAIN_ALBUM_GAIN`
    - `REPLAYGAIN_ALBUM_PEAK`
    - `REPLAYGAIN_TRACK_GAIN`
    - `REPLAYGAIN_TRACK_PEAK`

### M4A Files

- **BPM** - Beats per minute using median calculation
- **Key** (via "Grouping" tag) - Musical key detection
- **ReplayGain** - Album and track gain/peak for loudness normalization
    - `REPLAYGAIN_ALBUM_GAIN`
    - `REPLAYGAIN_ALBUM_PEAK`
    - `REPLAYGAIN_TRACK_GAIN`
    - `REPLAYGAIN_TRACK_PEAK`

## 🚀 Quick Start

### Basic Usage

```bash
# Process files in a specific directory
./tag-music.sh /path/to/your/music

# Process files in current directory
./tag-music.sh
```

### Example Output

```console
Processing music files in: /home/user/Music
Processing 45 MP3 files:
  BPM analysis...
  Key analysis...
  Loudness analysis...
Processing 23 M4A files:
  BPM analysis...
  Key analysis...
  Loudness analysis...
All done!
```

## 📋 Prerequisites

Before running the script, make sure you have the following tools installed:

### Required Dependencies

| Tool | Purpose | Installation |
|------|---------|-------------|
| **[FFmpeg](https://ffmpeg.org/)** | M4A container optimization | `apt install ffmpeg` / `brew install ffmpeg` |
| **[KeyFinder CLI](https://github.com/mixxxdj/libkeyfinder)** | Musical key detection | `apt install keyfinder-cli` / `brew install keyfinder-cli` |
| **[mid3v2](https://mutagen.readthedocs.io/)** | MP3 ID3v2 tag editing | `apt install python3-mutagen` / `pip install mutagen` |
| **[rsgain](https://github.com/complexlogic/rsgain)** | ReplayGain loudness analysis | `apt install rsgain` / `brew install rsgain` |
| **[GNU parallel](https://www.gnu.org/software/parallel/)** | Concurrent processing | `apt install parallel` / `brew install parallel` |
| **[mp4tags](https://github.com/enzo1982/mp4v2)** | M4A/MP4 metadata editing | `apt install mp4v2-utils` / `brew install mp4v2` |
| **[aubiotrack](https://aubio.org/)** | BPM detection | `apt install aubio-tools` / `brew install aubio` |

### Ubuntu/Debian Installation

```bash
sudo apt update && sudo apt install -y \
  ffmpeg \
  keyfinder-cli \
  python3-mutagen \
  rsgain \
  parallel \
  mp4v2-utils \
  aubio-tools
```

### macOS Installation (Homebrew)

```bash
brew install \
  ffmpeg \
  keyfinder-cli \
  mutagen \
  rsgain \
  parallel \
  mp4v2 \
  aubio
```

## 🔧 How It Works

1. **🔍 Discovery**: Recursively finds all MP3 and M4A files in the target directory
2. **🛠️ M4A Optimization**: Repairs M4A container structure for reliable tagging
3. **🥁 BPM Analysis**: Uses `aubiotrack` with median calculation and even rounding
4. **🎼 Key Detection**: Employs `keyfinder-cli` for harmonic analysis
5. **🔊 Loudness Analysis**: Applies ReplayGain standard using `rsgain`
6. **⚡ Parallel Processing**: Processes multiple files simultaneously for speed

## 📁 File Structure

```text
your-music-directory/
├── album1/
│   ├── track1.mp3  ← Will be analyzed and tagged
│   ├── track2.mp3  ← Will be analyzed and tagged
│   └── track3.m4a  ← Will be analyzed and tagged
├── album2/
│   └── song.m4a    ← Will be analyzed and tagged
└── tag-music.sh    ← The script
```

## ⚙️ Advanced Usage

### Custom CPU Usage

The script automatically detects your CPU cores and leaves 2 cores free. To override this behavior, set the `PARALLEL_JOBS` environment variable:

```bash
# Use only 4 parallel jobs
PARALLEL_JOBS=4 ./tag-music.sh /path/to/music

# Use maximum cores (no reservation)
PARALLEL_JOBS=$(nproc) ./tag-music.sh /path/to/music
```

### Integration with Other Tools

```bash
# Process multiple directories
for dir in ~/Music/*/; do
    ./tag-music.sh "$dir"
done

# Process only recently modified files
find ~/Music -name "*.mp3" -mtime -7 -execdir ./tag-music.sh {} \;
```

## 🛡️ Safety & Reliability

- **✅ Non-destructive**: Only metadata is modified, audio content remains untouched
- **✅ Atomic operations**: Uses temporary files to prevent corruption
- **✅ Error handling**: Gracefully handles missing tools and corrupted files
- **✅ POSIX compliance**: Works across different Unix-like systems
- **✅ Memory efficient**: Processes files in batches to prevent memory issues

## 📄 License

This software is released into the **public domain** under [The Unlicense](http://unlicense.org/).

You are free to copy, modify, publish, use, compile, sell, or distribute this software for any purpose, commercial or non-commercial, and by any means.
