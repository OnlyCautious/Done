# BUGS.md — Phase 1 Fixes

## VAGUE 1

## Interactions & Gestures (fondamental — impacte tout le reste)

1. **Latence au clic (~0.5s)** : délai perceptible entre le clic sur un élément
   et son highlight. Probablement lié au gesture recognizer qui attend de
   distinguer tap vs drag. À corriger avant d'ajouter d'autres interactions
   (sélection de formes, flèches, etc.).

2. **Pan au trackpad** : actuellement au clic-glisser. Doit passer en
   glissement à 2 doigts (comme Figma/Milanote), sans avoir à cliquer.

3. **Zoom au trackpad** : actuellement via glissement 2 doigts vers le
   haut/bas. Doit utiliser le geste de pincement natif (rapprocher/écarter
   les 2 doigts) pour zoomer/dézoomer.

4. **Pan à la souris** : ajouter le clic-molette (middle-click) + glisser
   comme méthode de pan, en plus du clic-glisser existant.

5. **Zoom adaptatif ("fit to content")** : le canvas infini ne doit pas
   permettre un dézoom disproportionné par rapport au contenu réel. Le
   niveau de zoom min/max doit s'adapter à la zone occupée par les éléments
   (peu d'éléments groupés = pas de dézoom excessif possible ; éléments
   dispersés = le zoom out s'ajuste en conséquence). Ajouter un indicateur
   de pourcentage de zoom dans la mini toolbar flottante à gauche.

## Sélection & Resize (fondamental)

6. **Taille des handles de resize** : actuellement ils scalent avec le zoom
   du canvas, ce qui les rend inutilisables au dézoom. Ils doivent garder
   une taille fixe à l'écran, indépendante du niveau de zoom.

7. **Un seul handle de resize**, positionné en bas à droite de l'élément
   (image ou autre), au lieu de handles sur les 4 coins/côtés. (Référence :
   capture jointe avec la flèche rouge.)

## Text Box (fondamental — comportement de base)

8. **Text box redimensionnable** : pouvoir agrandir/réduire la largeur de
   la zone de texte en glissant un bord, avec reflow du texte à l'intérieur
   (pas de scale de la police). (Référence : vidéo jointe.)

9. **Sauvegarde du texte** : actuellement le texte n'est enregistré qu'après
   un appui sur Échap (double-clic → édition → texte → Échap). Le texte doit
   se sauvegarder automatiquement au fil de la frappe, et cliquer ailleurs
   sur le canvas ne doit jamais effacer le texte saisi.

## Reporté à une phase ultérieure

10. **Crop d'image** : pas implémenté. Pas nécessaire pour la Phase 1 — à
    traiter dans une phase dédiée aux outils avancés d'image.




## Vague 2

1. **Grid Attach** : implémenter le magnétisme sur grille en pointillés
   lorsque Shift est maintenu pendant le déplacement d'un **Node**, pour
   permettre un alignement organisé optionnel.

2. **Cursor-anchored Zoom** : le zoom/dézoom est actuellement centré sur
   le milieu de la fenêtre. Il doit se faire en gardant fixe le point du
   canvas sous le curseur (comme Figma), pas le centre de la vue.

3. **Position de la Zoom Capsule** : la déplacer de "milieu gauche" vers
   "bas gauche". Ajouter un double-clic dessus déclenchant **Fit to
   Screen**.

4. **Scroll wheel** : actuellement il fait défiler la vue verticalement
   au lieu de zoomer/dézoomer à la souris. Restaurer le zoom/dézoom au
   scroll wheel pour les utilisateurs souris (le pan à la souris reste
   géré par le clic-molette + glisser, cf. Vague 1).

5. **Performance dégradée après dézoom** : latence/saccades observées
   après un dézoom. À investiguer — probable absence de culling des
   éléments hors-écran, ou re-render trop fréquent du **Infinite
   Canvas**. Merci de diagnostiquer la cause avant de proposer un fix.

6. **Proportional Canvas** : ajouter une marge d'environ 15% en plus
   autour de la zone occupée par le contenu, pour éviter que les limites
   de dézoom ne collent trop près des éléments en périphérie.

## Vague 3

1. **Scroll wheel / Cursor-anchored Zoom — nouvelle approche** :
   abandonner la détection par `hasPreciseScrollingDeltas` (non fiable,
   confirmé avec une MX Master + Logi Options+, smooth scrolling
   désactivé sans effet). Remplacer par :
   - Trackpad : zoom uniquement via le geste de pincement natif
     (magnification gesture), indépendant du scroll.
   - Scroll simple, tout périphérique confondu : toujours interprété
     comme du pan.
   - ⌘ (Cmd) + scroll, tout périphérique confondu : déclenche le
     Cursor-anchored Zoom.
   - Le pan au glissement 2 doigts (trackpad) et clic-molette + glisser
     (souris) restent inchangés depuis la Vague 1.

2. **Marquee Selection** (nouvelle fonctionnalité, remplace le pan au
   clic-glisser) : le clic-glisser sur une zone vide du canvas crée un
   rectangle de sélection qui met en Selection Highlight tous les Nodes
   qu'il recouvre au relâchement — sur trackpad comme sur souris.

3. **Suppression au clavier** (nouvelle fonctionnalité) : Backspace (ou
   Delete) supprime le(s) Node(s) sélectionné(s), un seul ou plusieurs
   via Marquee Selection. Action undoable.

## Note pour toutes les fonctionnalités ci-dessus

Pour chaque nouvel outil, geste, ou élément UI introduit dans cette
phase (ex. Marquee Selection), ajouter une entrée correspondante dans
GLOSSARY.md à la racine du projet — nom en gras suivi d'une description
en une phrase, dans la section appropriée. Respecter le format déjà
utilisé dans ce fichier.

## Vague 4

1. **Backspace/Delete + ESC ne répondent pas** : le son système
   ("beep" de touche non consommée) indique que l'event clavier n'est
   capté par aucune vue. Les gestes souris/trackpad (Shift+drag,
   ⌘+scroll) fonctionnent normalement, donc pas un problème de gesture
   handling — probable perte de focus clavier sur le canvas.

   Diagnostic avant fix : vérifier si le canvas (ou la vue contenant la
   logique de Node) détient bien le focus clavier au repos, et si ce
   focus est perdu après une interaction avec la Floating Toolbar ou
   après une sélection de Node. Logguer l'état du focus au moment d'un
   appui clavier pour confirmer avant de corriger.

2. **Zoom trackpad intermittent** : le pincement (magnification) cesse
   de répondre par moments, puis revient après quelques manipulations
   de pan/drag. Suggère un flag d'état (ex. "en cours de pan") qui ne
   se réinitialise pas correctement dans certains cas — probablement
   un geste annulé/interrompu plutôt que terminé normalement, laissant
   le flag bloqué et empêchant la reconnaissance du geste de zoom
   jusqu'à ce qu'un pan/drag complet le reset.

   Diagnostic avant fix : logguer l'état de ce flag (et celui du
   gesture recognizer de pan) au moment où le zoom ne répond pas, pour
   confirmer la cause avant de corriger l'exclusivité entre les deux
   gestures.

