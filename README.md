# DriveCine Pro (macOS Apple Silicon)
### High-Performance Google Drive Direct Stream & Resume Ingestion for Wedding & Media Editors

[![macOS](https://img.shields.io/badge/macOS-14.0%2B-blue?logo=apple&style=for-the-badge)](https://apple.com)
[![Architecture](https://img.shields.io/badge/Architecture-Apple%20Silicon%20(arm64)-orange?style=for-the-badge)](https://apple.com)
[![Swift](https://img.shields.io/badge/Swift-6.4%20Concurrency-red?logo=swift&style=for-the-badge)](https://swift.org)
[![Storage](https://img.shields.io/badge/Persistence-SQLite3%20WAL-lightgrey?logo=sqlite&style=for-the-badge)](https://sqlite.org)

---

## 🎬 The Wedding Videographer's Problem
When downloading large project deliveries (100 GB – 1 TB+ of 4K ProRes, Sony XAVC, Blackmagic RAW, or multitrack 32-bit float audio) from Google Drive's web interface:
1. **The 2GB Split-Zip Disaster**: Google Drive automatically compresses folders into dozens of arbitrary 2GB `.zip` chunks (`001.zip`, `002.zip` ... `085.zip`).
2. **Blind Chunking**: You have no idea which files are inside which `.zip` without extracting everything.
3. **Double Disk Space Required**: You must download 250 GB of zip files, then uncompress another 250 GB, needing over 500 GB of free SSD space just to ingest one wedding project.
4. **Dropped Connections & Zero Resumability**: If a zip download drops at 95%, browser downloads fail with "Network Error" and cannot resume.
5. **No Integrity Check**: You have no way of knowing if a video frame or audio file was corrupted during extraction until you are in the edit timeline.

---

## 🚀 How DriveCine Pro Solves This
**DriveCine Pro** is a native macOS application engineered specifically for video editors, DITs, and media professionals:

- **Direct Stream Download (`alt=media`)**: Completely bypasses Google Drive's zip engine. Downloads each individual video/audio/RAW file directly into its authentic folder hierarchy on your target SSD.
- **Resumable Range Streaming**: If Wi-Fi drops, your Mac sleeps, or you pause, downloads resume from the exact byte offset using HTTP `Range: bytes=X-` and temporary `.part` buffers.
- **CryptoKit Streaming MD5 Verification**: Verifies byte-for-byte perfection against Google Drive's API MD5 checksum before marking each file completed.
- **Concurrent Stream Acceleration**: Saturates high-speed 1 Gbps / 10 Gbps internet connections with 1 to 8 concurrent file streams, with intelligent exponential backoff on Google rate limits (HTTP 429 / 403).
- **SQLite3 WAL Persistence**: Automatically saves all transfer states, byte offsets, and session records to SQLite. Quit anytime or reboot; all transfers pick up right where they left off.
- **macOS Keychain Security**: Securely stores your Google Drive API Keys and OAuth2 Bearer Tokens inside macOS Keychain (`Security.framework`).
- **Disk Safety Shield**: Calculates required project size against the free capacity of your destination volume (e.g. SanDisk Extreme, Samsung T7/T9, OWC ThunderBay) before downloading.

---

## 🖥 User Interface Design
Built with a sleek, dark pro aesthetic matching **DaVinci Resolve** and **Final Cut Pro**:
- **Sidebar**: Switch between Active Transfers, History, Recent Projects, and Settings.
- **Master Metrics Strip**: Real-time throughput gauge (e.g. `84.5 MB/s`), transfer progress, active streams, and calculated ETA.
- **Hierarchy Inspector**: Interactive tree with checkboxes and quick filter chips:
  - 🎥 **Video Only** (`.MOV`, `.MP4`, `.MXF`, `.BRAW`, `.R3D`)
  - 🎙 **Audio Only** (`.WAV`, `.MP3`, `.AAC`, `.AIFF`)
  - 📷 **Stills / RAW** (`.ARW`, `.CR3`, `.NEF`, `.DNG`, `.JPG`)
  - 🎛 **LUTs & Projects** (`.CUBE`, `.DRP`, `.PRPROJ`, `.FCPXML`)
- **Transfer Table**: Shows per-file speed, relative path, progress bar, MD5 badge, individual Pause / Resume, and "Reveal in Finder" button.

---

## 📦 How to Launch

The compiled, signed native macOS app bundle is located in this directory:
```bash
# Launch directly from Terminal
open DriveCine.app

# Or copy to your Mac's Applications folder
cp -R DriveCine.app /Applications/
```

### To Recompile from Source:
```bash
./build.sh
```

---

## 🔑 Authentication Options

DriveCine Pro supports three flexible access modes in **Settings** (⌘,):

1. **Google Drive API Key (Fastest & Recommended for Public / Shared Links)**:
   - For links set to *"Anyone with the link can view"*.
   - Free to create in Google Cloud Console in under 2 minutes:
     1. Go to [Google Cloud Console](https://console.cloud.google.com).
     2. Create a project and enable **Google Drive API**.
     3. Go to **Credentials** -> **Create Credentials** -> **API Key**.
     4. Paste it into DriveCine Pro Settings and click **Save**.
2. **OAuth 2.0 Bearer Token (For Private / Restricted Drives)**:
   - For private wedding folders shared specifically with your Google account.
3. **Direct Paste**:
   - Accepts any format:
     - `https://drive.google.com/drive/folders/1A2b3C...`
     - `https://drive.google.com/file/d/1A2b3C.../view`
     - `https://drive.google.com/open?id=1A2b3C...`
     - Raw Folder / File ID string.

---

## 🛠 Technology Stack
- **Framework**: SwiftUI & AppKit (macOS 14+)
- **Architecture**: Apple Silicon (`arm64`) native Mach-O
- **Concurrency**: Swift 6 Concurrency (Actors, `@MainActor`, `Task`, `Async/Await`)
- **Networking**: `URLSession` with chunked streaming and HTTP `Range` headers
- **Database**: Native `SQLite3` with Write-Ahead Logging (`WAL`)
- **Cryptography**: Apple `CryptoKit` (`Insecure.MD5` chunked streaming buffer)
- **Security**: Apple `Security.framework` (macOS Keychain Services)
