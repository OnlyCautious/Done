//
//  CanvasViewModel.swift
//  DONE
//

import Foundation
import CoreGraphics
import Observation

/// The two Shape Node varieties available from the Shape Tool (Phase 2).
/// Codable because BoardNode persists it directly via SwiftData.
enum ShapeType: String, Codable, CaseIterable {
    case rectangle
    case ellipse
}

/// Which tool the Floating Toolbar currently has armed. `.selection` (the
/// default — see GLOSSARY.md's Selection Tool) is plain click/drag/marquee
/// behavior; `.shape` arms click-drag-to-create for that shape type and
/// reverts to `.selection` automatically once a shape is created. `.arrow`
/// (Phase 3 step 1/6) is the same one-shot pattern — armed, then a single
/// click-drag creates one Arrow Node and reverts to `.selection`.
enum CanvasTool: Equatable {
    case selection
    case shape(ShapeType)
    case arrow
}

/// A crop fraction (0...1 on each axis, relative to the source image's own
/// bounds) — used for both a node's committed crop and the Crop Tool's
/// in-progress draft.
struct CropFraction {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

/// An in-progress Crop Tool session (BUGS.md Vague 10 #4): draftCrop is
/// purely local to the session and never written to the model until Save —
/// Cancel, Escape, or clicking elsewhere all just discard it. fullWidth/
/// fullHeight/fullOrigin (the full source image's size and canvas-space
/// origin at the display scale in effect when the session began) are fixed
/// for the whole session, snapshotted once at the start, since nothing
/// mutates the underlying node until Save.
struct CropSession {
    var nodeID: UUID
    var fullWidth: CGFloat
    var fullHeight: CGFloat
    var fullOrigin: CGPoint
    var originalCrop: CropFraction
    var draftCrop: CropFraction
}

/// Live, in-progress geometry for the arrow currently under a handle A/B or
/// body drag (Phase 3 step 3/6 — the Arrow Style Panel's position tracks the
/// selection's bounding box live during a drag, not just after it commits)
/// — published here rather than read straight off the dragged BoardNode
/// because the drag only writes the model at gesture end (same live-preview-
/// then-commit-once pattern as NodeView's default resize), so mid-drag the
/// model's own start/end/control fields are still stale.
struct LiveArrowGeometry {
    var nodeID: UUID
    var start: CGPoint
    var end: CGPoint
    var control: CGPoint
}

/// Owns the canvas viewport (pan + zoom) and the screen<->canvas coordinate mapping.
/// Node positions are always stored in stable, unscaled canvas space; this is the
/// only place that knows how canvas space maps to the current on-screen viewport.
///
/// @Observable rather than the legacy ObservableObject/@Published: that older
/// mechanism invalidates *every* observing view on *any* published-property
/// change, even views whose body never reads the property that changed. With
/// one NodeView per board Node all observing this same view model, panning or
/// zooming re-evaluated every node's body on every gesture tick regardless of
/// selection — the more nodes on screen (typically after zooming out to see
/// them all), the worse it got. @Observable's fine-grained tracking means a
/// NodeView that never reads `scale`/`offset` in its body (i.e. every node
/// except the selected one, whose resize handle needs `scale`) simply isn't
/// re-evaluated when they change. Diagnosed for BUGS.md Vague 2 #5.
@MainActor
@Observable
final class CanvasViewModel {
    /// Named coordinate space for the canvas viewport (CanvasView's content
    /// area, before the pan/zoom .scaleEffect/.offset transform). Gestures
    /// deeply nested inside that transform — like the Resize Handle — use
    /// this instead of the default `.local` space so their positions can be
    /// explicitly converted via canvasPoint(fromScreen:), the same way
    /// background gestures (marquee, shape creation, zoom anchor) already
    /// do. Relying on `.local` to implicitly divide out an ancestor's scale
    /// turned out not to hold for the Resize Handle in practice — the same
    /// mouse movement produced the same size change at any zoom level,
    /// instead of a smaller one when zoomed in — so this makes the
    /// conversion explicit instead of assumed. Diagnosed for BUGS.md Vague 9 #1.
    static let viewportCoordinateSpaceName = "DoneCanvasViewport"

    var scale: CGFloat = 1.0
    var offset: CGSize = .zero

    var selectedNodeIDs: Set<UUID> = []
    var editingNodeID: UUID?
    var activeTool: CanvasTool = .selection

    /// The active Crop Tool session, if any (BUGS.md Vague 10 #4) — entered
    /// via beginCropping(), exited by Save (ContentView writes draftCrop to
    /// the node, then clears this) or Cancel/Escape (cancelCropping() just
    /// clears this, discarding the draft). Also cleared by every selection-
    /// changing method below, since clicking elsewhere/selecting a different
    /// node should cancel too — entering crop mode itself doesn't go through
    /// any of them, so that's never accidentally self-defeating.
    var cropSession: CropSession?

    /// Starts a Crop Tool session for the given (already-selected) Image
    /// Node, snapshotting the fixed reference points the whole session scales
    /// and positions against.
    ///
    /// Takes sourceWidth/sourceHeight/contentScale (Session 2 Vague 3) rather
    /// than the frame's own width/height: fullWidth/fullHeight used to be
    /// re-derived from width/crop.width and height/crop.height independently
    /// per axis, with nothing tying the pair back to the source image's real
    /// aspect ratio — the same root cause as the Crop-Resize deformation bug
    /// this Vague fixed. fullWidth/fullHeight are now always exactly
    /// sourceWidth/sourceHeight at contentScale, so they can never disagree
    /// with what NodeView's own Crop-Resize just computed.
    func beginCropping(nodeID: UUID, x: Double, y: Double, sourceWidth: Double, sourceHeight: Double, contentScale: Double, crop: CropFraction) {
        let fullWidth = sourceWidth * contentScale
        let fullHeight = sourceHeight * contentScale
        let fullOrigin = CGPoint(x: x - crop.x * fullWidth, y: y - crop.y * fullHeight)
        cropSession = CropSession(
            nodeID: nodeID,
            fullWidth: fullWidth,
            fullHeight: fullHeight,
            fullOrigin: fullOrigin,
            originalCrop: crop,
            draftCrop: crop
        )
    }

    /// Cancel (button, Escape): discards the draft, keeps the node selected.
    func cancelCropping() {
        cropSession = nil
    }

    // Shared live feedback for dragging a multi-node selection (BUGS.md
    // Vague 6 #1): the NodeView whose gesture is actually driving the drag
    // (the one the user grabbed) writes the in-progress delta here, and
    // every other selected NodeView reads it to move in lockstep, preserving
    // relative positions. Only that one gesture ever writes; the model
    // commit happens once, for every selected node, when it ends.
    var isGroupDragActive: Bool = false
    var groupDragDelta: CGSize = .zero

    /// Set by ArrowNodeView while a handle A/B or body drag is in progress
    /// on that specific arrow; nil otherwise. ContentView reads this (falling
    /// back to the model's own committed geometry when nil) to position the
    /// Arrow Style Panel live during the drag rather than have it lag one
    /// frame behind or jump at drag end (Phase 3 step 3/6).
    var liveArrowGeometry: LiveArrowGeometry?

    /// Visual feedback state for an in-progress Anchor Point / Arrow
    /// Connection snap (Phase 3 steps 4/6, 5/6) — set by AnchorPointFinder.
    /// snappedEndpoint(...) on every frame of an arrow endpoint drag,
    /// cleared when nothing is within display range. CanvasView reads this
    /// to draw the candidate-point indicators.
    var anchorSnapState: AnchorSnapState?

    // Mirrors of view-owned, frequently-changing values (content bounds,
    // viewport size, cursor position) that the NSEvent-based pan/zoom monitor
    // in CanvasView needs to read live. That monitor closure is installed once
    // (.onAppear), while CanvasView itself is a value type recreated on every
    // render — capturing its struct properties directly would freeze them at
    // whatever they were the moment the closure was created. Capturing this
    // view model (a stable reference) and reading these at call time instead
    // always sees the latest values. @ObservationIgnored: nothing renders off
    // them directly, they're only read imperatively inside that closure.
    @ObservationIgnored var lastKnownContentBounds: CGRect?
    @ObservationIgnored var lastKnownViewportSize: CGSize = .zero
    @ObservationIgnored var lastKnownHoverLocation: CGPoint = .zero

    static let maxScale: CGFloat = 4.0
    private static let fallbackMinScale: CGFloat = 0.2
    private static let absoluteMinScale: CGFloat = 0.05
    /// Extra margin kept around the content's bounding box — ~15% of its own
    /// size on each axis — when computing how far out zoom is allowed to go
    /// and what Fit to Screen frames. Proportional rather than a fixed point
    /// value (Proportional Canvas, BUGS.md Vague 2 #6): a fixed margin is
    /// negligible next to a large, spread-out board (limits hug the
    /// peripheral elements too closely) and disproportionately large next to
    /// a tiny one; scaling with content size keeps it consistent either way.
    private static let contentPaddingRatio: CGFloat = 0.15

    func canvasPoint(fromScreen screenPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: (screenPoint.x - offset.width) / scale,
            y: (screenPoint.y - offset.height) / scale
        )
    }

