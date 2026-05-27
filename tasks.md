# Technical Task Breakdown: Minimal Native macOS Notepad

## 1. Context Summary

The objective is to build a lightweight, single-window, native macOS plain-text editor utilizing AppKit and `NSTextView` (`TextKit 1`). The application acts as a digital notepad that prioritizes instant launch, explicit manual saving via direct overwrite, and an "open-anything" philosophy with silent UTF-8 fallback.

### Key Assumptions & Dependencies

* **Framework Stack:** Built using AppKit (Swift/Objective-C) or SwiftUI with an explicit `NSViewRepresentable` bridge to `NSTextView` + `TextKit 1` to guarantee text layout stability.
* **Distribution Model:** Distributed directly (e.g., GitHub download) without App Store sandboxing constraints, allowing uninhibited filesystem access via native macOS permissions.
* **Architecture:** In-memory architecture where the entire file buffer is loaded into RAM. No backend, database, or external network sync layers exist.

---

## 2. Sequencing & Implementation Roadmap

```text id="task-sequence"
[Phase 1: Core Target & UI] ──> [Phase 2: Text Engine & Buffer] ──> [Phase 3: File I/O & Encoding]
                                                                            │
[Phase 5: Search & Replace] <── [Phase 4: Document Lifecycle & UX Alerts] <─┘

```

### Parallel Execution Tracks

* **Track A (UI & UX):** Task 1.1, Task 1.2, Task 4.2, and Task 5.1 can be progressed concurrently once the window controller scaffolding is established.
* **Track B (Core Systems):** Task 2.1, Task 3.1, and Task 3.2 must be developed sequentially as they form the foundational data pipeline (Read $\rightarrow$ Edit Buffer $\rightarrow$ Write).

---

## 3. Detailed Task Breakdown

## Phase 1: Application Scaffolding & Native UI Layer

### Task 1.1: Project Setup and Single-Window Window Lifecycle

* **Description:** Initialize the macOS application project, disable multi-window and tab configurations natively, and implement a strict single-window lifecycle architecture.
* **Acceptance Criteria:**
* Application launches under 1 second directly into a single, clean editor window with no template picker or welcome dialogs.
* Attempting to open a second application instance or a new file window reuses the existing window after passing dirty-state validations.
* Standard AppKit `NSWindow` styling is implemented with standard window control buttons (Close, Minimize, Zoom).


* **Dependencies:** None
* **Priority:** High

### Task 1.2: Main Menu and Native Key Equivalents Binding

* **Description:** Configure the system-wide application menu bar mapping to traditional native macOS commands and assign global keyboard shortcuts.
* **Acceptance Criteria:**
* File menu maps and binds in English only: New File (`Cmd+N`), Open (`Cmd+O`), Save (`Cmd+S`), Save As (`Shift+Cmd+S`), and Quit (`Cmd+Q`).
* Edit menu binds native standard text actions: Undo (`Cmd+Z`), Redo (`Shift+Cmd+Z`), Cut (`Cmd+X`), Copy (`Cmd+C`), Paste (`Cmd+V`), and Select All (`Cmd+A`).


* **Dependencies:** Task 1.1
* **Priority:** High

---

## Phase 2: Text Engine & Editing Buffer

### Task 2.1: Implement NSTextView & TextKit 1 Bridge

* **Description:** Embed an `NSTextView` backed by `TextKit 1` as the core editing canvas, ensuring proper layout configurations for performance and default styling.
* **Acceptance Criteria:**
* Canvas fills the viewport entirely, scales responsively with window resizing, and focuses the cursor automatically upon application launch.
* Typography is configured globally to use a native macOS monospaced font (e.g., SF Mono) with regular system font rendering scales.
* Layout properties are explicitly configured for plain text: rich text features, smart quotes, smart dashes, and automatic spell-checking substitutions are disabled.
* Pasting formatted text converts and strips down to unformatted plain text natively before entering the text storage buffer.


* **Dependencies:** Task 1.1
* **Priority:** High

### Task 2.2: Native Undo/Redo Stack and Selection Control

* **Description:** Bind the `NSTextView` built-in undo manager and tracking mechanisms to ensure responsive state handling.
* **Acceptance Criteria:**
* Invoking `Cmd+Z` and `Shift+Cmd+Z` traverses text mutations smoothly inside the active editing session.
* Selection state remains responsive across large selections without UI stuttering.
* Swapping or closing the active document clears the undo/redo buffer completely.


