# DONE

A local-first macOS whiteboard/moodboard app for organizing creative project ideas on an infinite canvas — inspired by Milanote, built without the subscription.

*[Français ci-dessous ↓](#done-français)*

---

## English

### What it is

DONE lets you drop text notes, images, shapes, and arrows onto an infinite pannable, zoomable canvas — a lightweight local alternative to Milanote for planning creative/video projects. No account, no cloud dependency, no clutter: everything lives in a document package on disk.

### Core principles

- **Local-first** — works fully offline, nothing leaves the machine
- **Minimal UI** — blank-slate canvas, Apple-style visual language, light and dark mode both fully supported
- **Undoable by design** — every action (create, move, resize, delete) is wired into `UndoManager` from the moment it's built, not retrofitted later

### Tech stack

- **SwiftUI** for the app shell and panels
- **SwiftData** for board structure (nodes, positions, connections)
- Image assets stored separately in an `assets/` folder inside the board's document package, referenced by relative path — never embedded as base64
- macOS only, for now

### Features

- Infinite pan/zoom canvas with a Grid Attach snap option
- **Text Notes** — create, edit, move, resize
- **Image Nodes** — drag in from Finder, move, resize, an independent Crop-Resize mode, and a dedicated Crop Tool
- **Shape Nodes** — rectangles and ellipses with embedded text
- **Arrow Tool** — straight or curved (quadratic Bézier) arrows, solid/dashed stroke with adjustable width via the Arrow Style Panel, and persistent Arrow Connections that let one arrow's endpoint follow another node as it moves
- Marquee and Cmd-click multi-selection, group dragging, cursor-anchored zoom, Fit to Screen

### Repository structure

This repository preserves the project's build history across coding sessions, since the live working copy was lost between sessions and had to be reconstructed from conversation history each time:

- **`Recovery Session 1/`** — the app's baseline: infinite canvas, text notes, image nodes, shape nodes, Crop Tool
- **`Recovery Session 2/`** — everything from Session 1, plus the Arrow Tool (steps 1–5 of its roadmap), a rewritten "cover"-formula Crop-Resize, and a handful of crash/UX fixes

Each `Recovery Session N/` folder is a complete, standalone Xcode project (`DONE.xcodeproj` + `DONE/` source tree) — open either one directly in Xcode.

- `BUGS.md` — running log of bugs found and fixed, in the order they came up
- `GLOSSARY.md` — canonical name + one-line description for every tool, gesture, and UI concept introduced
- `SPEC.md` — the original project brief and feature roadmap
- `CLAUDE.md` — persistent working conventions for AI-assisted coding sessions on this project

### Known gap

The custom app icon (an Icon Composer `.icon` package with light/dark layers) built during Session 2 could not be recovered when the working copy was lost — it will need to be re-added manually from a backup or rebuilt in Icon Composer.

---

## DONE (Français)

### Ce que c'est

DONE permet de déposer des notes texte, des images, des formes et des flèches sur un canvas infini, pannable et zoomable — une alternative locale et légère à Milanote pour planifier des projets créatifs/vidéo. Pas de compte, pas de dépendance au cloud, pas d'encombrement : tout vit dans un document package sur le disque.

### Principes fondamentaux

- **100% local** — fonctionne entièrement hors ligne, rien ne quitte la machine
- **UI minimale** — canvas vierge, langage visuel à l'Apple, dark mode et light mode tous deux pleinement supportés
- **Undoable par conception** — chaque action (créer, déplacer, redimensionner, supprimer) est câblée à l'`UndoManager` dès son implémentation, jamais ajoutée après coup

### Stack technique

- **SwiftUI** pour l'app shell et les panneaux
- **SwiftData** pour la structure du board (nodes, positions, connexions)
- Les assets images sont stockés séparément dans un dossier `assets/` à l'intérieur du document package du board, référencés par chemin relatif — jamais en base64
- macOS uniquement, pour l'instant

### Fonctionnalités

- Canvas infini avec pan/zoom, et une option d'accroche à la grille (Grid Attach)
- **Text Notes** — création, édition, déplacement
- **Image Nodes** — glisser-déposer depuis le Finder, déplacement, redimensionnement, un mode Crop-Resize indépendant, et un Crop Tool dédié
- **Shape Nodes** — rectangles et ellipses avec texte intégré
- **Arrow Tool** — flèches droites ou courbées (Bézier quadratique), trait plein ou pointillé avec largeur ajustable via l'Arrow Style Panel, et des Arrow Connections persistantes permettant à l'extrémité d'une flèche de suivre un autre node lorsqu'il se déplace
- Sélection multiple (marquee ou Cmd-clic), déplacement de groupe, zoom ancré sur le curseur, Fit to Screen

### Structure du dépôt

Ce dépôt conserve l'historique de développement du projet à travers les sessions de code, la copie de travail active ayant été perdue entre les sessions et ayant dû être reconstruite à chaque fois à partir de l'historique de conversation :

- **`Recovery Session 1/`** — la base de l'app : canvas infini, notes texte, image nodes, shape nodes, Crop Tool
- **`Recovery Session 2/`** — tout ce qui vient de la Session 1, plus l'Arrow Tool (étapes 1 à 5 de sa roadmap), un Crop-Resize réécrit selon la formule "cover", et plusieurs correctifs de crash/UX

Chaque dossier `Recovery Session N/` est un projet Xcode complet et autonome (`DONE.xcodeproj` + arborescence `DONE/`) — ouvrez l'un ou l'autre directement dans Xcode.

- `BUGS.md` — journal des bugs trouvés et corrigés, dans l'ordre chronologique
- `GLOSSARY.md` — nom canonique + description en une phrase pour chaque outil, geste et concept UI introduit
- `SPEC.md` — le brief de projet original et la roadmap des fonctionnalités
- `CLAUDE.md` — conventions de travail persistantes pour les sessions de code assistées par IA sur ce projet

### Manque connu

L'icône d'app personnalisée (un package Icon Composer `.icon` avec des calques light/dark) construite durant la Session 2 n'a pas pu être récupérée lors de la perte de la copie de travail — elle devra être réajoutée manuellement depuis une sauvegarde, ou reconstruite dans Icon Composer.
