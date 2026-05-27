# Product Requirements Document (PRD)

## Minimal Native macOS Notepad Application

---

# 1. Product Summary

## Product Overview

A lightweight native macOS text editor designed for fast, frictionless plain-text editing. The application behaves similarly to a traditional notepad utility:

* Launches instantly into an empty editor
* Opens arbitrary files directly from disk
* Allows quick editing and explicit saving
* Maintains a minimal native macOS experience
* Avoids advanced editor complexity

The product intentionally prioritizes simplicity and predictability over extensibility or feature richness.

---

## Core Value Proposition

> “A minimal native macOS notepad that opens anything and gets out of your way.”

Key differentiators:

* Extremely fast launch and interaction
* Minimal cognitive overhead
* Native macOS behavior and shortcuts
* Direct filesystem editing without abstraction
* No accounts, cloud services, or telemetry

---

## Problem Statement

Existing text editors on macOS often fail quick-edit workflows because they are:

* Heavyweight
* Developer-centric
* Rich-text oriented
* Configuration-heavy
* Multi-window/tab focused
* Slow to launch for simple tasks

Users need a lightweight fallback editor for inspecting and editing arbitrary files quickly without workflow friction.

---

## Target Users

### Primary Users

| User Type               | Needs                                  |
| ----------------------- | -------------------------------------- |
| Developers              | Quickly inspect logs, configs, scripts |
| Power users             | Lightweight fallback editor            |
| General macOS users     | Simple text editing                    |
| Technical support users | Open unknown text files rapidly        |

---

# 2. Goals & Non-Goals

## Product Goals

### User Goals

* Open and edit files with minimal friction
* Perform quick edits without setup/configuration
* Use familiar native macOS behaviors
* Reliably save changes manually
* Open arbitrary file types without restriction

### Business/Product Goals

* Maintain extremely low maintenance overhead
* Keep architecture intentionally simple
* Preserve predictable UX behavior
* Avoid long-term feature creep
* Deliver stable native performance

---

## Non-Goals

The following are explicitly out of scope:

| Feature                 | Reason Excluded                     |
| ----------------------- | ----------------------------------- |
| Tabs                    | Increases state complexity          |
| Multiple windows        | Violates single-document simplicity |
| Autosave                | Reduces predictability              |
| Crash recovery          | Adds hidden persistence complexity  |
| Syntax highlighting     | Moves product toward IDE territory  |
| Rich text formatting    | Product is plain-text only          |
| Plugins/extensions      | Increases maintenance burden        |
| Collaboration           | Requires backend complexity         |
| Cloud sync              | Violates local-only philosophy      |
| Encoding picker         | Adds UX complexity                  |
| Regex search            | Increases implementation complexity |
| Hex/binary editing mode | Outside plain-text scope            |
| Session restoration     | Conflicts with minimal lifecycle    |

---

# 3. Personas

## Persona 1 — Developer “Alex”

### Profile

* Experienced macOS developer
* Frequently edits logs/configs/scripts
* Uses heavyweight IDEs for coding

### Behaviors

* Opens random filesystem files rapidly
* Uses keyboard shortcuts extensively
* Expects native macOS interactions

### Pain Points

* Existing editors launch slowly
* IDEs are excessive for quick edits
* Rich editors distract from simple tasks

### Motivations

* Speed
* Predictability
* Minimal UI friction

---

## Persona 2 — Power User “Sam”

### Profile

* Technical but non-developer
* Frequently edits exported data/text files

### Behaviors

* Uses drag-and-drop workflows
* Wants familiar desktop interactions

### Pain Points

* Many editors feel cluttered
* Complex applications are intimidating

### Motivations

* Simplicity
* Reliability
* Familiar behavior

---

## Persona 3 — Casual User “Taylor”

### Profile

* Needs occasional text editing
* Opens README, TXT, or unknown files

### Behaviors

* Uses menus over shortcuts
* Expects native dialogs

### Pain Points

* Confusing editor terminology
* Too many formatting features

### Motivations

* Clear workflows
* Low learning curve