* **Dependencies:** Task 2.1
* **Priority:** Medium

---

## Phase 3: File I/O Layer & Encoding Strategy

### Task 3.1: Read Stream and Silent Fallback Decodification

* **Description:** Implement the file ingestion module responsible for loading files into memory and resolving paths.
* **Acceptance Criteria:**
* App attempts to load any arbitrary file size blindly without size verification gates or warning thresholds.
* Arbitrary raw binary files load without throwing access crashes; invalid bytes display replacement characters or raw text interpretation.
* System utilizes automated encoding heuristics. If character conversion fails, it falls back to UTF-8 encoding silently with no user-facing alerts.
* External file modifications (deletions, renames, updates by outside processes) are completely ignored by the file stream manager while open.


* **Dependencies:** Task 2.1
* **Priority:** High

### Task 3.2: Direct Overwrite Persistence Subsystem

* **Description:** Construct the save mechanism that commits the text stream directly back to the physical filesystem location.
* **Acceptance Criteria:**
* Saving an existing file overwrites the target destination path directly without utilizing secondary staging or temporary swap documents.
* New documents initiate a native macOS `NSSavePanel`, enforcing a standard plain-text UTF-8 string encoding default.
* Destructive file write errors (e.g., volume disconnect or full disk) bubble up safely to block dirty state clearing.


* **Dependencies:** Task 3.1
* **Priority:** High

---

## Phase 4: Document Lifecycle & UX Alerts

### Task 4.1: State Mutability and Dirty-Flag Subsystem

* **Description:** Implement a reliable state tracker that flags mutations to evaluate whether the text storage diverges from the source file.
* **Acceptance Criteria:**
* Any alphanumeric, punctuation, or whitespace alteration increments the modification flag, triggering the standard macOS unsaved bullet indicator inside the window title close widget.
* Executing an Undo action sequentially back to the baseline disk state automatically clears the dirty state indicator.
* Successful persistence operations clear the state flag immediately.


* **Dependencies:** Task 2.1, Task 3.2
* **Priority:** High

### Task 4.2: Application Exit Interceptor & Guard Alerts

* **Description:** Wire application termination events (`NSApplicationDelegate`) and file swap triggers into the dirty validation logic to protect unsaved work.
* **Acceptance Criteria:**
* Triggering `Cmd+Q`, window close, or dropping a new file while marked dirty pauses the transaction and displays a native app sheet alert window in English.
* Sheet presents three explicit choices: "Save", "Don't Save", and "Cancel".
* "Save" executes Task 3.2 and continues termination/swap on success; "Don't Save" discards modifications and exits/swaps immediately; "Cancel" completely aborts the interaction.


* **Dependencies:** Task 4.1
* **Priority:** High

### Task 4.3: Drag-and-Drop File Ingestion Validation Matrix

* **Description:** Register the editor view for filesystem dragging types and implement specific filtering logic matching the application guidelines.
* **Acceptance Criteria:**
* Drops featuring multiple entities filter out subsequent options, processing **only the first item** in the array.
* Directories and folder paths are rejected instantly, surfacing an informative English native error alert.
* Symbolic links and system aliases resolve cleanly down to their base files before parsing begins.


* **Dependencies:** Task 3.1, Task 4.2
* **Priority:** Medium

---

## Phase 5: Search & Replace Architecture

### Task 5.1: In-Memory Incremental Linear Search Engine

* **Description:** Architect an integrated inline search utility that operates directly against the text storage structure.
* **Acceptance Criteria:**
* `Cmd+F` launches a clean query component layer built inside the window layout hierarchy.
* Evaluation scans the buffer sequentially via direct literal text matching. Regular expression tracking is strictly omitted; expressions match symbols literally.
* Search matches update incrementally as the user types, highlighting occurrences and providing immediate "No Matches" string responses inside the UI when empty.


* **Dependencies:** Task 2.1
* **Priority:** Medium

### Task 5.2: Sequential Match Replace and Bulk Substitution Execution

* **Description:** Extend the search engine layer to support focused match replacements and global structural replacements.
* **Acceptance Criteria:**
* "Replace" updates the currently focused occurrence index item and shifts the viewer frame forward to the subsequent instance target.
* "Replace All" performs an in-place mutation of all matching literals across the entire layout container buffer.
* Heavy search/replace workflows complete without causing application crashes, keeping memory inflation under control.


* **Dependencies:** Task 5.1
* **Priority:** Medium
