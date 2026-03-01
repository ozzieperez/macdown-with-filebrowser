# File Browser Sidebar — Design Document

**Date:** 2026-03-01
**Status:** Approved

## Overview

Add an embedded, collapsible file browser sidebar to MacDown's document windows. The sidebar displays a hierarchical tree of files from a user-selected root folder, allowing users to browse and open markdown files as tabs, and create new markdown files inline.

## Architecture

### New Classes

| Class | Type | Role |
|---|---|---|
| `MPFileBrowserController` | `NSViewController` | Owns the `NSOutlineView`, manages file tree data source/delegate, handles file operations (open, create new) |
| `MPFileNode` | `NSObject` | Model: represents a file/folder. Properties: `url`, `name`, `isDirectory`, `children` (lazy-loaded), `isMarkdown` |

### Modified Classes

| Class | Changes |
|---|---|
| `MPDocument` | Add outer `NSSplitView` wrapping existing editor/preview split. Add IBOutlets for sidebar container. Add toggle action. Wire up `MPFileBrowserController`. Set `NSWindow.tabbingMode = NSWindowTabbingModePreferred`. |
| `MPPreferences` | Add `BOOL fileBrowserVisible`, `NSString *fileBrowserRootPath` properties |
| `MPDocument.xib` | Restructure: outer NSSplitView → [sidebar | existing MPDocumentSplitView] |
| `MPMainController` | Add menu items: View > Toggle File Browser (Cmd+Shift+B), File > Open Folder... (Cmd+Shift+O) |
| `MPToolbarController` | Add "Toggle Sidebar" toolbar button |
| `MainMenu.xib` | Add menu items |

### Window Layout

```
┌─────────────────────────────────────────────────┐
│  MacDown Window                                  │
│  ┌────────────┬──────────────────────────────┐   │
│  │File Browser│  ┌──────────┬─────────────┐  │   │
│  │(collapsible│  │  Editor  │   Preview   │  │   │
│  │  sidebar)  │  │          │             │  │   │
│  │            │  │          │             │  │   │
│  │  tree/     │  │          │             │  │   │
│  │  outline   │  │          │             │  │   │
│  │  view      │  │          │             │  │   │
│  │            │  └──────────┴─────────────┘  │   │
│  └────────────┴──────────────────────────────┘   │
└─────────────────────────────────────────────────┘
      ↑ Outer NSSplitView        ↑ Existing inner split
```

## File Browser UI

### Tree View
- `NSOutlineView` with source list selection highlight style
- Folders show disclosure triangles, expandable/collapsible
- File icons via `NSWorkspace.icon(forFile:)`
- Non-markdown files: visible but grayed out, non-selectable
- Markdown extensions: `.md`, `.markdown`, `.mdown`, `.mkd`, `.mkdn`, `.mdwn`, `.text`, `.txt`

### Sidebar Toolbar
- "Open Folder" button (folder icon) — opens `NSOpenPanel` in directory mode
- "New File" button (`+` icon) — creates new `.md` in selected folder
- Current folder path breadcrumb label

### Context Menu
- Folder: "New Markdown File Here", "Reveal in Finder"
- File: "Open", "Reveal in Finder", "Delete" (with confirmation)

### File Watching
- FSEvents to watch root folder for external changes
- Auto-refresh tree on add/remove/rename

### New File Creation
1. Right-click folder → "New Markdown File Here"
2. Inline editable text field appears in outline view
3. `.md` extension auto-appended if not provided
4. File created on disk, tree refreshes, file opens as new tab

## Tab Integration

- `NSWindow.tabbingMode = NSWindowTabbingModePreferred` for automatic tab grouping
- Before opening: check `[[NSDocumentController sharedDocumentController] documentForURL:]` to prevent duplicates
- If already open, bring existing tab to front

## Sidebar State

- Root folder path: shared across all windows (in `MPPreferences`)
- Root folder change: post notification so all windows update
- Collapse state: per-window
- Sidebar width: shared (in `MPPreferences`)

## Menu & Keyboard Shortcuts

| Menu | Item | Shortcut |
|---|---|---|
| View | Toggle File Browser | Cmd+Shift+B |
| File | Open Folder... | Cmd+Shift+O |

## Edge Cases

- **No folder selected:** Show centered "Open Folder" button with drag-drop support
- **Folder deleted externally:** FSEvents detects, show "Folder not found" with re-select option
- **Permission denied:** Gray out with lock icon
- **Large directories:** Lazy-load children on expand
- **Unsaved changes:** Handled by macOS document architecture natively
- **File renamed externally:** FSEvents updates tree; NSDocument file presenter handles open documents

## Out of Scope (YAGNI)

- Drag-and-drop reordering
- File renaming from sidebar
- Multi-file selection
- Search/filter within browser
- Favorites/bookmarks
- Recent folders list