---

# 4. User Problems & Jobs-To-Be-Done

## Core User Problems

| Problem                                   | Product Response                |
| ----------------------------------------- | ------------------------------- |
| Need to quickly edit arbitrary files      | Fast lightweight editor         |
| Existing editors are too complex          | Minimal UX and feature set      |
| Unknown file types may not open elsewhere | Open-anything philosophy        |
| Rich editors are slow to launch           | Native lightweight architecture |
| Users want predictable save behavior      | Explicit manual save model      |

---

## Jobs-To-Be-Done (JTBD)

### JTBD 1 — Quick Edit

> “When I need to quickly inspect or modify a file, I want an editor that opens immediately so I can make changes without distraction.”

### JTBD 2 — Arbitrary File Access

> “When I encounter an unknown file type, I want to open it anyway so I can inspect or edit its contents.”

### JTBD 3 — Predictable Saving

> “When editing a file, I want explicit save control so I know exactly when changes are persisted.”

### JTBD 4 — Native Desktop Workflow

> “When using a macOS application, I want standard shortcuts and dialogs so the app behaves predictably.”

---

# 5. Core User Flows

## Flow 1 — Launch Application

### Entry Points

* Dock icon
* Finder launch
* Spotlight
* Terminal `open`

### User Journey

1. User launches app
2. Single empty editor window appears
3. No file loaded initially
4. Cursor focused in editor

### Acceptance Expectations

* Startup under 1 second on modern hardware
* No startup dialogs
* No onboarding or templates

### Edge Cases

| Scenario                                    | Expected Behavior         |
| ------------------------------------------- | ------------------------- |
| Previous unsaved state existed before crash | Do not recover            |
| Launch without permissions                  | macOS handles permissions |

---

## Flow 2 — Open Existing File

### Entry Points

* Cmd+O
* File → Open
* Drag-and-drop

### User Journey

1. User selects file
2. App validates target
3. File bytes loaded
4. Encoding detection attempted
5. Content rendered
6. File becomes active document

### Decision Points

| Condition                   | Behavior                |
| --------------------------- | ----------------------- |
| Encoding detection succeeds | Use detected encoding   |
| Detection fails             | Fallback to UTF-8       |
| File is directory           | Reject                  |
| File inaccessible           | Show error              |
| File is binary              | Render interpreted text |

### Edge Cases

| Edge Case            | Behavior                                  |
| -------------------- | ----------------------------------------- |
| Multiple drag files  | Open first only                           |
| Symlink/alias        | Resolve target                            |
| Network path         | Allowed                                   |
| Extremely large file | Attempt open even if performance degrades |

---

## Flow 3 — Edit and Save

### User Journey

1. User modifies text
2. Document enters dirty state
3. UI indicates unsaved changes
4. User selects Save
5. File overwritten directly
6. Dirty state cleared

### Decision Points

| Condition               | Behavior           |
| ----------------------- | ------------------ |
| Save succeeds           | Clear dirty state  |
| Save fails              | Show error         |
| File removed externally | Save failure shown |

### Edge Cases

| Edge Case           | Behavior     |
| ------------------- | ------------ |
| Disk full           | Save error   |
| Permissions changed | Save error   |
| Invalid destination | Prevent save |

---

## Flow 4 — Save New File

### User Journey

1. User creates new document
2. User edits content
3. User selects Save
4. Native Save As dialog appears
5. User selects destination
6. File saved as UTF-8
7. Document becomes associated with path

### Edge Cases

| Edge Case               | Behavior                            |
| ----------------------- | ----------------------------------- |
| User cancels dialog     | Remain unsaved                      |
| Existing file overwrite | Native macOS overwrite confirmation |

---

## Flow 5 — Quit With Unsaved Changes

### User Journey

1. User attempts quit
2. Dirty-state validation occurs
3. Confirmation dialog appears:

   * Save
   * Don’t Save
   * Cancel
4. User selection executed immediately

### Decision Matrix

| Action     | Result           |
| ---------- | ---------------- |
| Save       | Save then quit   |
| Don’t Save | Quit immediately |
| Cancel     | Abort quit       |

