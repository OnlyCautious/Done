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

    // Crop-Resize (Cmd-held, images only, BUGS.md Vague 10 #3) mutates
    // node.width/height/cropWidth/cropHeight directly and continuously,
    // rather than through the live-size-then-commit-once pattern above —
    // ImageNodeContentView needs the crop fraction live to render the
    // in-progress crop preview, and there's nowhere else to put a "live
    // crop" override. hasCropUndoRegistered mirrors the text-autosave
    // pattern: only the first mutation of the gesture registers with the
    // undo manager, so undoing the whole drag is still one step.
    @State private var resizeStartCropSize: CGSize?
    @State private var hasCropUndoRegistered = false

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
        return Self.isShiftHeld ? Self.snapped(point) : point
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
                        ? Self.snappedDelta(from: start, translation: value.translation)
                        : value.translation
                } else {
                    liveTranslation = value.translation
                }
            }
            .onEnded { value in
                guard let start = dragStartPosition else { return }
                let delta = Self.isShiftHeld
                    ? Self.snappedDelta(from: start, translation: value.translation)
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
    // (not just on drop) so the snap is visible as it happens.
    private static let gridSpacing: CGFloat = 24

    private static var isShiftHeld: Bool {
        NSEvent.modifierFlags.contains(.shift)
    }

    private static func snapped(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: (point.x / gridSpacing).rounded() * gridSpacing,
            y: (point.y / gridSpacing).rounded() * gridSpacing
        )
    }

    /// The delta that would land `start` on the grid — applied identically to
    /// every selected node in a group drag (BUGS.md Vague 6 #1) so the whole
    /// group shifts by the same amount and keeps its relative layout, rather
    /// than each node snapping independently and staggering apart.
    private static func snappedDelta(from start: CGPoint, translation: CGSize) -> CGSize {
        let raw = CGPoint(x: start.x + translation.width, y: start.y + translation.height)
        let snappedPoint = snapped(raw)
        return CGSize(width: snappedPoint.x - start.x, height: snappedPoint.y - start.y)
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
                    x: node.x, y: node.y, width: node.width, height: node.height,
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
                    resizeStartCropSize = CGSize(width: node.cropWidth, height: node.cropHeight)
                    onInteract()
                }
                guard let start = resizeStartSize, let startOrigin = resizeStartOrigin else { return }

                if Self.isCommandHeld && node.kind == .image {
                    applyCropResize(start: start, startCrop: resizeStartCropSize ?? CGSize(width: 1, height: 1), value: value)
                    return
                }
                let result = computeResize(start: start, startOrigin: startOrigin, value: value)
                liveResizeSize = result.size
                liveResizeOrigin = result.origin
            }
            .onEnded { value in
                guard let start = resizeStartSize, let startOrigin = resizeStartOrigin else { return }

                if Self.isCommandHeld && node.kind == .image {
                    applyCropResize(start: start, startCrop: resizeStartCropSize ?? CGSize(width: 1, height: 1), value: value)
                } else {
                    let result = computeResize(start: start, startOrigin: startOrigin, value: value)
                    node.width = result.size.width
                    node.height = result.size.height
                    node.x = result.origin.x
                    node.y = result.origin.y
                }
                try? modelContext.save()
                resizeStartSize = nil
                resizeStartOrigin = nil
                resizeStartCropSize = nil
                liveResizeSize = nil
                liveResizeOrigin = nil
                hasCropUndoRegistered = false
            }
    }

    private static var isCommandHeld: Bool {
        NSEvent.modifierFlags.contains(.command)
    }

    /// Crop-Resize (BUGS.md Vague 10 #3): Cmd-held resize on an Image Node
    /// changes the visible frame without changing the image's own display
    /// scale — it reveals or hides part of the picture rather than scaling
    /// it. `fullWidth`/`fullHeight` (the full uncropped image's size at the
    /// scale in effect when the gesture began) stay fixed for the whole
    /// gesture, derived from the crop fraction captured at that same moment
    /// — the model itself can't be used as that reference mid-gesture since
    /// this mutates node.cropWidth/cropHeight directly on every call.
    /// Mutates the model directly (unlike computeResize's pure-then-commit-
    /// once pattern) because ImageNodeContentView reads cropWidth/cropHeight
    /// straight off the node to render the live preview, with nowhere else
    /// to plumb a "live" override through. Only the first mutation of the
    /// gesture registers with the undo manager (matching the text-autosave
    /// pattern) so undoing the whole drag is still one step.
    private func applyCropResize(start: CGSize, startCrop: CGSize, value: DragGesture.Value) {
        let fullWidth = start.width / max(startCrop.width, 0.001)
        let fullHeight = start.height / max(startCrop.height, 0.001)

        let translation = CGSize(
            width: (value.location.x - value.startLocation.x) / canvas.scale,
            height: (value.location.y - value.startLocation.y) / canvas.scale
        )

        let minVisible: CGFloat = 24
        let newWidth = min(max(start.width + translation.width, minVisible), fullWidth)
        let newHeight = min(max(start.height + translation.height, minVisible), fullHeight)

        func apply() {
            node.width = newWidth
            node.height = newHeight
            node.cropWidth = newWidth / fullWidth
            node.cropHeight = newHeight / fullHeight
        }

        if hasCropUndoRegistered {
            let manager = modelContext.undoManager
            modelContext.undoManager = nil
            apply()
            modelContext.undoManager = manager
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
    private func computeResize(start: CGSize, startOrigin: CGPoint, value: DragGesture.Value) -> (size: CGSize, origin: CGPoint) {
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
            width: (value.location.x - value.startLocation.x) / canvas.scale,
            height: (value.location.y - value.startLocation.y) / canvas.scale
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
