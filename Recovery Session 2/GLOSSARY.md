# GLOSSARY.md — Done

Référence des noms officiels pour les outils, fonctionnalités et éléments UI du projet. Utilisé de manière cohérente dans les conversations, les specs, et les fichiers de bugs.

## Canvas & Navigation

- **Infinite Canvas** : la zone de travail principale, pannable et zoomable sans limite fixe, sur laquelle tous les éléments sont posés.
- **Proportional Canvas** : comportement qui ajuste dynamiquement les marges/limites de dézoom en fonction de la zone réellement occupée par le contenu, plutôt qu'un espace infini fixe et disproportionné.
- **Cursor-anchored Zoom** : le zoom/dézoom se fait en gardant fixe le point du canvas sous le curseur, plutôt que le centre de la fenêtre.
- **Fit to Screen** : action qui recadre automatiquement la vue pour englober tout le contenu du board à l'écran.
- **Grid Attach** : magnétisme qui aligne un élément déplacé sur une grille en pointillés lorsque Shift est maintenu.
- **Anchor Point** : point d'ancrage affiché à chaque point cardinal (haut/bas/gauche/droite) de la bounding box d'un Node, apparaissant à l'approche d'un point A ou B d'une Arrow Node, et sur lequel ce point peut s'accrocher.

## Éléments UI

- **Zoom Capsule** : l'indicateur flottant affichant le pourcentage de zoom actuel ; un double-clic dessus déclenche le Fit to Screen.
- **Floating Toolbar** : la barre d'outils flottante en bas de l'écran, avec ombre portée, donnant accès aux outils de création.
- **Selection Tool** : le mode par défaut du canvas (clic/glisser/Marquee Selection habituels), actif tant qu'aucun outil de création n'est armé depuis la Floating Toolbar.
- **Resize Handle** : le point de saisie unique (bas-droite) permettant de redimensionner un élément sélectionné, à taille fixe quel que soit le zoom.
- **Selection Highlight** : le contour affiché autour d'un élément sélectionné sur le canvas.
- **Marquee Selection** : rectangle de sélection tracé par clic-glisser sur une zone vide du canvas, qui met en Selection Highlight tous les Nodes qu'il recouvre au relâchement.
- **Crop-Resize** : ⌘+glisser sur le Resize Handle d'un Image Node — redimensionne librement le cadre (largeur/hauteur indépendantes, sans contrainte de ratio) ; l'image à l'intérieur rescale toujours proportionnellement pour remplir ce cadre (mode "Fill", un seul facteur d'échelle), centrée, l'excédent étant simplement clippé. ⌘+Option ancre le redimensionnement au centre du cadre plutôt qu'au coin haut-gauche.
- **Crop Tool** : mode d'édition de recadrage activé par double-clic sur un Image Node déjà sélectionné — affiche l'image source entière, zone hors-cadre assombrie et floutée, 8 poignées (coins + bords), pan interne, grille des tiers pendant l'ajustement, validation via Cancel/Save.
- **Curve Handle** : la poignée positionnée sur le milieu visuel d'une Arrow Node, dont le glissé courbe la flèche (Bézier quadratique) ; un double-clic dessus réinitialise la flèche en ligne droite.
- **Arrow Style Panel** : le panneau flottant apparaissant au-dessus d'une Arrow Node sélectionnée, permettant de régler le style du trait (plein/pointillé) et son épaisseur.

## Éléments du canvas (Nodes)

- **Node** : terme générique pour tout élément posé sur le canvas (texte, image, forme, etc.).
- **Text Note** : un node de texte libre, éditable, avec largeur redimensionnable.
- **Image Node** : un node contenant une image importée. Sa taille (frame) et l'échelle interne de l'image affichée sont deux valeurs distinctes — le frame définit la zone visible sur le canvas, l'image à l'intérieur scale proportionnellement pour toujours remplir ce frame (comme un mode "Fill"), sans jamais être déformée.
- **Caption Box** : la zone de texte qui s'accroche au bas d'une image pour la décrire, ajoutée au double-clic.
- **Shape Node** : un node créé via le Shape Tool (rectangle ou ellipse), avec texte intégré éditable et un Resize Handle.
- **Arrow Node** : un node créé via l'Arrow Tool — une courbe de Bézier quadratique entre deux points (startPoint/endPoint, droite par défaut), tête de flèche à endPoint uniquement (orientée selon la tangente de la courbe), avec deux handles indépendants par point plus un Curve Handle, plutôt qu'un Resize Handle classique.
- **Arrow Connection** : lien persistant entre le point A ou B d'une Arrow Node et le point A, B, ou Curve Handle d'une autre Arrow Node ; la flèche connectée suit automatiquement la position de sa cible si celle-ci bouge, formant une arborescence. Si la flèche cible est supprimée, le point connecté redevient libre à sa dernière position.

## Outils (roadmap)

- **Shape Tool** : outil de création de formes avec texte intégré.
- **Arrow Tool** : outil de création de flèches droites ou courbes, personnalisables (style, épaisseur).
- **Color Palette Tool** : outil de sélection de couleur affichée en pastille ronde ou rectangle, avec bascule d'affichage RVB/HEX.
- **Drawing Tool** : outil de dessin libre avec 3 styles de stylo (Marker, Pastel, Pen).
- **Embed** : élément intégrant un lien hypertexte ou une vidéo YouTube directement sur le canvas.

## Stockage & Technique

- **Document Package** : format de stockage d'un board — un dossier contenant les données du board et un sous-dossier `assets/` pour les images.
- **Undo Stack** : historique d'actions annulables (créer, déplacer, redimensionner, supprimer) géré via UndoManager.