Committer séparément chaque fix une fois la cause confirmée. Si le
diagnostic infirme ces hypothèses, explique ce qui a été trouvé avant
de proposer un correctif.

## Vague 5

1. **Pan trackpad saccadé uniquement quand DONE est en focus** :
   fluide quand la fenêtre est visible mais pas active/focus, saccadé
   dès qu'elle redevient la fenêtre active. Piste prioritaire à
   vérifier : les logs de diagnostic temporaires ajoutés en Vague 4
   (focus clavier, flag de pan/zoom) sont-ils toujours actifs ? Un
   print console à chaque delta de pan peut suffire à saccader le
   rendu, et n'expliquerait le lien avec le focus que si ces handlers
   ne s'exécutent qu'en fenêtre active. Si ce n'est pas la cause,
   vérifier aussi tout état/computed property lié à `isKeyWindow` ou au
   focus qui déclencherait un travail coûteux à chaque frame de pan.

2. **Marquee Selection en temps réel** : actuellement le Node n'est mis
   en Selection Highlight qu'au relâchement du clic-glisser. Il doit
   être surligné dès que le rectangle de sélection le recouvre pendant
   le glissement, pas seulement à la fin du geste.

3. **Sélection additive/soustractive façon Finder** : ajouter ⌘+clic
   pour ajouter/retirer un Node individuel de la sélection courante, et
   ⌘+glisser pour étendre la Marquee Selection à une nouvelle zone sans
   perdre la sélection déjà en cours — comportement standard macOS
   (Finder, etc.).

