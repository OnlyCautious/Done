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

## SESSION 2

## VAGUE 1

1. **Crash "snapshot should exist before creating a new snapshot for
   undo"** en tapant du texte dans un Node (ex. taper "Hello World" —
   le crash survient au "E"). Cause très probable : le conflit de
   focus clavier déjà signalé en Vague 4 et Vague 9 (jamais
   complètement résolu) — une lettre tapée dans un champ de texte en
   cours d'édition déclenche encore un raccourci d'outil global (ici
   "E" = Embed Tool), qui tente d'ouvrir une nouvelle transaction
   UndoManager pendant que celle de l'édition de texte est encore
   active, d'où le crash sur le snapshot.

   Cette fois le bug casse l'app (non-responsive, force quit
   nécessaire) plutôt qu'un simple bip système — priorité haute,
   diagnostic complet demandé avant fix :
   - Confirmer que le champ de texte en édition ne détient toujours
     pas le focus clavier de façon fiable (logguer le responder/focus
     actif à chaque touche pressée).
   - Vérifier que chaque groupe UndoManager (`beginUndoGrouping`/
     `endUndoGrouping` ou équivalent SwiftData) est bien fermé avant
     qu'un autre puisse s'ouvrir — ajouter une garde défensive qui
     empêche d'ouvrir un nouveau snapshot si un autre est déjà actif,
     indépendamment du fix de focus (filet de sécurité, pas un
     remplacement du vrai fix).

2. **Crop-Resize rend l'app non-responsive quasi immédiatement** —
   à peine le temps d'apercevoir l'animation avant le freeze. Piste
   probable : le flou (blur gaussien) demandé sur la zone hors-cadre
   est recalculé de façon synchrone à chaque frame du drag, ce qui
   bloque le thread principal. Diagnostiquer si le blur (ou un autre
   calcul du mode Crop) s'exécute de façon coûteuse et synchrone
   pendant le geste, avant de proposer un fix (ex. throttle, calcul
   asynchrone, ou blur appliqué seulement au relâchement plutôt qu'en
   continu).

3. **Double-clic sur une Image Node ne déclenche rien** — le Crop Tool
   ne s'active pas du tout. Vérifier que le double-clic est bien câblé
   spécifiquement sur Image Node (peut-être jamais connecté, ou
   intercepté par un autre gesture recognizer en premier).

Committer séparément chaque point. Pour les points 1 et 2, explique le
diagnostic trouvé avant de proposer le correctif.

## VAGUE 2

### Updates aux fichiers de référence (à faire immédiatement)

**GLOSSARY.md** — remplacer cette ligne :
```
- Image Node : un node contenant une image importée, redimensionnable (et à terme recadrable).
```
par :
```
- Image Node : un node contenant une image importée. Sa taille (frame) et l'échelle interne de l'image affichée sont deux valeurs distinctes — le frame définit la zone visible sur le canvas, l'image à l'intérieur scale proportionnellement pour toujours remplir ce frame (comme un mode "Fill"), sans jamais être déformée.
```

---

### Bugs & Corrections

1. **Crop-Resize — comportement incohérent selon l'ordre des touches**
   (cf. vidéos "Click_handle_puis_CMD" et "CMD_appuye__puis_Click_handle") :
   - Cmd maintenu **avant** le clic-glisser sur le handle : crop simple,
     correct.
   - Clic-glisser démarré **puis** Cmd pressé en cours de geste :
     produit une déformation (stretch X/Y indépendant) — c'est un bug,
     pas un mode alternatif. Le comportement doit être identique peu
     importe le moment où Cmd est pressé (avant ou pendant le drag).

   **Modèle cible, à corriger en profondeur** : découpler le frame de
   l'Image Node de l'échelle interne de l'image.
   - Le **frame** = la taille du Node visible sur le canvas, modifiée
     par le drag du handle.
   - L'**échelle de l'image à l'intérieur** du frame se recalcule pour
     toujours remplir le frame proportionnellement (mode "Fill" — le
     ratio source de l'image ne change jamais, seule la portion
     visible/l'échelle globale s'ajuste). Jamais de déformation
     indépendante des axes X et Y.
   - Ce modèle s'applique identiquement que Cmd soit pressé avant ou
     pendant le drag.

