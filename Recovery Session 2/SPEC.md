# Done — Project Brief & Build Spec

A living reference doc. Update it as decisions get made; paste the relevant sections into new Claude Code sessions instead of re-explaining the app from scratch.

## What this is

Done is a macOS whiteboard/moodboard app for laying out creative project ideas on an infinite canvas — inspired by Milanote, built for a video production workflow. Local-first, no subscription, no clutter.

## Core principles

- Local-first: everything works offline, no account, no internet dependency
- Minimal UI: blank-slate canvas, Apple-style visual language
- Dark & light mode, both fully supported from the start

## Why this exists

Milanote is subscription-based. ClickUp was tried as an alternative but its UI feels busy/cluttered compared to Milanote's polish. Done aims for Milanote's simplicity without the subscription, owned locally, with iCloud sync as a later addition for iPhone pairing.

## Tech decisions (locked)

- SwiftUI for the app shell and panels; a `Canvas`/`NSView`-backed layer for the infinite board itself (performance with many objects)
- SwiftData for board structure (nodes, positions, connections); image/asset files stored separately in an app-managed folder, referenced by relative path — the board is a document package (folder), not one flat file. This keeps a clean path to iCloud/CloudKit sync later.
- UndoManager wired in from the first feature, not retrofitted later — every action (create/move/resize/delete) should be an undoable command
- Git, initialized before any code was written; commit after each working milestone

## MVP scope — Phase 1

1. Infinite pannable, zoomable canvas
2. Text notes: create, move, edit, delete
3. Images: drag in from Finder, move, resize, delete (crop comes later)
4. Save/load a board to local disk (the document package format above)
5. Light/dark mode, following system appearance
6. Undo/redo for all of the above

Explicitly not in Phase 1: arrows, shapes, drawing tools, color palette tool, hyperlinks/embeds, custom font picker, iCloud.

## Full feature roadmap (post-MVP, build order)

1. Shapes with embedded text
2. Arrows — straight & curved, dotted/solid, variable width slider
3. Local font picker (any installed font)
4. Color palette tool — circle/rectangle swatches, RGB/HEX toggle
5. Image captions — double-click adds a text box glued to the bottom
6. Hyperlinks + embedded YouTube video support (likely via `WKWebView`)
7. Drawing tool — 3 pen styles (Marker/Pastel/Pen), color + width
8. Floating bottom toolbar with drop shadow (UI chrome pass)
9. iCloud sync, paired iPhone use (separate phase, after local version is stable)

## Data model sketch

```
Board
  id, name, createdAt
  nodes: [Node]

Node (base)
  id, position (x, y), size, zIndex

TextNote: Node + content, font, color
ImageNode: Node + assetPath, cropRect
// more Node subtypes added as each feature is built
```

## Design tokens

To fill in after the Figma / Claude Design pass — reference these by name in future prompts instead of re-describing the look each time.

- Corner radius:
- Spacing scale:
- Colors (light):
- Colors (dark):
- Fonts:
- Toolbar shadow:
