//
//  NodeView.swift
//  DONE
//

import SwiftUI
import SwiftData
import AppKit

/// Shared chrome (selection border, move gesture, select/edit taps, resize
/// handle) around a node's own content view. Position/size are expressed in
/// canvas space; the parent canvas layer applies the pan/zoom transform on top.
struct NodeView: View {
    @Bindable var node: BoardNode
    var canvas: CanvasViewModel
    var onInteract: () -> Void
    /// Commits a group move (BUGS.md Vague 6 #1): applies `delta` to every
    /// currently-selected node in one step, as a single undo entry — this
    /// node doesn't have access to the rest of the board's nodes itself.
    var onGroupDragEnd: (CGSize) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.boardURL) private var boardURL

    @State private var dragStartPosition: CGPoint?
    @State private var liveTranslation: CGSize = .zero
    @State private var isGroupDragForThisGesture = false

    // Only ever a bottom-right handle (BUGS.md #7), so top-left never moves
    // *unless* Option-held center-anchored resize is active (Phase 2 #5), in
    // which case the origin moves too to keep the center fixed.
    @State private var resizeStartSize: CGSize?
    @State private var resizeStartOrigin: CGPoint?
    @State private var liveResizeSize: CGSize?
    @State private var liveResizeOrigin: CGPoint?

    // Crop-Resize (Cmd-held, images only, BUGS.md Vague 10 #3, rewritten
    // Session 2 Vague 3) mutates node.width/height/contentScale/crop*
    // directly and continuously, rather than through the live-size-then-
    // commit-once pattern above — ImageNodeContentView needs these live to
    // render the in-progress preview, and there's nowhere else to put a
    // "live" override. hasCropUndoRegistered mirrors the text-autosave
    // pattern: only the first mutation of the gesture registers with the
    // undo manager, so undoing the whole drag is still one step.
    @State private var hasCropUndoRegistered = false

    // Re-anchoring (BUGS.md Session 2 Vague 2 #1): resizeStartSize/Origin/
    // CropSize and resizeAnchorLocation are reset not just once per gesture
    // but every time Cmd's held state changes mid-gesture, so computeResize
    // and applyCropResize always measure "how far the cursor has moved since
    // this reference point" rather than since the gesture's very first
    // pixel. Without this, pressing Cmd partway through a drag replayed the
    // *entire* gesture's translation through the crop-resize formula (which,
    // unlike the ratio-locked default resize, moves each axis independently)
    // and the frame jumped/stretched to wherever that math landed instead of
    // continuing smoothly from the shape already on screen.
    @State private var resizeAnchorLocation: CGPoint?
    @State private var resizeAnchorWasCommandHeld = false

    private var isSelected: Bool { canvas.selectedNodeIDs.contains(node.id) }
    private var isEditing: Bool { canvas.editingNodeID == node.id }

    private var displaySize: CGSize {
        liveResizeSize ?? CGSize(width: node.width, height: node.height)
    }

    private var displayOrigin: CGPoint {
        if let liveResizeOrigin { return liveResizeOrigin }
        let base = CGPoint(x: node.x, y: node.y)
        // Any selected node (not just the one whose gesture is driving the
        // drag) follows the shared group-drag delta while one is active.
        if canvas.isGroupDragActive && isSelected {
            return CGPoint(x: base.x + canvas.groupDragDelta.width, y: base.y + canvas.groupDragDelta.height)
        }
        guard dragStartPosition != nil else { return base }
        let point = CGPoint(x: base.x + liveTranslation.width, y: base.y + liveTranslation.height)
        return Self.isShiftHeld ? GridAttach.snapped(point) : point
    }

    private var isCropping: Bool { canvas.cropSession?.nodeID == node.id }

    var body: some View {
        if isCropping {
            ImageCropEditorView(node: node, canvas: canvas)
        } else {
            content
                .frame(width: displaySize.width, height: displaySize.height)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                )
                .overlay(alignment: .topLeading) { resizeHandleOverlay }
                .offset(x: displayOrigin.x, y: displayOrigin.y)
                .gesture(dragGesture)
                .simultaneousGesture(singleTapGesture)
                .simultaneousGesture(doubleTapGesture)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch node.kind {
        case .text:
            TextNoteContentView(node: node, isEditing: isEditing) {
                canvas.editingNodeID = nil
                try? modelContext.save()
            }
        case .image:
            ImageNodeContentView(node: node, boardURL: boardURL)
        case .shape:
            ShapeNodeContentView(node: node, isEditing: isEditing) {
                canvas.editingNodeID = nil
                try? modelContext.save()
            }
        case .arrow:
            // Never actually reached: ContentView routes .arrow nodes to
            // ArrowNodeView instead of NodeView entirely (Phase 3 step 1/6)
            // — arrows have their own two-handle/body-drag chrome, nothing
            // like this rectangular-frame content. Only here to satisfy the
            // exhaustive switch.
            EmptyView()
        }
    }

    // MARK: - Move

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .local)
            .onChanged { value in
                if dragStartPosition == nil {
                    dragStartPosition = CGPoint(x: node.x, y: node.y)
                    onInteract()
                    // Only treat this as a group drag if the node was already
                    // part of a multi-selection before this gesture began —
                    // dragging an unselected node (even with others selected)
                    // still just selects and moves that one, per Vague 3/5.
                    let wasAlreadyMultiSelected = isSelected && canvas.selectedNodeIDs.count > 1
                    isGroupDragForThisGesture = wasAlreadyMultiSelected
                    if !wasAlreadyMultiSelected {
                        canvas.select(node.id)
                    }
                }
                guard let start = dragStartPosition else { return }
                if isGroupDragForThisGesture {
                    canvas.isGroupDragActive = true
                    canvas.groupDragDelta = Self.isShiftHeld
                        ? GridAttach.snappedDelta(from: start, translation: value.translation)
                        : value.translation
                } else {
                    liveTranslation = value.translation
                }
            }
            .onEnded { value in
                guard let start = dragStartPosition else { return }
                let delta = Self.isShiftHeld
                    ? GridAttach.snappedDelta(from: start, translation: value.translation)
                    : value.translation
                if isGroupDragForThisGesture {
                    onGroupDragEnd(delta)
                    canvas.isGroupDragActive = false
                    canvas.groupDragDelta = .zero
                } else {
                    node.x = start.x + delta.width
                    node.y = start.y + delta.height
                    try? modelContext.save()
                }
                dragStartPosition = nil
                liveTranslation = .zero
                isGroupDragForThisGesture = false
            }
    }

    // Grid Attach (BUGS.md Vague 2 #1): holding Shift while dragging snaps the
    // node to the same dotted grid CanvasView draws (24pt canvas-space spacing),
    // for optional organized alignment. Snapping applies live during the drag
    // (not just on drop) so the snap is visible as it happens. The actual snap
    // math (spacing, snapped(_:), snappedDelta(from:translation:)) lives in
    // GridAttach.swift so ArrowNodeView can share it (Arrow Tool Vague 1 #2)
    // instead of redefining its own copy of the same grid.
    private static var isShiftHeld: Bool {
        NSEvent.modifierFlags.contains(.shift)
    }

    // Single- and double-tap are recognized independently (simultaneousGesture)
    // rather than via `.exclusively`, which would force the single tap to wait
    // out the double-click interval before it could fire — that wait was the
    // ~0.5s selection-highlight latency reported in BUGS.md #1.
    private var singleTapGesture: some Gesture {
        TapGesture(count: 1).onEnded {
            onInteract()
            // Cmd+click toggles this node in/out of the selection without
            // touching the rest — Finder-style additive/subtractive
            // selection (BUGS.md Vague 5 #3).
            if NSEvent.modifierFlags.contains(.command) {
                canvas.toggleSelection(node.id)
            } else {
                canvas.select(node.id)
            }
        }
    }

    private var doubleTapGesture: some Gesture {
        TapGesture(count: 2).onEnded {
            onInteract()
            // Double-clicking an image that's *already* selected enters the
            // Crop Tool instead of just re-selecting it (BUGS.md Vague 10
            // #4) — this replaces the previously-planned "double-click adds
            // a caption" behavior for images, per spec; captions aren't
            // implemented.
            if node.kind == .image && isSelected {
                canvas.beginCropping(
                    nodeID: node.id,
                    x: node.x, y: node.y,
                    sourceWidth: node.sourceWidth, sourceHeight: node.sourceHeight, contentScale: node.contentScale,
                    crop: CropFraction(x: node.cropX, y: node.cropY, width: node.cropWidth, height: node.cropHeight)
                )
                return
            }
            canvas.select(node.id)
            if node.kind == .text || node.kind == .shape {
                canvas.editingNodeID = node.id
            }
        }
    }

    // MARK: - Resize

    // Handles live inside the canvas content layer, which sits under the
    // canvas's .scaleEffect(canvas.scale) — so a handle drawn at a fixed
    // canvas-space size shrinks to unusable at low zoom (BUGS.md #6). Dividing
    // by canvas.scale here cancels that ancestor scale out, keeping the handle
    // a constant size on screen at any zoom level.
    private var handleScreenDiameter: CGFloat { 10 }
    private var handleScreenStrokeWidth: CGFloat { 1.5 }

    private var showsResizeHandle: Bool {
        isSelected && (node.kind == .image || node.kind == .text || node.kind == .shape)
    }

    // A single bottom-right handle (BUGS.md #7) rather than one per corner —
    // top-left always stays anchored in place.
    @ViewBuilder
    private var resizeHandleOverlay: some View {
        if showsResizeHandle {
            Circle()
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(Circle().stroke(Color.accentColor, lineWidth: handleScreenStrokeWidth / canvas.scale))
                .frame(width: handleScreenDiameter / canvas.scale, height: handleScreenDiameter / canvas.scale)
                .position(x: displaySize.width, y: displaySize.height)
                .gesture(resizeGesture)
        }
    }

    // Named coordinate space (not .local): the handle sits deeply nested
    // inside the canvas's pan/zoom transform, and assuming SwiftUI's default
    // .local gesture space implicitly divides out that ancestor scale turned
    // out not to hold in practice here — see computeResize below. The named
    // space lets positions be explicitly converted via
    // canvas.canvasPoint(fromScreen:), the same function background gestures
    // (marquee, shape creation, zoom anchor) already use. (BUGS.md Vague 9 #1)
    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(CanvasViewModel.viewportCoordinateSpaceName))
            .onChanged { value in
                if resizeStartSize == nil {
                    resizeStartSize = CGSize(width: node.width, height: node.height)
                    resizeStartOrigin = CGPoint(x: node.x, y: node.y)
                    resizeAnchorLocation = value.location
                    resizeAnchorWasCommandHeld = Self.isCommandHeld && node.kind == .image
                    onInteract()
                }
                reanchorResizeIfModifierChanged(value: value)
                guard let start = resizeStartSize, let startOrigin = resizeStartOrigin,
                      let anchorLocation = resizeAnchorLocation else { return }

                if resizeAnchorWasCommandHeld {
                    applyCropResize(start: start, startOrigin: startOrigin, anchorLocation: anchorLocation, value: value)
                    return
                }
                let result = computeResize(start: start, startOrigin: startOrigin, anchorLocation: anchorLocation, value: value)
                liveResizeSize = result.size
                liveResizeOrigin = result.origin
            }
            .onEnded { value in
                reanchorResizeIfModifierChanged(value: value)
                guard let start = resizeStartSize, let startOrigin = resizeStartOrigin,
                      let anchorLocation = resizeAnchorLocation else { return }

                if resizeAnchorWasCommandHeld {
                    applyCropResize(start: start, startOrigin: startOrigin, anchorLocation: anchorLocation, value: value)
                } else {
                    let result = computeResize(start: start, startOrigin: startOrigin, anchorLocation: anchorLocation, value: value)
                    // Images always ratio-lock outside Crop-Resize (Vague 10
                    // #2), so width and height always scale by the same
                    // factor here — contentScale (Session 2 Vague 3) tracks
                    // that factor so the image keeps zooming with the frame
                    // (same crop window fraction, now at the new scale)
                    // exactly like it did before contentScale existed.
                    if node.kind == .image, start.width > 0 {
                        node.contentScale *= result.size.width / start.width
                    }
                    node.width = result.size.width
                    node.height = result.size.height
                    node.x = result.origin.x
                    node.y = result.origin.y
                }
                try? modelContext.save()
                resizeStartSize = nil
                resizeStartOrigin = nil
                resizeAnchorLocation = nil
                resizeAnchorWasCommandHeld = false
                liveResizeSize = nil
                liveResizeOrigin = nil
                hasCropUndoRegistered = false
            }
    }

    /// See the resizeAnchor* properties' doc comment. Called on every drag
    /// update before routing to computeResize/applyCropResize, so a modifier
    /// change is caught the very next frame after it happens.
    private func reanchorResizeIfModifierChanged(value: DragGesture.Value) {
        let commandHeld = Self.isCommandHeld && node.kind == .image
        guard commandHeld != resizeAnchorWasCommandHeld else { return }
        resizeStartSize = liveResizeSize ?? CGSize(width: node.width, height: node.height)
        resizeStartOrigin = liveResizeOrigin ?? CGPoint(x: node.x, y: node.y)
        resizeAnchorLocation = value.location
        resizeAnchorWasCommandHeld = commandHeld
    }

    private static var isCommandHeld: Bool {
        NSEvent.modifierFlags.contains(.command)
    }

    /// Crop-Resize (BUGS.md Vague 10 #3; rewritten in depth for Session 2
    /// Vague 3 after two prior attempts — Session 2 Vague 2 #1 and its own
    /// re-anchoring — failed to fix a deformation that turned out to run
    /// deeper than gesture continuity): Cmd-held resize on an Image Node
    /// frees the frame to any width/height independently (no ratio lock on
    /// the frame itself), then recomputes a *single* contentScale via the
    /// "cover" formula so the image is always scaled uniformly to fill that
    /// frame — never a separate X/Y scale, which was the actual root cause.
    /// The old version derived the full image's on-screen size independently
    /// per axis (start.width/startCrop.width, start.height/startCrop.height)
    /// with nothing tying the two back to the source's real aspect ratio;
    /// any prior non-square crop fraction (i.e. basically any real use of
    /// this feature) made that pair inconsistent with the source image, so
    /// Image(...).resizable() rendered it visibly stretched. contentScale
    /// and sourceWidth/sourceHeight (BoardNode) remove that possibility
    /// entirely: there is exactly one scale factor, so the rendered image
    /// can never end up anisotropic.
    ///
    /// The crop window (cropX/Y/Width/Height) is recentered to exactly match
    /// the new frame every frame — the "cover, centered" crop — rather than
    /// preserved from the gesture's start as the old reveal/hide model did.
    ///
    /// Anchoring matches the standard Resize Handle's own convention: top-
    /// left fixed by default, center-fixed if Option is also held.
    ///
    /// Mutates the model directly (unlike computeResize's pure-then-commit-
    /// once pattern) because ImageNodeContentView reads contentScale/crop*
    /// straight off the node to render the live preview, with nowhere else
    /// to plumb a "live" override through. Only the first mutation of the
    /// gesture registers with the undo manager (matching the text-autosave
    /// pattern) so undoing the whole drag is still one step.
    ///
    /// Suppressing registration on every frame after the first used to nil
    /// out modelContext.undoManager and restore it right after, but — same
    /// crash as the text-autosave fix (Session 2 Vague 1 #1) — detaching that
    /// binding right after a real registration had already opened a
    /// SwiftData snapshot for this node corrupted its internal bookkeeping,
    /// here freezing/crashing the app almost immediately since a drag fires
    /// far more frames per second than someone can type (Session 2 Vague 1
    /// #2). disableUndoRegistration()/enableUndoRegistration() suppress the
    /// registration without ever touching modelContext.undoManager.
    private func applyCropResize(start: CGSize, startOrigin: CGPoint, anchorLocation: CGPoint, value: DragGesture.Value) {
        let minVisible: CGFloat = 24
        let newSize: CGSize
        let newOrigin: CGPoint

        if Self.isOptionHeld {
            let centerFixed = CGPoint(x: startOrigin.x + start.width / 2, y: startOrigin.y + start.height / 2)
            let cursorCanvasPoint = canvas.canvasPoint(fromScreen: value.location)
            newSize = CGSize(
                width: max(abs(cursorCanvasPoint.x - centerFixed.x) * 2, minVisible),
                height: max(abs(cursorCanvasPoint.y - centerFixed.y) * 2, minVisible)
            )
            newOrigin = CGPoint(x: centerFixed.x - newSize.width / 2, y: centerFixed.y - newSize.height / 2)
        } else {
            let translation = CGSize(
                width: (value.location.x - anchorLocation.x) / canvas.scale,
                height: (value.location.y - anchorLocation.y) / canvas.scale
            )
            newSize = CGSize(
                width: max(start.width + translation.width, minVisible),
                height: max(start.height + translation.height, minVisible)
            )
            newOrigin = startOrigin
        }

        // The "cover" formula: one scale factor, large enough that the
        // source image (at that scale) fills the frame on both axes — never
        // two independent per-axis factors.
        let contentScale = max(newSize.width / node.sourceWidth, newSize.height / node.sourceHeight)
        let fullWidth = node.sourceWidth * contentScale
        let fullHeight = node.sourceHeight * contentScale
        let cropWidth = min(newSize.width / fullWidth, 1)
        let cropHeight = min(newSize.height / fullHeight, 1)

        func apply() {
            node.width = newSize.width
            node.height = newSize.height
            node.x = newOrigin.x
            node.y = newOrigin.y
            node.contentScale = contentScale
            node.cropWidth = cropWidth
            node.cropHeight = cropHeight
            node.cropX = (1 - cropWidth) / 2
            node.cropY = (1 - cropHeight) / 2
        }

        if hasCropUndoRegistered {
            modelContext.undoManager?.disableUndoRegistration()
            apply()
            modelContext.undoManager?.enableUndoRegistration()
        } else {
            apply()
            hasCropUndoRegistered = true
        }
    }

    private static var isOptionHeld: Bool {
        NSEvent.modifierFlags.contains(.option)
    }

    /// Computes the resized (size, origin) pair from the handle's drag `value`.
    ///
    /// `value.translation` arrives in viewport (screen-ish) points, which
    /// don't account for the canvas's own zoom — the exact same physical
    /// mouse movement must produce a *smaller* canvas-space change at a
    /// higher zoom level and a *larger* one zoomed out, since you're
    /// dragging across less/more of the actual board. Dividing by
    /// canvas.scale makes that conversion explicit rather than assumed —
    /// relying on SwiftUI's default gesture coordinate space to already
    /// account for the ancestor .scaleEffect turned out not to hold here in
    /// practice: the same mouse movement produced the same size change at
    /// any zoom level. Diagnosed for BUGS.md Vague 9 #1.
    ///
    /// Option held takes over completely, for every node kind with a Resize
    /// Handle, scaling from the fixed center. By default (Option alone) the
    /// dragged corner tracks the cursor's converted canvas-space position
    /// exactly — no derived scale factor, width/height free to differ (the
    /// previous two attempts, Vague 7 #2 and Vague 8 #1, both computed a
    /// scale factor from mouse movement and got the sensitivity wrong in
    /// different ways; tracking the corner position directly sidesteps that
    /// entirely). Shift+Option instead locks width/height to the node's
    /// starting ratio while still scaling from the center (BUGS.md Vague 10
    /// #1) — same center-fixed idea, but the scale factor is derived from
    /// how far the (converted) cursor is from center relative to how far the
    /// corner started, rather than tracked directly, since a locked ratio
    /// needs one uniform factor rather than two independent axis distances.
    private func computeResize(start: CGSize, startOrigin: CGPoint, anchorLocation: CGPoint, value: DragGesture.Value) -> (size: CGSize, origin: CGPoint) {
        if Self.isOptionHeld {
            let centerFixed = CGPoint(x: startOrigin.x + start.width / 2, y: startOrigin.y + start.height / 2)
            let cursorCanvasPoint = canvas.canvasPoint(fromScreen: value.location)
            // Images can never resize free-form (even without Option) — Cmd
            // is Crop-Resize's key, but Shift's own choice shouldn't grant a
            // ratio that's otherwise impossible for this kind. So Option
            // alone already means ratio-locked for images, and Shift+Option
            // is identical to Option alone (BUGS.md Vague 10 #2).
            if Self.isShiftHeld || node.kind == .image {
                return Self.centerAnchoredRatioLocked(start: start, center: centerFixed, cursorCanvasPoint: cursorCanvasPoint)
            }
            return Self.centerAnchoredFreeForm(center: centerFixed, cursorCanvasPoint: cursorCanvasPoint)
        }

        let translation = CGSize(
            width: (value.location.x - anchorLocation.x) / canvas.scale,
            height: (value.location.y - anchorLocation.y) / canvas.scale
        )

        switch node.kind {
        case .image:
            // Locked to the node's aspect ratio: projects the drag onto the
            // diagonal from the fixed top-left corner through the dragged
            // bottom-right one, so width/height always scale together.
            return (Self.proportionalSize(start: start, translation: translation), startOrigin)
        case .text:
            // Free-form: width and height resize independently. The font
            // stays fixed size — only the frame changes — so Text/TextEditor
            // reflow the content to fit rather than scaling it (BUGS.md #8).
            let size = CGSize(
                width: max(start.width + translation.width, Self.minTextWidth),
                height: max(start.height + translation.height, Self.minTextHeight)
            )
            return (size, startOrigin)
        case .shape:
            // Shift constrains to a perfect square (rectangle shapes) or
            // circle (ellipse shapes) — both are just "width == height" on
            // the bounding box, so one constraint covers both (Phase 2 #5).
            // Otherwise free-form, same as text.
            let size: CGSize
            if Self.isShiftHeld {
                size = Self.constrainedSquareSize(start: start, translation: translation)
            } else {
                size = CGSize(
                    width: max(start.width + translation.width, Self.minShapeSize),
                    height: max(start.height + translation.height, Self.minShapeSize)
                )
            }
            return (size, startOrigin)
        case .arrow:
            // Never reached — see the .arrow case in `content` above.
            return (start, startOrigin)
        }
    }

    private static let minShapeSize: CGFloat = 24

    private static let minTextWidth: CGFloat = 120
    private static let minTextHeight: CGFloat = 60

    /// Option alone: the dragged corner tracks the cursor's canvas-space
    /// position exactly, independently on each axis — no ratio preserved.
    private static func centerAnchoredFreeForm(center: CGPoint, cursorCanvasPoint: CGPoint) -> (size: CGSize, origin: CGPoint) {
        let newSize = CGSize(
            width: abs(cursorCanvasPoint.x - center.x) * 2,
            height: abs(cursorCanvasPoint.y - center.y) * 2
        )
        let newOrigin = CGPoint(x: center.x - newSize.width / 2, y: center.y - newSize.height / 2)
        return (newSize, newOrigin)
    }

    /// Shift+Option (BUGS.md Vague 10 #1) — and always, for images (Vague 10
    /// #2): a single uniform scale factor, derived from how far the cursor's
    /// canvas-space position is from the fixed center relative to how far
    /// the corner started, keeps width/height locked to the node's starting
    /// ratio while still scaling from the center.
    private static func centerAnchoredRatioLocked(start: CGSize, center: CGPoint, cursorCanvasPoint: CGPoint) -> (size: CGSize, origin: CGPoint) {
        let vectorStart = CGVector(dx: start.width / 2, dy: start.height / 2)
        let vectorStartLength = (vectorStart.dx * vectorStart.dx + vectorStart.dy * vectorStart.dy).squareRoot()
        guard vectorStartLength > 0 else {
            return (start, CGPoint(x: center.x - start.width / 2, y: center.y - start.height / 2))
        }
        let vectorCurrent = CGVector(dx: cursorCanvasPoint.x - center.x, dy: cursorCanvasPoint.y - center.y)
        let vectorCurrentLength = (vectorCurrent.dx * vectorCurrent.dx + vectorCurrent.dy * vectorCurrent.dy).squareRoot()
        let scale = vectorCurrentLength / vectorStartLength
        let newSize = CGSize(width: start.width * scale, height: start.height * scale)
        let newOrigin = CGPoint(x: center.x - newSize.width / 2, y: center.y - newSize.height / 2)
        return (newSize, newOrigin)
    }

    private static func proportionalSize(start: CGSize, translation: CGSize) -> CGSize {
        let diagLength = (start.width * start.width + start.height * start.height).squareRoot()
        guard diagLength > 0 else { return start }

        let unitX = start.width / diagLength
        let unitY = start.height / diagLength
        let projected = translation.width * unitX + translation.height * unitY

        let minDiagonal: CGFloat = 32
        let newDiagLength = max(diagLength + projected, minDiagonal)
        let factor = newDiagLength / diagLength
        return CGSize(width: start.width * factor, height: start.height * factor)
    }

    /// Locks width == height (a perfect square, or circle for an ellipse
    /// shape) — the uniform side grows with whichever axis the drag reaches
    /// furthest on, matching the more intuitive of the two directions.
    private static func constrainedSquareSize(start: CGSize, translation: CGSize) -> CGSize {
        let rawWidth = start.width + translation.width
        let rawHeight = start.height + translation.height
        let side = max(rawWidth, rawHeight, minShapeSize)
        return CGSize(width: side, height: side)
    }
}