2. **Crop Tool — modificateurs manquants**. Ajouter les mêmes
   conventions que le Resize Handle standard :
   - Shift + drag d'une poignée du cadre de recadrage : contraint à un
     recadrage carré.
   - Option + drag d'une poignée : redimensionne le cadre de recadrage
     depuis son centre plutôt que depuis le coin opposé.

3. **Sélection out-of-bounds** (cf. vidéo jointe) : la partie de
   l'image masquée par le crop reste sélectionnable en cliquant à côté
   du frame visible — la zone de hit-testing correspond toujours aux
   dimensions complètes de l'image source au lieu de se limiter au
   frame actuellement visible. La zone cliquable/sélectionnable d'une
   Image Node doit correspondre exactement à son frame visible, jamais
   à la zone masquée par le crop.

Committer séparément chaque point.

## VAGUE 3

### Diagnostic requis avant tout fix (Crop-Resize)

Deux tentatives précédentes (Vague 2) n'ont rien changé au comportement :
Cmd avant clic-glisser reste un simple crop basique (pas de mode Fill),
et Cmd pressé pendant le drag continue de produire un stretch X/Y
indépendant. Avant de retenter quoi que ce soit, log/confirme :
- Le code du handler actuel du Crop-Resize — colle le contenu de la
  fonction concernée dans ta réponse avant de la modifier, pour qu'on
  comprenne pourquoi les tentatives précédentes n'ont rien changé.
- Confirme si un `contentScale` unique (scalaire) existe déjà dans le
  modèle de données de Image Node, ou si l'image est actuellement
  stockée avec une largeur et une hauteur affichées indépendantes
  (ce qui expliquerait le stretch).

### Algorithme cible — formules explicites

