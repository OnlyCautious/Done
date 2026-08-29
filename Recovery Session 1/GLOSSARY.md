# GLOSSARY.md — Done

Référence des noms officiels pour les outils, fonctionnalités et éléments UI du projet. Utilisé de manière cohérente dans les conversations, les specs, et les fichiers de bugs.

## Canvas & Navigation

- **Infinite Canvas** : la zone de travail principale, pannable et zoomable sans limite fixe, sur laquelle tous les éléments sont posés.
- **Proportional Canvas** : comportement qui ajuste dynamiquement les marges/limites de dézoom en fonction de la zone réellement occupée par le contenu, plutôt qu'un espace infini fixe et disproportionné.
- **Cursor-anchored Zoom** : le zoom/dézoom se fait en gardant fixe le point du canvas sous le curseur, plutôt que le centre de la fenêtre.
- **Fit to Screen** : action qui recadre automatiquement la vue pour englober tout le contenu du board à l'écran.
- **Grid Attach** : magnétisme qui aligne un élément déplacé sur une grille en pointillés lorsque Shift est maintenu.

## Éléments UI

- **Zoom Capsule** : l'indicateur flottant affichant le pourcentage de zoom actuel ; un double-clic dessus déclenche le Fit to Screen.
- **Floating Toolbar** : la barre d'outils flottante en bas de l'écran, avec ombre portée, donnant accès aux outils de création.
- **Selection Tool** : le mode par défaut du canvas (clic/glisser/Marquee Selection habituels), actif tant qu'aucun outil de création n'est armé depuis la Floating Toolbar.
- **Resize Handle** : le point de saisie unique (bas-droite) permettant de redimensionner un élément sélectionné, à taille fixe quel que soit le zoom.
- **Selection Highlight** : le contour affiché autour d'un élément sélectionné sur le canvas.
- **Marquee Selection** : rectangle de sélection tracé par clic-glisser sur une zone vide du canvas, qui met en Selection Highlight tous les Nodes qu'il recouvre au relâchement.
- **Crop-Resize** : ⌘+glisser sur le Resize Handle d'un Image Node — redimensionne le cadre visible sans changer l'échelle du contenu, révélant ou masquant une partie de l'image.
- **Crop Tool** : mode d'édition de recadrage activé par double-clic sur un Image Node déjà sélectionné — affiche l'image source entière, zone hors-cadre assombrie et floutée, 8 poignées (coins + bords), pan interne, grille des tiers pendant l'ajustement, validation via Cancel/Save.

## Éléments du canvas (Nodes)

- **Node** : terme générique pour tout élément posé sur le canvas (texte, image, forme, etc.).
- **Text Note** : un node de texte libre, éditable, avec largeur redimensionnable.
- **Image Node** : un node contenant une image importée, redimensionnable (et à terme recadrable).
- **Caption Box** : la zone de texte qui s'accroche au bas d'une image pour la décrire, ajoutée au double-clic.
- **Shape Node** : un node créé via le Shape Tool (rectangle ou ellipse), avec texte intégré éditable et un Resize Handle.

## Outils (roadmap)

- **Shape Tool** : outil de création de formes avec texte intégré.
- **Arrow Tool** : outil de création de flèches droites ou courbes, personnalisables (style, épaisseur).
- **Color Palette Tool** : outil de sélection de couleur affichée en pastille ronde ou rectangle, avec bascule d'affichage RVB/HEX.
- **Drawing Tool** : outil de dessin libre avec 3 styles de stylo (Marker, Pastel, Pen).
- **Embed** : élément intégrant un lien hypertexte ou une vidéo YouTube directement sur le canvas.

## Stockage & Technique

- **Document Package** : format de stockage d'un board — un dossier contenant les données du board et un sous-dossier `assets/` pour les images.
- **Undo Stack** : historique d'actions annulables (créer, déplacer, redimensionner, supprimer) géré via UndoManager.
