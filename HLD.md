# High-Level Product Description

# 1. Product Overview

## Problem Statement

macOS lacks a truly minimal native notepad-style editor focused on:

* Fast launch
* Plain text editing
* Arbitrary file opening
* Zero configuration
* Minimal UX complexity

Existing editors are often:

* Too heavy
* Developer-centric
* Rich-document focused
* Overengineered for quick editing tasks

---

## Product Vision

Build a native macOS `.app` that behaves like a lightweight desktop notepad:

* Start with an empty editor
* Open any file from disk
* Edit contents directly
* Save explicitly
* Warn before losing unsaved changes
* Stay intentionally simple

The product prioritizes:

* Simplicity
* Native UX
* Low maintenance
* Predictable behavior

---

## Target Users

### Primary Users

* macOS users needing quick edits
* Developers inspecting logs/configs
* Users opening unknown file types
* Power users wanting a lightweight fallback editor

---

## Core Value Proposition

> “A minimal native macOS notepad that opens anything and gets out of your way.”

---

# 2. Functional Requirements

## Must-Have

### File Operations

* Open file
* Open arbitrary file types
* Drag-and-drop file open
* Create new file
* Save
* Save As
* Quit application

---

### Editing

* Plain text editing
* Undo/redo
* Native copy/paste support
* Text selection
* Keyboard shortcuts

---

### Search

* Find
* Incremental search
* Find next/previous
* Replace
* Replace all
* Direct text matching only
* No regex support

---

### UX Behavior

* Empty editor on launch
* Single window
* Single document only
* Warn on unsaved exit
* No autosave
* No recovery system

---

### File Handling

* Detect encoding if possible
* Fallback to UTF-8 silently
* New files always saved as UTF-8
* Open any filesystem file
* Reject folders/directories
* Resolve aliases/symlinks and open target
* Allow network paths
* Multiple drag-and-drop files → open first file only

---

## Future Scope

None intentionally.

The product philosophy is:

* Resist feature creep
* Stay minimal permanently

---

# 3. Non-Functional Requirements

## Scalability

This is a local desktop application, but internal scalability still matters.

### Expectations

* Open very large files if system RAM permits
* Avoid arbitrary file-size limits
* Maintain responsive editing for common usage

### Accepted Constraints

* Extremely large files may freeze or slow the application
* User accepts this tradeoff

---

## Reliability

Goals:

* Predictable behavior
* Direct save semantics
* Minimal hidden logic

Non-goals:

* Crash recovery
* Transaction-safe editing

---

## Availability

* Fully offline
* No backend dependencies
* No cloud services

---

## Performance Expectations

### Startup

* Under 1 second on modern macOS hardware

### Editing

* Normal typing should remain responsive
* Find/replace should complete quickly for normal text files

---

## Security

* Native macOS permissions
* Full filesystem access allowed
* No sandbox restrictions required

---

## Privacy

* No telemetry
* No analytics
* No cloud synchronization
* No external communication

---

## Cost Efficiency

Operational cost:

* Essentially zero

No:

* Servers
* APIs
* Infrastructure
* Databases

---

# 4. Key User Flows

## Launch Application

1. User launches app
2. Empty editor appears
3. No file loaded initially

---

## Open Existing File

1. User selects Open or drags file into window
2. System validates target is a file
3. File loaded into memory
4. Encoding detection attempted
5. If detection fails:

   * Fallback to UTF-8
6. Content rendered in editor

---

## Drag-and-Drop File Open

1. User drags item into application window
2. Application validates dropped item
3. Validation rules:

   * Multiple file drops → load only first file
   * Directories/folders → reject
   * Aliases/symlinks → resolve and open target
   * Network paths → allowed
4. System validates resolved target is a file
5. File loaded into memory
6. Encoding detection attempted
7. If detection fails:

   * Fallback to UTF-8
8. Content rendered in editor

---

## Open Binary File

1. User opens arbitrary binary file
2. App attempts text interpretation
3. Invalid bytes may render as gibberish/replacement characters
4. Editing remains allowed

---

## Edit and Save

1. User edits content
2. Document marked dirty
3. User selects Save
4. File overwritten directly
5. Dirty state cleared

---

## Save New File

1. User creates new document
2. User selects Save As
3. Native save dialog appears
4. File saved as UTF-8
5. File becomes current document

---

## Quit With Unsaved Changes