Modèle de données attendu pour Image Node :
- `frameSize` (width, height) : taille du Node visible sur le canvas,
  modifiable librement sur les deux axes indépendamment (le frame n'a
  pas besoin de respecter le ratio de l'image source).
- `contentScale` : **un seul scalaire**, jamais deux valeurs séparées
  pour X et Y. C'est le seul facteur d'échelle appliqué à l'image
  source.
- `sourceSize` (width, height) : dimensions natives de l'image importée,
  fixes, jamais modifiées.

Pendant Cmd + drag du handle (peu importe si Cmd est pressé avant ou
pendant le drag — comportement strictement identique dans les deux cas) :

1. Le coin du frame suit le curseur (en coordonnées canvas, donc en
   tenant compte du zoom) — le frame peut devenir plus large, plus
   haut, plus étroit, plus court, sans contrainte de ratio sur lui-même.
2. À chaque frame de drag, recalculer :
   `contentScale = max(frameSize.width / sourceSize.width, frameSize.height / sourceSize.height)`
   — c'est la formule "cover" : l'image scale toujours par ce facteur
   unique, jamais différemment sur X et Y.
3. L'image est dessinée avec ce `contentScale` unique, centrée dans le
   frame, et tout ce qui dépasse les limites du frame est clippé
   (non affiché, mais toujours en mémoire — cf. point sélection
   out-of-bounds déjà corrigé en Vague 2, à ne pas régresser).
4. Ancrage du frame pendant le drag : coin haut-gauche fixe par défaut
   (comportement standard du Resize Handle), sauf si Option est aussi
   maintenu, auquel cas le centre du frame reste fixe (cohérent avec
   la convention Option déjà en place pour tous les autres Nodes).

Test de validation à faire après implémentation : redimensionner le
frame en largeur seule (garder la hauteur fixe) ne doit jamais déformer
l'image — seul `contentScale` (recalculé via la formule cover) doit
changer, jamais de scale X/Y séparé.

Committer une fois le diagnostic confirmé et le fix appliqué.

## VAGUE 4

### Updates aux fichiers de référence (à faire immédiatement)

**TOOLS.md** — ajouter cette ligne à la fin de la section "Idées inspirées de la toolbar ClickUp — nouvelles, à valider" :
```
- Corner Radius : possibilité d'arrondir les bords d'une Image Node, d'un Shape Tool rectangle, ou d'un Text Note — un slider ou une valeur numérique appliquée uniformément aux 4 coins. Idée pour une phase future, pas encore cadrée.
```

---

### Bugs & Corrections

1. **Crop Tool — le cadre de recadrage peut dépasser les limites de
   l'image source, uniquement côtés gauche et haut**. En redimensionnant
   le cadre depuis un handle, les côtés directement liés à ce handle
   restent bien contraints aux dimensions de l'image, mais les côtés
   opposés (dont la position résulte d'un recalcul d'origin plutôt
   que d'une taille bornée directement) peuvent sortir des limites
   réelles de l'image source.

   Fix attendu : le clamp aux dimensions de l'image source doit
   s'appliquer aux 4 côtés du cadre de recadrage à chaque frame du
   drag, pas seulement au côté actif du handle — origin ET taille
   doivent tous les deux être bornés entre 0 et les dimensions de
   `sourceSize` après chaque recalcul, peu importe quel handle est
   utilisé.

Committer une fois corrigé.

## Vague 5

1. **Shift + drag dans le Crop Tool — le carré se déforme en rectangle
   au contact des bords de l'image source**. Le ratio 1:1 est respecté
   tant que la poignée reste loin des limites, mais dès que le carré
   atteint un bord de l'image source, il continue à suivre le curseur
   sur l'axe encore libre et devient un rectangle — au lieu de se
   bloquer à sa taille carrée maximale pour cette position.

   Cause probable : le clamp aux limites de l'image (déjà en cause
   pour le bug de la Vague 4 sur les côtés gauche/haut) est appliqué
   indépendamment sur chaque axe (X puis Y séparément), après le
   calcul de la contrainte Shift. Résultat : un axe peut se faire
   clamper pendant que l'autre continue de grandir, cassant le ratio
   carré au moment même où le clamp intervient.

   Comportement attendu : quand Shift est maintenu, le clamp aux
   limites de l'image doit être calculé sur la taille du carré dans
   son ensemble, pas axe par axe. Concrètement :
   - Calculer la taille carrée que produirait le mouvement du curseur
     (comme actuellement, sans clamp).
   - Calculer séparément la taille carrée maximale possible à cette
     position, compte tenu de l'ancre (coin opposé, ou centre si
     Option est aussi maintenu) et des limites de l'image source sur
     les deux axes — c'est-à-dire la plus petite des deux distances
     disponibles (horizontale et verticale) jusqu'au bord.
   - La taille finale du carré = le minimum entre la taille demandée
     par le curseur et cette taille carrée maximale, appliqué
     identiquement aux deux axes.
   - Résultat attendu : au contact d'un bord, le carré se fige à sa
     taille maximale et arrête de suivre le curseur sur les deux axes
     à la fois — jamais un seul axe qui continue.

   Vérifier si ce même correctif doit s'appliquer au clamp standard
   (sans Shift) pour rester cohérent, ou si le bug de la Vague 4 est
   une cause distincte — à confirmer par le diagnostic avant de
   toucher au code du clamp sans Shift.

Committer séparément de tout autre point en cours.

## Arrow Tool — Vague 1 (post-Étape 1)

### Bugs & Corrections

1. **Déplacement du corps de la ArrowNode — mauvais suivi du curseur**.
   En glissant le corps de la flèche (hors handles A/B), la flèche ne
   suit pas le curseur au pixel près — décalage/dérive pendant le
   drag (cf. vidéo jointe : observable dans ce contexte, mais rappel —
   je sais que tu ne peux pas lire la vidéo, donc je décris ci-dessous
   ce qui doit être vérifié).

   Cause probable, par analogie avec des bugs déjà rencontrés sur ce
   projet (Session 1 Vague 9, Session 2 Vague 3) : soit le calcul de
   déplacement utilise la position brute du curseur au lieu d'un
   delta relatif au point de départ du drag, soit la conversion
   écran → coordonnées canvas (facteur de zoom) n'est pas appliquée
   correctement au delta avant de l'ajouter à `startPoint`/`endPoint`.

   Diagnostic avant fix :
   - Logguer, à chaque frame du drag : la position du curseur en
     coordonnées canvas, le delta calculé, et les valeurs résultantes
     de `startPoint`/`endPoint`.
   - Tester à deux niveaux de zoom différents (ex. 50% et 150%) — si
     l'ampleur de la dérive change avec le zoom, ça confirme un
     problème de conversion d'espace plutôt qu'un problème de calcul
     de delta pur.
   - Confirmer si le déplacement du corps entier utilise bien un delta
     cumulé depuis le point de départ du drag (translation de
     `startPoint` ET `endPoint` par le même vecteur), ou s'il
     recalcule les points à partir de la position absolue du curseur
     à chaque frame — ce dernier cas expliquerait un décalage si le
     point de clic initial sur le corps de la flèche n'est pas
     exactement sur le segment.

   Comportement attendu : le point du corps de la flèche sous le
   curseur au moment du clic doit rester sous le curseur pendant tout
   le drag, quel que soit le niveau de zoom.

