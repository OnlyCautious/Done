# CLAUDE.md — Done

Instructions persistantes pour ce projet. Lu automatiquement au début de chaque session Claude Code.

> Note de reconstruction : le fichier original était en réalité du RTF brut sauvegardé avec l'extension `.md` (illisible tel quel comme markdown). Reconstruit ici en markdown propre, contenu identique.

## Le projet en une phrase

Done est une app macOS de whiteboard/moodboard créative (inspirée de Milanote), 100% locale, avec un canvas infini pour organiser des idées de projets.
Pour le détail complet des fonctionnalités et de la roadmap : voir SPEC.md. Pour les bugs et corrections en cours : voir BUGS.md.

## Stack & architecture (décisions verrouillées)

- **SwiftUI** uniquement pour l'app shell et les panneaux. Un `Canvas`/`NSView` custom pour le rendu du canvas infini si nécessaire pour la performance — pas d'AppKit ailleurs sauf demande explicite.
- **SwiftData** pour les métadonnées (board, nodes, positions, connexions).
- **Assets (images) stockés séparément** dans un dossier `assets/` à l'intérieur du document package du board, référencés par chemin relatif — jamais en base64 ou embarqués dans SwiftData.
- **UndoManager** : toute action (créer, déplacer, redimensionner, supprimer) doit être undoable dès son implémentation, pas ajouté après coup.
- **Handles UI** (resize, sélection) : toujours à taille fixe à l'écran, jamais scalés avec le zoom du canvas.

## Build & workflow

- Build via Xcode (⌘B), pas de commande CLI configurée pour l'instant.
- **Committer après chaque item/fonctionnalité terminé**, jamais en un seul gros commit à la fin.
- **Pousser (`git push`) chaque commit vers `origin/main` immédiatement après l'avoir créé** — ne jamais laisser de commits seulement locaux entre deux sessions, pour éviter de reperdre du travail si la copie de travail est à nouveau perdue.
- Après chaque item significatif, **expliquer brièvement ce qui a été fait et pourquoi** avant de passer au suivant.
- Ne jamais implémenter une fonctionnalité de la roadmap qui est hors du scope explicitement demandé dans le prompt en cours.

## Conventions de code

- Noms de variables, commentaires et code en anglais (convention Swift standard), même si les échanges avec l'utilisateur se font en français.
- Un type de Node par fichier (`TextNote.swift`, `ImageNode.swift`, etc.) plutôt que tout regrouper dans un seul fichier de modèles.

## Comportements UI à respecter systématiquement

- Trackpad : pan au glissement 2 doigts, zoom au pincement (pas de scroll vertical pour zoomer).
- Souris : pan au clic-molette + glisser.
- Dark mode et light mode toujours supportés en parallèle, jamais l'un au détriment de l'autre.

## Glossaire

Chaque nouvel outil, geste, ou élément UI introduisant un concept nommable doit être ajouté à GLOSSARY.md à la racine du projet (nom en gras + description en une phrase), dans la section appropriée, au moment où il est implémenté — pas après coup.

## Si une règle est apprise en cours de route

Si l'utilisateur corrige quelque chose qui devrait s'appliquer à toutes les sessions futures, l'ajouter directement dans ce fichier plutôt que de le laisser seulement dans la conversation.

## Si l'utilisateur utilise : ## Vague "X"

Si l'utilisateur utilise "## Vague "X"" — introduire ce prompt dans BUGS.md (moyen de log les différents patch pour garder en mémoire ce qui a été fait).