    /// Inverse of canvasPoint(fromScreen:) — used by the Arrow Style Panel's
    /// positioning logic (Phase 3 step 3/6) to convert a selection's canvas-
    /// space bounding box into viewport coordinates for placement.
    func screenPoint(fromCanvas canvasPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: canvasPoint.x * scale + offset.width,
            y: canvasPoint.y * scale + offset.height
        )
    }

    /// The currently-visible portion of canvas space, derived from the last-
    /// known viewport size and the current pan/zoom — used by
    /// AnchorPointFinder.candidates(...) (Phase 3 step 4/6) to skip distance
    /// checks against nodes that are off-screen entirely.
    var visibleCanvasRect: CGRect {
        let topLeft = canvasPoint(fromScreen: .zero)
        let bottomRight = canvasPoint(fromScreen: CGPoint(x: lastKnownViewportSize.width, y: lastKnownViewportSize.height))
        return CGRect(x: topLeft.x, y: topLeft.y, width: bottomRight.x - topLeft.x, height: bottomRight.y - topLeft.y)
    }

    func pan(by translation: CGSize, startingFrom start: CGSize) {
        offset = CGSize(width: start.width + translation.width, height: start.height + translation.height)
    }

    /// Pans by a raw per-event delta (trackpad two-finger scroll, middle-click
    /// drag) rather than a gesture's translation-since-start.
    func panIncremental(by delta: CGSize) {
        offset = CGSize(width: offset.width + delta.width, height: offset.height + delta.height)
    }

    /// Zooms by `factor`, keeping the canvas point under `anchor` (in local/screen
    /// coordinates of the viewport) fixed on screen. `contentBounds` (canvas
    /// space, nil if the board is empty) and the current `viewportSize` bound how
    /// far out this is allowed to go, so zoom-out stays proportionate to what's
    /// actually on the board instead of shrinking a few notes to a speck in an
    /// empty void.
    func zoom(by factor: CGFloat, anchor: CGPoint, contentBounds: CGRect?, viewportSize: CGSize) {
        let floor = Self.minScale(contentBounds: contentBounds, viewportSize: viewportSize)
        let newScale = min(max(scale * factor, floor), Self.maxScale)
        guard newScale != scale else { return }
        let canvasAnchor = canvasPoint(fromScreen: anchor)
        scale = newScale
        offset = CGSize(
            width: anchor.x - canvasAnchor.x * scale,
            height: anchor.y - canvasAnchor.y * scale
        )
    }

    /// How far zoom-out may go: enough to fit the content's bounding box (plus
    /// padding) in the viewport, so a tight cluster of nodes can't be zoomed out
    /// to a speck, while a board spread over a wide area allows zooming out
    /// further to see it all.
    static func minScale(contentBounds: CGRect?, viewportSize: CGSize) -> CGFloat {
        guard let contentBounds, viewportSize.width > 0, viewportSize.height > 0 else {
            return fallbackMinScale
        }
        let padded = paddedContentRect(contentBounds)
        guard let fit = fitScale(paddedRect: padded, viewportSize: viewportSize) else {
            return fallbackMinScale
        }
        return min(max(fit, absoluteMinScale), maxScale)
    }

    /// Zooms and pans so the whole board — its content bounding box, expanded by
    /// the same margin used for the zoom-out floor — is framed and centered in
    /// the viewport. Backs both the Fit to Screen action and the zoom-out floor,
    /// so they always agree on what "fits."
    func fitToScreen(contentBounds: CGRect?, viewportSize: CGSize) {
        guard let contentBounds, viewportSize.width > 0, viewportSize.height > 0 else {
            scale = 1.0
            offset = .zero
            return
        }
        let padded = Self.paddedContentRect(contentBounds)
        guard let fit = Self.fitScale(paddedRect: padded, viewportSize: viewportSize) else { return }
        scale = min(fit, Self.maxScale)
        offset = CGSize(
            width: viewportSize.width / 2 - padded.midX * scale,
            height: viewportSize.height / 2 - padded.midY * scale
        )
    }

    private static func paddedContentRect(_ contentBounds: CGRect) -> CGRect {
        contentBounds.insetBy(
            dx: -contentBounds.width * contentPaddingRatio,
            dy: -contentBounds.height * contentPaddingRatio
        )
    }

    private static func fitScale(paddedRect: CGRect, viewportSize: CGSize) -> CGFloat? {
        guard paddedRect.width > 0, paddedRect.height > 0 else { return nil }
        return min(viewportSize.width / paddedRect.width, viewportSize.height / paddedRect.height)
    }

    /// Guarded to a no-op when `id` is already the sole selection (Session 2
    /// Vague 5): without this, re-selecting an already-selected node — which
    /// NodeView's own drag-start and tap gestures do unconditionally, every
    /// time — cleared cropSession/editingNodeID and reset selectedNodeIDs to
    /// an equal-but-new Set on every single frame of an ordinary drag,
    /// needlessly re-triggering @Observable's change tracking across every
    /// observing view for no actual state change.
    func select(_ id: UUID?) {
        guard selectedNodeIDs != (id.map { [$0] } ?? []) || editingNodeID != nil || cropSession != nil else { return }
        selectedNodeIDs = id.map { [$0] } ?? []
        if editingNodeID != id {
            editingNodeID = nil
        }
        cropSession = nil
    }

    /// Replaces the whole selection at once — used by Marquee Selection,
    /// which can select zero, one, or many nodes in a single rubber-band drag.
    func setSelection(_ ids: Set<UUID>) {
        selectedNodeIDs = ids
        editingNodeID = nil
        cropSession = nil
    }

    /// Adds or removes a single node from the current selection without
    /// touching the rest — Finder-style Cmd+click (BUGS.md Vague 5 #3).
    func toggleSelection(_ id: UUID) {
        if selectedNodeIDs.contains(id) {
            selectedNodeIDs.remove(id)
        } else {
            selectedNodeIDs.insert(id)
        }
        editingNodeID = nil
        cropSession = nil
    }

    func deselectAll() {
        selectedNodeIDs = []
        editingNodeID = nil
        cropSession = nil
    }
}