Committer séparément chaque point. Pour le point 1, si le diagnostic
infirme l'hypothèse des logs, explique ce qui a été trouvé avant de
proposer un correctif.

## Vague 6

1. **Déplacement groupé des Nodes sélectionnés** : la suppression
   fonctionne déjà sur une sélection multiple (Marquee Selection ou
   ⌘+clic), mais le déplacement (drag) ne bouge qu'un seul Node à la
   fois au lieu de l'ensemble de la sélection courante. Tous les Nodes
   sélectionnés doivent se déplacer ensemble, en conservant leurs
   positions relatives entre eux, lorsqu'on en glisse un.

Action undoable comme un déplacement individuel (un seul pas d'undo
pour le déplacement du groupe entier, pas un par Node).

## Vague 7

1. **Shift pendant la création d'une shape** : actuellement Shift ne
   contraint le ratio (cercle parfait pour l'ellipse, carré parfait
   pour le rectangle) que sur un Node déjà créé et sélectionné, via le
   Resize Handle. Ce comportement doit être actif dès le geste de
   création lui-même (Shape Tool actif, clic-glisser initial) — pas
   besoin de créer la forme puis de la resize après coup pour y avoir
   accès.

2. **Option + Click Drag cassé** : le resize avec Option maintenu ne
   fonctionne pas correctement (cf. vidéo jointe). Comportement attendu :
   - Le scale X et Y doivent être **strictement liés et proportionnels**
     l'un à l'autre pendant tout le geste — jamais un axe qui bouge
     sans que l'autre suive dans la même proportion. L'objectif est
     uniquement d'agrandir/réduire le Node en conservant son ratio
     largeur/hauteur d'origine, quel que soit l'axe sur lequel
     l'utilisateur bouge la souris.
   - L'ancrage doit être le **centre du Node**, pas un coin — le Node
     grandit/rétrécit symétriquement autour de son centre pendant tout
     le drag.
   - S'applique à **tous les Nodes** ayant un Resize Handle (Text Note,
     Image Node, Shape), pas seulement aux formes.

Committer séparément chaque point.

## Vague 8

1. **Option + Click Drag — anchor et sensibilité toujours cassés**
   (2e tentative). Le scale X/Y est maintenant bien lié (uniforme),
   mais l'ancrage reste visuellement sur le handle au lieu du centre,
   et le resize est extrêmement sensible au moindre mouvement.

   Cause probable : le facteur de scale est calculé directement à
   partir du delta de mouvement de la souris, sans le rapporter à la
   distance géométrique par rapport au centre — et l'origin du Node
   n'est jamais recalculé par rapport au centre fixe, seule la taille
   change (d'où l'ancrage qui reste sur le handle).

   Algorithme attendu, à implémenter tel quel :

   - Au début du drag (Option maintenu) : mémoriser `centerStart`
     (centre du Node), et `vectorStart` = position du handle moins
     `centerStart` (vecteur du centre vers le handle).
   - À chaque mouvement de souris, position `P` :
     - `vectorCurrent` = `P` moins `centerStart`
     - `scale` = longueur(`vectorCurrent`) divisée par longueur(`vectorStart`)
     - `newSize` = taille d'origine du Node multipliée par `scale`
     - `newOrigin` = `centerStart` moins (`newSize` divisé par 2)
   - Le centre ne doit jamais bouger pendant tout le geste — seule la
     taille change, et l'origin est recalculé à partir du centre fixe
     et de la nouvelle taille, jamais accumulé/déplacé directement.

   Tester en particulier : resize très lent (mouvement de quelques
   pixels) doit donner un changement de taille proportionnellement
   petit — si ça reste trop sensible, le calcul du scale n'utilise
   probablement toujours pas la distance réelle au centre.