2. **Grid Attach absent pour ArrowNode**. Le magnétisme sur grille en
   pointillés (Shift maintenu, cf. GLOSSARY.md) fonctionne déjà pour
   les autres types de Node mais pas pour ArrowNode, ni pour le
   déplacement du corps entier ni pour le déplacement individuel des
   handles A et B.

   Comportement attendu :
   - Shift + drag du corps de la flèche : `startPoint` ET `endPoint`
     s'alignent sur la grille ensemble, en conservant leur position
     relative (comme le déplacement groupé de plusieurs Nodes
     sélectionnés, cf. Session 1 Vague 6 — même logique de
     translation groupée, mais ici appliquée aux deux points d'une
     seule ArrowNode).
   - Shift + drag du handle A ou B individuellement : seul ce point
     s'aligne sur la grille, l'autre point ne bouge pas.

   Vérifier comment Grid Attach est implémenté pour les autres Node
   (probablement une fonction utilitaire de snap réutilisable) avant
   de l'intégrer à ArrowNode — réutiliser cette logique plutôt que
   la redupliquer si possible.

Committer séparément chaque point. Pour le point 1, explique le
diagnostic trouvé avant de proposer le correctif.

## Arrow Tool — Vague 2 (post-Étape 2)

### Correction de conception — état "droite / courbée"

Le modèle actuel (Étape 2) ne distingue pas explicitement une flèche
droite d'une flèche courbée — la courbure est déduite de la position
de `controlPoint` par rapport au milieu du segment. Ce choix est en
cause dans le bug observé : déplacer A ou B sur une flèche droite la
courbe involontairement, car `controlPoint` reste figé à son ancienne
position absolue au lieu de suivre le nouveau milieu.

Fix : ajouter un état explicite à `ArrowNode` :
- `isCurved: Bool`, `false` par défaut à la création.

### Comportement attendu selon l'état

**Tant que `isCurved == false`** (flèche droite, jamais touchée via
le Curve Handle) :
- Déplacer le handle A, le handle B, ou le corps entier de la flèche
  recalcule `controlPoint = midpoint(startPoint, endPoint)` à chaque
  frame du drag — la flèche reste visuellement droite quoi que
  l'utilisateur fasse avec A/B ou le déplacement global.
- Cela permet de repositionner librement une flèche droite sans
  jamais la faire basculer en courbée par accident.

**Dès que l'utilisateur glisse le Curve Handle (point C)** et que
`controlPoint` s'écarte du milieu :
- Passer `isCurved = true`. Cette transition est définitive jusqu'à
  un reset explicite (double-clic sur le Curve Handle, cf. Étape 2 —
  qui doit aussi repasser `isCurved = false`).