### Edge Cases

| Edge Case              | Behavior         |
| ---------------------- | ---------------- |
| Save fails during quit | Quit canceled    |
| No unsaved changes     | Quit immediately |

---

# 6. Functional Requirements

## Module: Editor Window

| ID   | Requirement                                 | Acceptance Criteria                     | Edge Cases                                                           |
| ---- | ------------------------------------------- | --------------------------------------- | -------------------------------------------------------------------- |
| EW-1 | App shall use single-window architecture    | Only one editor window exists at a time | Opening additional files replaces current document after dirty check |
| EW-2 | App shall launch into empty editor          | Blank editable area visible on launch   | None                                                                 |
| EW-3 | App shall support native keyboard shortcuts | Cmd+O, Cmd+S, Cmd+Q functional          | Shortcut conflicts defer to macOS                                    |

---

## Module: File Operations

| ID   | Requirement                        | Acceptance Criteria            | Edge Cases                             |
| ---- | ---------------------------------- | ------------------------------ | -------------------------------------- |
| FO-1 | User can open arbitrary files      | Any filesystem file selectable | Binary files may render poorly         |
| FO-2 | User can drag-and-drop files       | Dropped file loads into editor | Multiple files open first only         |
| FO-3 | App shall reject directories       | Error shown for folders        | Symlink resolving to folder rejected   |
| FO-4 | App shall resolve aliases/symlinks | Target file opened             | Broken symlink shows error             |
| FO-5 | User can save current document     | File overwritten directly      | Save failures preserve dirty state     |
| FO-6 | User can Save As                   | Native save dialog appears     | Canceled dialog leaves state unchanged |
| FO-7 | New files save as UTF-8            | Persisted file encoded UTF-8   | None                                   |

---

## Module: Editing

| ID   | Requirement                  | Acceptance Criteria                | Edge Cases                     |
| ---- | ---------------------------- | ---------------------------------- | ------------------------------ |
| ED-1 | Plain text editing supported | User can insert/delete text        | Large files may slow           |
| ED-2 | Undo/redo supported          | Native undo stack functional       | Stack cleared on reopen        |
| ED-3 | Copy/paste supported         | Native clipboard behavior works    | Rich text pasted as plain text |
| ED-4 | Text selection supported     | Native selection interactions work | None                           |

---

## Module: Search & Replace

| ID   | Requirement                         | Acceptance Criteria            | Edge Cases                                 |
| ---- | ----------------------------------- | ------------------------------ | ------------------------------------------ |
| SR-1 | User can search text                | Find dialog available          | Empty query disabled                       |
| SR-2 | Incremental search supported        | Matches update during typing   | Large files may slow                       |
| SR-3 | Replace single occurrence supported | Current match replaced         | No match shows no-op                       |
| SR-4 | Replace all supported               | All exact matches replaced     | Large operations may freeze UI temporarily |
| SR-5 | Regex unsupported                   | Regex syntax treated literally | None                                       |

---

## Module: Dirty State

| ID   | Requirement                           | Acceptance Criteria                        | Edge Cases                                 |
| ---- | ------------------------------------- | ------------------------------------------ | ------------------------------------------ |
| DS-1 | App tracks unsaved changes            | Dirty indicator updates after modification | Undo back to saved state clears dirty flag |
| DS-2 | Quit prompts on dirty state           | Confirmation dialog shown                  | Save failure prevents quit                 |
| DS-3 | Opening another file prompts if dirty | User prompted before replacing document    | Cancel aborts open                         |

---

## Module: Encoding

| ID   | Requirement                     | Acceptance Criteria                  | Edge Cases                   |
| ---- | ------------------------------- | ------------------------------------ | ---------------------------- |
| EN-1 | App attempts encoding detection | Detected encoding used if successful | Partial detection acceptable |
| EN-2 | UTF-8 fallback used silently    | File still opens                     | Gibberish possible           |
| EN-3 | No encoding picker shown        | No user-facing encoding controls     | None                         |

