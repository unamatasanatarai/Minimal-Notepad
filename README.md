# Minimal Notepad

A lightweight, distraction-free native macOS plain text editor built for immediate launch and frictionless writing without runtime bloat.

Minimal Notepad is a zero-configuration text editor engineered with native AppKit and TextKit 1. It delivers an instant-launch plain text canvas with robust encoding resilience, in-memory search and replace, and direct filesystem persistence—designed to get out of your way and let you focus entirely on your words and code.

<p align="center">
  <img src="Resources/MinimalNotepad.iconset/icon_256x256.png" alt="Minimal Notepad App Icon" width="128" height="128" />
</p>

<p align="center">
  <a href="https://github.com/unamatasanatarai/Minimal-Notepad/releases/latest">
    <img src="https://img.shields.io/github/v/release/unamatasanatarai/Minimal-Notepad?style=flat-square&color=2ea44f" alt="Latest Release" />
  </a>
  <img src="https://img.shields.io/badge/Platform-macOS%2011.0+-lightgrey?style=flat-square" alt="Platform: macOS 11.0+" />
  <img src="https://img.shields.io/badge/Language-Swift-FA7343?style=flat-square&logo=swift" alt="Language: Swift" />
  <img src="https://img.shields.io/badge/Framework-AppKit%20%2F%20TextKit-blue?style=flat-square" alt="Framework: AppKit / TextKit" />
  <img src="https://img.shields.io/badge/License-MIT-blue?style=flat-square" alt="License: MIT" />
</p>

<p align="center">
  <a href="https://github.com/unamatasanatarai/Minimal-Notepad/releases/latest"><strong>Download Latest Release</strong></a> &bull;
  <a href="#quick-start"><strong>Quick Start</strong></a> &bull;
  <a href="#key-capabilities"><strong>Key Capabilities</strong></a> &bull;
  <a href="#keyboard-shortcuts"><strong>Keyboard Shortcuts</strong></a>
</p>

---

## Why Minimal Notepad?

Most modern text editors have evolved into massive, resource-heavy application suites. They package entire web browser runtimes, run continuous background telemetry, and burden simple note-taking tasks with complex plugin setups, cloud synchronization prompts, and sluggish cold starts.

When you only need to inspect a log file, jot down immediate thoughts, or manipulate plain text, you shouldn't have to wait for heavy application stacks to load.

**Minimal Notepad solves this by returning to the fundamentals of macOS software engineering:**

* **Zero Startup Delay**: Launches directly into a focused editing buffer without template pickers, workspace selection dialogs, or telemetry handshakes.
* **Pure Plain Text Purity**: System typography automatically sanitizes incoming rich-text styling, graphics, and smart substitutions to ensure clean ASCII and UTF-8 output.
* **Complete System Independence**: No runtime daemons, no background analytics, no hidden dotfiles, and zero external dependency trees.

---

## Key Capabilities

### ⚡ Instant Single-Window Architecture
Opens straight into an active editor window using a single-process AppKit lifecycle. All file interactions, document resets, and external drag-and-drop actions recycle the existing window canvas cleanly without spawning unmanaged windows or background helper processes.

### 🛡️ Resilient Encoding Fallback Engine
Opens arbitrary file types safely using a multi-stage encoding detection pipeline. If standard `UTF-8` parsing fails, the engine tries `UTF-16` (when a byte-order mark is present), then `Windows-CP1252`, and finally `macOS Roman`, which accepts any byte sequence, preventing window freezes or read crashes on legacy files.

### 🔍 Integrated Linear Search & Batch Replace
Access an inline query drawer via `Cmd + F` built directly into the window stack. Perform instant literal string queries with real-time match tracking, wrap-around navigation, single occurrence substitution, and full document bulk replacements.

### 💾 Safe Persistence with Dirty-State Protection
Visual change indicators keep you informed in real time: an asterisk (`*`) prefixes the active file name in the top title bar and activates the native macOS unsaved document indicator. Modifying or closing the buffer prompts a native confirmation sheet to prevent accidental data loss.

### 📂 Seamless Drag-and-Drop Ingestion
Drop files directly from Finder onto the editor canvas. The system automatically inspects filesystem references, resolves symbolic links down to their target paths, and rejects directories, pipes, and devices with informative native alerts.