**Tant que `isCurved == true`** :
- Déplacer le handle A, le handle B, ou le corps entier : conserver
  `controlPoint` en position absolue (comportement déjà spécifié en
  Étape 2, à ne pas changer) — la courbe garde sa forme, et le fait
  de bouger A/B seul modifie la courbure relative au nouveau segment,
  ce qui est le comportement voulu ("les points A et B permettent la
  courbure aussi").

**Double-clic sur le Curve Handle** : reset `controlPoint` au milieu
ET `isCurved = false` (retour complet à l'état "flèche droite", pas
seulement une réinitialisation visuelle ponctuelle).

### Vérification

Tester spécifiquement le scénario qui a révélé le bug : créer une
flèche droite, déplacer A ou B plusieurs fois de suite (jamais toucher
C) — la flèche doit rester droite à chaque étape, jamais de courbure
résiduelle.

Committer une fois corrigé.

## Arrow Tool — Vague 4 (crash au démarrage, post-Étape 3)

### Crash SIGABRT à l'ouverture — `arrowStrokeStyle`

L'app crashe à l'ouverture avec un board existant (créé pendant les
Étapes 1/2, donc antérieur à l'ajout de `strokeStyle`/`strokeWidth`
sur `ArrowNode`). Stack trace : SIGABRT dans l'accesseur généré
SwiftData de `arrowStrokeStyle`, sur `self.getValue(forKey:
\.arrowStrokeStyle)`.

Cause très probable : ajout d'une propriété stockée à un `@Model`
existant sans valeur par défaut compatible avec la migration légère
automatique de SwiftData — les enregistrements déjà persistés sur
disque n'ont pas cette clé, et il n'y a rien vers quoi retomber au
chargement.

Diagnostic avant fix :
- Confirmer que `arrowStrokeStyle` a bien une valeur par défaut
  déclarée directement en ligne (`var arrowStrokeStyle:
  ArrowStrokeStyle = .solid`), pas assignée seulement dans un
  initialiseur custom — SwiftData a besoin du défaut au niveau de la
  déclaration pour la migration légère.
- Vérifier si `ArrowStrokeStyle` (l'enum solid/dashed) est bien
  `Codable` et conforme aux exigences SwiftData pour un type stocké
  custom — un enum mal conformé peut faire échouer la migration même
  avec un défaut présent.
- Confirmer si le crash touche uniquement les boards de test
  existants (créés avant l'Étape 3) ou aussi un board flambant neuf —
  si un board neuf crashe aussi, la cause n'est pas la migration mais
  un bug dans l'accesseur lui-même, à investiguer séparément.
- Si c'est bien un problème de migration : soit corriger la
  déclaration de la propriété pour que la migration légère
  fonctionne, soit — si SwiftData ne gère pas proprement la migration
  légère pour ce type d'enum stocké — mettre en place un
  `VersionedSchema` / plan de migration minimal plutôt qu'un
  contournement fragile.

Ne pas supprimer les boards de test existants comme solution de
contournement — le but est que l'app gère correctement l'évolution du
schéma, pas d'éviter le problème en repartant d'un board vide.

Explique le diagnostic trouvé avant de proposer le correctif, et
committer une fois confirmé.

## Arrow Tool — Vague 5 (post-Étape 3)

### Bugs & Corrections

1. **Tête de flèche pointillée en mode Dashed**. Actuellement, quand
   `strokeStyle == .dashed`, le pattern de tirets s'applique à
   l'ensemble du path, y compris la tête de flèche — la tête doit
   rester en trait continu (plein) dans tous les cas, seul le corps
   (shaft) doit être affecté par le style pointillé.

   Fix attendu : appliquer le `StrokeStyle(dash:)` uniquement au
   sous-path du corps (de startPoint jusqu'à la base de la tête, même
   découpage que celui déjà utilisé pour le mode Dynamic — cf. Étape
   3, "le ruban s'arrête à la base de la tête de flèche"), et dessiner
   la tête séparément avec un stroke/fill plein, indépendamment de
   `strokeStyle`.

2. **Arrow Style Panel — repositionnement uniquement au relâchement**.
   Le panneau ne recalcule sa position qu'une fois le drag terminé
   (relâchement de A, B, ou du corps), au lieu de suivre en temps réel
   pendant le geste. Même défaut de principe que celui déjà corrigé
   pour la Marquee Selection (Session 1, Vague 5, point 2 —
   surlignage en temps réel plutôt qu'au relâchement) : ici c'est la
   position du panneau plutôt que le highlight qui doit s'actualiser
   à chaque frame du drag, pas seulement à la fin.

   Comportement attendu :
   - Pendant le drag du handle A, du handle B, du corps entier, ou du
     Curve Handle (point C, cf. Étape 2) : recalculer la position du
     panneau à chaque frame, en fonction de la bounding box actuelle
     de la flèche (qui change en temps réel avec la courbe si le
     Curve Handle est déplacé).
   - Actuellement le panneau semble ignorer le Curve Handle dans le
     calcul de sa position de repli — inclure `controlPoint` (ou plus
     précisément le point visuel du Curve Handle, cf. Étape 2) dans le
     calcul de la bounding box utilisée pour positionner le panneau,
     pas seulement startPoint/endPoint.
   - Référence de comportement cible : le panneau contextuel de
     ClickUp qui suit la sélection en continu pendant le drag, sans
     lag ni saut au relâchement.

Committer séparément chaque point.