---

## Module: Error Handling

| ID   | Requirement                   | Acceptance Criteria                | Edge Cases                                           |
| ---- | ----------------------------- | ---------------------------------- | ---------------------------------------------------- |
| ER-1 | Invalid files show errors     | User notified with native alert    | None                                                 |
| ER-2 | Save failures show errors     | Dirty state preserved              | Disk disconnected                                    |
| ER-3 | Invalid drop targets rejected | Unsupported items ignored/rejected | Mixed valid/invalid drops open first valid file only |

---

# 7. UX & Interaction Requirements

## General UX Principles

* Native macOS behavior first
* Minimal visual chrome
* No onboarding
* No modal interruptions unless destructive

---

## UI Requirements

| Area          | Requirement                   |
| ------------- | ----------------------------- |
| Window        | Single document window only   |
| Toolbar       | Minimal or optional           |
| Menus         | Native macOS menu conventions |
| Editor        | Focused immediately on launch |
| Dialogs       | Use native macOS dialogs      |
| Drag-and-drop | Visual drop feedback required |

---

## Dirty State UI

| State        | UI Behavior                   |
| ------------ | ----------------------------- |
| Clean        | Standard title                |
| Dirty        | macOS unsaved indicator shown |
| Save success | Indicator cleared             |

---

## Empty States

| Scenario          | UI                           |
| ----------------- | ---------------------------- |
| Fresh launch      | Blank editor                 |
| Empty file        | Editable blank state         |
| No search results | Inline “No Matches” feedback |

---

## Error States

| Scenario       | UX Behavior          |
| -------------- | -------------------- |
| Save failed    | Blocking alert       |
| Invalid file   | Error alert          |
| Folder dropped | Reject with feedback |

---

## Interaction Requirements

| Interaction           | Requirement                                 |
| --------------------- | ------------------------------------------- |
| Cmd+F                 | Opens find UI                               |
| Cmd+H                 | Standard macOS behavior                     |
| Cmd+W                 | Close behavior mapped to app lifecycle      |
| Drag file into window | Replaces current document after dirty check |

---

# 8. Data & System Constraints

## Architectural Constraints

| Constraint                  | Product Impact               |
| --------------------------- | ---------------------------- |
| Entire file loaded into RAM | Huge files may freeze        |
| Single-document model       | No tabs/multi-file workflows |
| Direct overwrite saves      | Potential corruption risk    |
| No autosave                 | User responsible for saving  |
| No recovery                 | Crashes lose unsaved work    |
| Local-only architecture     | No sync/collaboration        |

---

## Platform Constraints

| Constraint                  | Product Impact                      |
| --------------------------- | ----------------------------------- |
| macOS-native only           | No Windows/Linux support            |
| AppKit/TextKit 1 dependency | Stable editing behavior prioritized |
| No sandboxing               | Full filesystem access enabled      |

---

## Encoding Constraints

| Constraint                   | Product Impact                     |
| ---------------------------- | ---------------------------------- |
| UTF-8 fallback only          | Some files may display incorrectly |
| No manual encoding selection | Simpler UX but less control        |

---

# 9. Success Metrics

## Adoption Metrics

| Metric                | Target    |
| --------------------- | --------- |
| Successful file opens | >95%      |
| Startup time          | <1 second |
| Crash-free sessions   | >99%      |

---

## Engagement Metrics

| Metric               | Target                |
| -------------------- | --------------------- |
| Save completion rate | >90%                  |
| Search usage rate    | Track usage frequency |
| Drag-and-drop usage  | Track adoption        |

---

## Behavioral Metrics

| Metric                            | Target                     |
| --------------------------------- | -------------------------- |
| Average time-to-edit after launch | <3 seconds                 |
| Failed save rate                  | <1%                        |
| Quit-cancel after dirty prompt    | Measured for UX validation |

---

## Product Philosophy Metrics

| Metric                        | Goal                  |
| ----------------------------- | --------------------- |
| Feature count growth          | Minimal over time     |
| Binary size                   | Keep small            |
| Launch performance regression | Prevent over releases |