## Vague 9

1. **Option + Click Drag — 3e tentative, approche différente**. Le
   ratio et le centre sont corrects, mais le resize reste hypersensible.

   Nouvelle cause suspectée : le calcul utilise probablement les
   coordonnées écran (screen space) du curseur directement, sans les
   convertir en coordonnées canvas (content space) via le facteur de
   zoom actuel. Un même mouvement de souris doit produire un
   changement de taille différent selon le niveau de zoom — sinon
   c'est le signe que cette conversion manque. Vérifier en premier :
   logguer la position du curseur en coordonnées canvas (pas écran)
   pendant le drag, à deux niveaux de zoom différents (ex. 50% et
   150%), et confirmer que le comportement diffère bien entre les deux
   avant de conclure.

   Algorithme cible (référence : vidéo "Click Up Option resize
   correct" jointe) — le coin du Node suit le curseur au pixel près,
   en coordonnées canvas :

   - Convertir la position du curseur en coordonnées canvas dès le
     début du geste (pas juste au moment du calcul final).
   - `centerFixed` = centre du Node au début du drag (ne bouge jamais).
   - À chaque mouvement, en coordonnées canvas : le coin bottom-right
     du Node est repositionné exactement sur la position du curseur
     (1:1, aucun facteur de sensibilité ajouté).
   - La taille du Node = distance entre `centerFixed` et ce nouveau
     coin, multipliée par 2 sur chaque axe (puisque le centre reste
     fixe, symétrique des deux côtés).
   - `newOrigin` = `centerFixed` moins (`newSize` divisé par 2), comme
     avant.

   Le point clé de cette itération : le coin doit suivre le curseur au
   pixel près en espace canvas, pas juste être proportionnel à un delta
   — ça élimine mécaniquement le problème de sensibilité si la
   conversion de zoom est bien faite.

2. **Focus clavier — conflit avec les raccourcis d'outils**. En
   éditant un Text Note ou le texte d'une Shape, une seule lettre
   s'insère avant que le focus semble être repris ailleurs (Xcode passe
   au premier plan). Cause très probable : les raccourcis d'outils
   (V, H, R, O, A, T, D, C, Backspace, Esc, etc., introduits Vagues
   2-4) sont captés par un handler clavier qui ne vérifie pas si un
   champ de texte est actuellement en cours d'édition — chaque lettre
   tapée déclenche donc le raccourci correspondant (ex. "R" active le
   Shape Tool) au lieu d'être insérée comme caractère.

   Fix attendu : tout handler de raccourci d'outil doit vérifier en
   premier si un champ de texte (Text Note, texte de Shape, etc.) a
   actuellement le focus d'édition, et si oui, laisser passer l'event
   normalement vers ce champ sans déclencher de raccourci. Vérifier
   aussi qu'aucun handler global (`NSEvent.addGlobalMonitorForEvents`
   ou équivalent) n'est utilisé pour ces raccourcis à la place d'un
   handler scopé à la fenêtre/vue de l'app — un handler global
   capterait les touches même quand une autre app a le focus, ce qui
   correspondrait aussi au symptôme "Xcode prend le dessus".

   Lié au point 1 de la Vague 4 (focus clavier déjà signalé pour
   Backspace/Esc) — probablement la même cause racine, à corriger
   ensemble.

   **État (2026-07-28) :** point 1 corrigé et commité. Point 2 —
   l'hypothèse est infirmée : grep du projet entier pour tout handler
   de raccourci-lettre (V/H/R/O/A/T/D/C), `NSEvent.
   addGlobalMonitorForEvents`, `onKeyPress`, `keyEquivalent` ne donne
   aucun résultat ; le seul moniteur NSEvent du code (`panMonitor`) est
   local, pas global, et ne gère que scroll/clic-molette. Aucun
   raccourci d'outil n'a jamais été implémenté dans ce projet.
   Hypothèse alternative proposée (non confirmée) : Xcode reprend le
   premier plan de lui-même quand le débogueur s'arrête (breakpoint
   d'exception ou crash), indépendamment du code de l'app — question
   posée à l'utilisateur pour confirmer, réponse en attente.