1. User quits app
2. Dirty-state check occurs
3. Prompt displayed:

   * Save
   * Don’t Save
   * Cancel
4. User decision executed immediately

---

## Document Lifecycle

```text id="9o0sib"
Open
↓
Decode
↓
Editable buffer
↓
Dirty tracking
↓
Save validation
↓
Persistence
↓
Verification
```

### Lifecycle Notes

#### Decode

Responsibilities:

* Read file bytes
* Attempt encoding detection
* Convert bytes into editable text representation

Fallback behavior:

* UTF-8 fallback if detection fails

---

#### Editable Buffer

Responsibilities:

* In-memory text representation
* Backing storage for editing operations
* Undo/redo integration
* Selection state management

Implementation strategy:

* Native macOS text system using `NSTextView` + `TextKit 1`

---

#### Dirty Tracking

Responsibilities:

* Detect document modifications
* Track unsaved changes
* Control save prompts and quit protection

---

#### Save Validation

Responsibilities:

* Validate writable target path
* Reject invalid destinations
* Ensure target is not a directory
* Validate file accessibility before persistence

---

#### Persistence

Responsibilities:

* Encode text for save operation
* Write updated contents to filesystem
* Overwrite existing target file when applicable

---

#### Verification

Responsibilities:

* Confirm save operation completed successfully
* Clear dirty state only after successful completion
* Notify user if persistence failed

---

# 5. High-Level Architecture

## System Overview

```text id="4v16ji"
User
  ↓
Native macOS Window
  ↓
Editor Controller
  ↓
Text Engine
  ↓
File I/O Layer
  ↓
Filesystem
```

---

## Major Components

### Native UI Layer

Responsibilities:

* Menus
* Toolbar
* Keyboard shortcuts
* Drag-and-drop
* Window lifecycle
* Save/open dialogs

Recommended stack:

* AppKit preferred
* SwiftUI acceptable with AppKit interoperability

---

### Editor Controller

Central application coordinator.

Responsibilities:

* Current document state
* Dirty tracking
* File association
* Save/open flow
* Quit handling
* Find/replace coordination

---

### Text Engine

Responsibilities:

* Text rendering
* Selection handling
* Undo/redo
* Search operations
* Replace operations

Use native macOS text system instead of custom rendering.

Recommended implementation:

* `NSTextView`
* Mature `TextKit 1`

Rationale:

* Better stability for plain-text editing workflows
* Proven behavior with large text buffers
* More predictable performance characteristics
* Lower interoperability complexity compared to SwiftUI `TextEditor`

Avoid:

* Custom text rendering
* SwiftUI-only text editing architecture
* Experimental text system abstractions

---

### File I/O Layer

Responsibilities:

* Read files
* Detect encoding
* Convert bytes to text
* Overwrite files directly on save
* Validate file-vs-directory behavior

---

## Encoding Strategy

```text id="knjlwm"
Try Detect Encoding
       ↓
Success → Use Detected Encoding
       ↓
Failure → UTF-8
```

No:

* Encoding picker
* Encoding warnings
* Manual user selection

---

# 6. Scalability Strategy

## Memory Model

Design choice:

* Entire file loaded into RAM

Reason:

* Simpler architecture
* Faster development
* Lower maintenance

Tradeoff:

* Huge files may consume excessive memory

Accepted intentionally.

---

## Rendering Strategy

Use native text rendering to leverage:

* Optimized macOS text layout
* GPU acceleration where available
* Built-in selection/editing behavior

---

## Search Strategy

Find/replace performed in-memory against loaded document.

Behavior:

* Direct text matching only
* Incremental search supported
* No regex support
* No advanced indexing
* No semantic search

Advantages:

* Simplicity
* Predictable behavior
* Low implementation complexity
* Fast implementation for normal text files

Tradeoff:

* Large-file searches may become slow
* Full-document scans remain linear-time operations

---

## Window Strategy

Single-window architecture:

* Simplifies lifecycle management
* Reduces state complexity
* Easier save/quit handling

---

# 7. Reliability & Failure Handling

## Save Behavior

Files are overwritten directly.

```text id="q52n3k"
Editor Content
      ↓
Overwrite Existing File
```

Intentional simplification:

* No temp files
* No atomic save guarantees
* No recovery system

---

## Unsaved Data Protection

Only protection mechanism:

```text id="mgg1o4"
Unsaved Changes?
      ↓
Show Confirmation Dialog
```

If user chooses:

* “Don’t Save” → data lost permanently
* “Save” → overwrite file
* “Cancel” → abort quit

---

## Drag-and-Drop Validation Rules

Validation behavior:

| Input Type       | Behavior                |
| ---------------- | ----------------------- |
| Single file      | Open normally           |
| Multiple files   | Open first file only    |
| Directory/folder | Reject                  |
| Alias/symlink    | Resolve target and open |
| Network path     | Allowed                 |
| Invalid path     | Show error              |

---

## Failure Scenarios

### Invalid Encoding

Behavior:

* UTF-8 fallback silently

---

### Binary File Opened

Behavior:

* Render whatever possible
* Allow editing anyway

---

### Application Crash

Behavior:

* Unsaved data lost
* No recovery attempted

Accepted tradeoff.

---

### Disk Write Failure

Behavior:

* Save fails
* User notified
* No retry/recovery system

---

# 8. Security & Compliance

## Authentication

None.

---

## Authorization

Filesystem access delegated entirely to macOS.

---

## Sandboxing

No App Store sandbox assumptions.

Distribution model:

* Direct GitHub download

Allows:

* Access to arbitrary filesystem locations
* Standard native open/save behavior

---

## Data Protection

* No network communication
* Local-only processing

---

## Compliance

No meaningful compliance obligations because:

* No accounts
* No telemetry
* No cloud storage
* No user data collection

---

# 9. Product & Technical Tradeoffs

| Decision               | Benefit                           | Drawback                           |
| ---------------------- | --------------------------------- | ---------------------------------- |
| Full in-memory loading | Extremely simple architecture     | Huge files may freeze app          |
| Direct overwrite saves | Minimal implementation complexity | Risk of file corruption on failure |
| No autosave            | Predictable manual-save model     | Unsaved work easily lost           |
| Single-window design   | Simple lifecycle management       | No multi-document workflow         |
| UTF-8 fallback only    | Zero encoding UX complexity       | Incorrect rendering possible       |
| Open any file          | Maximum flexibility               | Binary gibberish UX                |
| No sandboxing          | Full filesystem access            | Less App Store friendly            |
| Native macOS controls  | Familiar UX                       | Platform lock-in                   |
| NSTextView + TextKit 1 | Stable native editing stack       | Older framework architecture       |
| No recovery system     | Lower maintenance burden          | Crash loses unsaved work           |

---

# 10. Risks & Unknowns

## Technical Risks

### Extremely Large Files

Potential issues:

* Memory exhaustion
* UI freezes
* Search slowdown

Accepted as non-critical.

---

### Encoding Misinterpretation

Fallback UTF-8 may:

* Corrupt visual rendering
* Show replacement characters

Accepted tradeoff.

---

### Binary Rendering Edge Cases

Some binary content may:

* Render poorly
* Stress text layout systems
* Cause performance issues

---

## Product Risks

### “Too Minimal”

Some users may expect:

* Tabs
* Syntax highlighting
* Recovery
* Autosave

The product intentionally rejects these expectations.

---

## Operational Risks

### Native macOS API Evolution

Future macOS changes could impact:

* File permissions
* Drag/drop APIs
* Text system behavior

---

# 11. Suggested MVP Scope

## Build First

### Core Editor

* Single-window text editor
* `NSTextView` + mature `TextKit 1`
* New/Open/Save/Save As
* Dirty-state tracking
* Native shortcuts

---

### File Handling

* Open arbitrary files
* Encoding detection + UTF-8 fallback
* Direct overwrite saving
* Drag-and-drop validation rules
* Alias/symlink resolution
* Network path support

---

### Search

* Incremental find
* Direct text matching only
* Replace
* Replace all
* No regex support

---

### User Experience

* Drag-and-drop open
* Find & replace
* Unsaved-change warning dialog

---

### Native Integration

* Cmd+O
* Cmd+S
* Cmd+Q
* Native file dialogs

---

## Explicitly Excluded

* Autosave
* Recovery
* Tabs
* Multiple windows
* Plugins
* Cloud sync
* Hex mode
* Encoding picker
* Collaboration
* Rich text formatting

---

# 12. Future Evolution

The intended future is stability, not expansion.

Architectural direction:

```text id="bd6ihk"
Simple Native Editor
        ↓
Polish & Stability
        ↓
Long-Term Minimal Maintenance
```

The strategic recommendation is:

> Keep the product aggressively small.

The defining product characteristic is not features — it is predictability and absence of complexity.