---

# 10. Edge Cases & Failure Scenarios

## File Handling

| Scenario                 | Expected Behavior             |
| ------------------------ | ----------------------------- |
| Binary file opened       | Render interpreted text       |
| Huge file                | Attempt open despite slowdown |
| Broken symlink           | Error                         |
| Network drive disconnect | Save/open error               |

---

## Persistence Failures

| Scenario                | Expected Behavior    |
| ----------------------- | -------------------- |
| Disk full               | Save error           |
| Permissions revoked     | Save error           |
| File deleted externally | Save failure         |
| App crash               | Unsaved changes lost |

---

## User Misuse

| Scenario              | Expected Behavior     |
| --------------------- | --------------------- |
| User edits binary     | Allowed               |
| User drops folder     | Rejected              |
| User expects autosave | No hidden persistence |

---

## Performance Risks

| Scenario                 | Expected Behavior              |
| ------------------------ | ------------------------------ |
| Massive replace-all      | Potential UI freeze acceptable |
| Large incremental search | Slower response acceptable     |

---

# 11. Open Questions & Assumptions

## Open Questions

| Topic                 | Question                                                   |
| --------------------- | ---------------------------------------------------------- |
| File size behavior    | Should warning thresholds exist for extremely large files? |
| Binary heuristics     | Should obvious binaries display warning banner?            |
| Toolbar               | Should toolbar be visible by default?                      |
| Save verification     | How should partial write failures be surfaced?             |
| External file changes | Should external modification detection exist?              |

---

## Assumptions

| Assumption                                       | Impact                    |
| ------------------------------------------------ | ------------------------- |
| Users understand manual save workflows           | No autosave UX needed     |
| Native macOS text system handles most edge cases | Avoid custom rendering    |
| Product intentionally rejects advanced workflows | Reduced roadmap pressure  |
| Direct overwrite risk is acceptable              | Simpler persistence layer |

---

# 12. Future Considerations

The product strategy favors stability over expansion.

Potential future considerations (not commitments):

| Area                   | Potential Evolution               |
| ---------------------- | --------------------------------- |
| Performance            | Better handling for huge files    |
| Stability              | Improved save robustness          |
| Native polish          | Enhanced macOS integration        |
| Accessibility          | Additional VoiceOver optimization |
| External file watching | Detect filesystem changes         |

---

# Critical Review

## Missing Requirements

| Area                  | Missing Detail                                         |
| --------------------- | ------------------------------------------------------ |
| Accessibility         | No explicit VoiceOver/keyboard navigation requirements |
| Internationalization  | No localization expectations defined                   |
| File change detection | Behavior undefined if file changes externally          |
| Search UI             | Exact UI pattern unspecified                           |
| Window restoration    | Relaunch behavior not explicitly defined               |
| Clipboard handling    | Plain-text sanitization rules unspecified              |
| File permissions      | Detailed permission failure UX undefined               |

---

## Ambiguities

| Topic                       | Ambiguity                                   |
| --------------------------- | ------------------------------------------- |
| Encoding detection strategy | Detection library/mechanism unspecified     |
| Large-file threshold        | “Very large” undefined                      |
| Save verification           | Degree of verification unclear              |
| Binary rendering            | No definition of “render whatever possible” |
| Dirty tracking              | Whether whitespace-only changes count       |
| Replace-all UX              | Whether operation is cancelable             |

---

## Potential Implementation Risks

| Risk                         | Impact                                         |
| ---------------------------- | ---------------------------------------------- |
| Large-file memory exhaustion | App freeze/crash                               |
| Direct overwrite saves       | Potential file corruption                      |
| UTF-8 fallback               | Incorrect rendering/data corruption perception |
| Binary file rendering        | NSTextView performance degradation             |
| Lack of recovery system      | User frustration after crashes                 |
| Single-window model          | Users may perceive app as too limited          |
| Native API evolution         | macOS updates may affect behavior              |
| Network file editing         | Increased save/open failure conditions         |
| No sandboxing                | Distribution/security review concerns          |