## Vague 10

1. **Shift + Option + Click Drag** (nouveau raccourci) : fixe le ratio
   largeur/hauteur pendant le resize avec ancrage centre, en plus du
   comportement Option seul (ratio libre) déjà fonctionnel. S'applique
   à tous les Nodes sauf Image Node.

2. **Images — Option + Click Drag a un ratio bloqué par défaut** :
   contrairement aux autres Nodes, le resize d'une Image Node avec
   Option seul doit toujours conserver le ratio d'origine (pas de
   resize libre possible). Shift + Option + Click Drag sur une image
   ne doit rien changer de plus — comportement strictement identique à
   Option seul dans ce cas précis.

3. **Crop-Resize** (nouvelle fonctionnalité, images uniquement) :
   Cmd + Click Drag sur une Image Node redimensionne le cadre visible
   sans changer l'échelle du contenu de l'image — révèle ou masque une
   partie de l'image plutôt que de la scaler. Le champ `cropRect` déjà
   prévu dans le data model (`ImageNode`) doit être utilisé pour ça.

4. **Crop Tool** (nouvelle fonctionnalité, images uniquement) — spec
   détaillée, pas de vidéo de référence disponible pour Claude Code :

   **Activation** : double-clic sur une Image Node déjà sélectionnée.

   **Affichage en mode Crop** :
   - L'image est affichée à une taille révélant l'intégralité de
     l'image source (y compris les parties actuellement masquées par
     le cropRect existant), pas seulement le cadre actuellement visible.
   - Un rectangle de recadrage (overlay) représente le cropRect actuel,
     avec 8 poignées : 4 aux coins (resize sur les 2 axes), 4 au milieu
     des bords (resize sur 1 axe uniquement).
   - Une grille 3x3 (règle des tiers) s'affiche à l'intérieur du
     rectangle de recadrage pendant l'ajustement, pour aider à la
     composition.
   - La zone de l'image en dehors du rectangle de recadrage est à la
     fois **assombrie** (overlay semi-transparent sombre) **et
     légèrement floutée** (léger blur gaussien), pour bien distinguer
     visuellement la zone exclue de la zone nette qui sera conservée.

   **Interactions** :
   - Glisser une poignée : redimensionne le rectangle de recadrage.
     Toujours contraint à rester dans les limites réelles de l'image
     source — impossible de "cropper" en dehors des pixels existants.
   - Glisser à l'intérieur du rectangle (pas sur une poignée) :
     déplace le rectangle de recadrage sur l'image, sans le
     redimensionner (pan du cadre).

   **Barre d'action en bas** (visible pendant tout le mode Crop) :
   - Bouton **Cancel** : annule, revient au cropRect précédent, sort du
     mode Crop.
   - Bouton **Save** : valide le nouveau cropRect, sort du mode Crop,
     la Image Node affiche désormais l'image recadrée à la taille
     actuelle du Node.
   - Un bouton "Rotate left" apparaît dans la référence Milanote —
     **optionnel, à ignorer pour cette phase**, pas dans le scope
     initial. Ne pas l'implémenter maintenant.

   **Sortie du mode** : Esc a le même effet que Cancel (annule et
   sort). Cliquer ailleurs sur le canvas sans passer par Save doit
   aussi annuler — jamais de sauvegarde silencieuse d'un crop non
   confirmé.

   **Data model** : stocker `cropRect` en coordonnées relatives
   (0 à 1) par rapport aux dimensions de l'image source, pas en pixels
   absolus — ça reste valide quel que soit le resize du Node ou le
   niveau de zoom du canvas.

   Remplace pour l'instant le comportement prévu de "double-clic pour
   ajouter une légende" (cf. SPEC.md, conflit noté) — ne pas
   implémenter les légendes dans cette vague.

Committer séparément chaque point.