### 🖨️ Native System Print Integration
Generate standard paginated print operations using the system printing pipeline via `Cmd + P`, supporting physical printer output, preview formatting, and direct PDF generation.

---

## Product Experience

```text
1. Launch ─────────► Opens instantly into an empty, focused plain-text canvas
2. Draft / Drop ───► Type freely or drop any file directly onto the editor window
3. Edit & Search ──► Use Cmd + F for quick literal matching and global replacements
4. Title Tracking ─► Watch the top bar reflect live changes with *filename indicators
5. Save & Print ───► Commit directly to disk with Cmd + S or print via Cmd + P
```

---

## What Makes It Different

| Characteristic | Minimal Notepad | Electron & Multi-Platform Editors |
| :--- | :--- | :--- |
| **Engine Architecture** | Native Swift & AppKit (TextKit 1) | Chromium runtime & Node.js subprocesses |
| **Memory Footprint** | Lightweight single native process | Multi-process browser engine pools |
| **Cold Startup** | Instantaneous single-window launch | Multi-second runtime bootstrapping |
| **Formatting Handling** | Strict plain text; strips rich text & graphics | Rich text parsing by default |
| **External Dependencies** | Zero external frameworks or libraries | Hundreds of vendor packages and modules |
| **Configuration** | Zero setup; launches ready to write | Config files, extension stores, and accounts |

---

## Keyboard Shortcuts

Minimal Notepad is fully operable through standard native macOS key commands:

| Shortcut | Action | Description |
| :--- | :--- | :--- |
| `Cmd + N` | **New File** | Clear buffer and reset document state (prompts if dirty) |
| `Cmd + O` | **Open...** | Present native system file chooser |
| `Cmd + S` | **Save** | Overwrite current file or trigger save panel for new drafts |
| `Cmd + Shift + S` | **Save As...** | Save text buffer to a new filesystem destination |
| `Cmd + P` | **Print...** | Open native macOS print and PDF export dialog |
| `Cmd + F` | **Find & Replace** | Open or focus inline search and substitution overlay |
| `Cmd + Z` | **Undo** | Step backward through text alterations |
| `Cmd + Shift + Z` | **Redo** | Replay undone text alterations |
| `Cmd + X` | **Cut** | Cut selected characters to clipboard |
| `Cmd + C` | **Copy** | Copy selected characters to clipboard |
| `Cmd + V` | **Paste** | Paste clipboard contents as unformatted plain text |
| `Cmd + A` | **Select All** | Highlight entire document buffer |
| `Cmd + Q` | **Quit** | Terminate application (prompts if unsaved changes exist) |

---

## Quick Start

### Download Prebuilt App

1. Download the latest compiled bundle from [GitHub Releases](https://github.com/unamatasanatarai/Minimal-Notepad/releases/latest).
2. Move `Minimal Notepad.app` to your `/Applications` directory.
3. Open the application.

---

## Building from Source

### Prerequisites

* macOS 11.0 (Big Sur) or newer
* Xcode Command Line Tools (`xcode-select --install`)
* GNU Make

### Build and Run

1. Clone the repository:
   ```bash
   git clone https://github.com/unamatasanatarai/Minimal-Notepad.git
   cd Minimal-Notepad
   ```

2. Compile the standalone application bundle:
   ```bash
   make
   ```

3. Launch the compiled application:
   ```bash
   make run
   ```

The compiled binary and macOS app bundle will be placed in `build/Minimal Notepad.app`.

To clean up build artifacts:
```bash
make clean
```

---

## Architecture & Technology

Minimal Notepad is constructed as a single-binary AppKit application:

* **Language**: Swift
* **UI Framework**: AppKit (`NSWindow`, `NSStackView`, `NSScrollView`)
* **Text Engine**: TextKit 1 (`NSTextView`, `NSLayoutManager`, `NSTextStorage`, `NSTextContainer`)
* **Styling**: Locked Aqua light appearance with native monospaced system typography
* **Packaging**: Standard macOS `.app` bundle generated via shell and GNU Make

---

## License

This project is licensed under the terms of the [MIT License](LICENSE).
