//
//  CanvasView.swift
//  DONE
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

// Static stored properties aren't allowed inside a generic type (CanvasView is
// generic over Content), so these live in a plain namespace instead.
private enum GridMetrics {
    /// Base canvas-space grid spacing that Grid Attach also snaps to.
    static let baseSpacing: CGFloat = 24
    /// On-screen dot spacing never drops below this, however far zoomed out —
    /// otherwise on-screen spacing shrinks with scale (baseSpacing * scale),
    /// so dot count grows roughly as 1/scale² and peaks right before the old
    /// `spacing > 4` cutoff (tens of thousands of dots/frame at some zoom
    /// levels), redrawn on every pan/zoom tick. Diagnosed as one of two causes
    /// of the zoomed-out lag in BUGS.md Vague 2 #5 (the other being
    /// over-broad view invalidation, fixed by the @Observable migration on
    /// CanvasViewModel). Doubling the canvas-space spacing instead keeps
    /// on-screen dot density — and so dot count — roughly constant at any
    /// zoom level.
    static let minOnScreenDotSpacing: CGFloat = 16
}

/// The infinite pannable/zoomable viewport. Owns only the viewport transform and
/// background chrome; the actual board content is supplied by the caller so this
/// stays reusable as nodes are layered in.
struct CanvasView<Content: View>: View {
    var viewModel: CanvasViewModel
    var contentBounds: CGRect?
    /// Every node on the board (Phase 3 step 4/6) — needed only for Anchor
    /// Point candidate search during the Arrow Tool's creation drag; nothing
    /// else here reads the board's actual node list.
    var allNodes: [BoardNode] = []

    var onBackgroundDoubleClick: ((CGPoint) -> Void)?
    var onBackgroundClick: (() -> Void)?
    /// Rect (canvas space) currently covered, plus the selection to union it
    /// with — non-empty only for a Cmd-held Marquee Selection drag extending
    /// a prior selection (BUGS.md Vague 5 #3), empty otherwise.
    var onMarqueeSelect: ((CGRect, Set<UUID>) -> Void)?
    /// Fires once, on release, when the Shape Tool is armed and the drag was
    /// large enough to be a real shape rather than a stray click (Phase 2 #2).
    var onShapeCreate: ((ShapeType, CGRect) -> Void)?
    /// Fires once, on release, when the Arrow Tool is armed (Phase 3 step
    /// 1/6, extended step 5/6): start/end in canvas space, already resolved
    /// against Anchor Point / Arrow Connection snapping for the end point —
    /// `connection` is non-nil only when the end point locked onto another
    /// arrow's own point.
    var onArrowCreate: ((CGPoint, CGPoint, ArrowConnection?) -> Void)?
    var onDropFile: (([NSItemProvider], CGPoint) -> Bool)?
    var onCropCancel: (() -> Void)?
    var onCropSave: (() -> Void)?
    @ViewBuilder var content: () -> Content

    @State private var lastMagnification: CGFloat = 1.0
    @State private var lastHoverLocation: CGPoint = .zero
    @State private var viewportSize: CGSize = .zero
    @State private var panMonitor: Any?
    @State private var marqueeStart: CGPoint?
    @State private var marqueeCurrent: CGPoint?
    @State private var marqueeBaseSelection: Set<UUID> = []
    @State private var shapeDragStart: CGPoint?
    @State private var shapeDragCurrent: CGPoint?
    @State private var arrowDragStartCanvas: CGPoint?
    @State private var arrowDragEndCanvas: CGPoint?
    @State private var arrowDragConnection: ArrowConnection?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                gridBackground
                    .contentShape(Rectangle())
                    .gesture(backgroundDragGesture)
                    .simultaneousGesture(backgroundSingleTapGesture)
                    .simultaneousGesture(backgroundDoubleTapGesture)

                ZStack(alignment: .topLeading) {
                    // Zero-sized anchor keeps canvas-space (0, 0) stable regardless
                    // of which nodes exist or how large they are.
                    Color.clear.frame(width: 0, height: 0)
                    content()
                }
                .scaleEffect(viewModel.scale, anchor: .topLeading)
                .offset(x: viewModel.offset.width, y: viewModel.offset.height)

                marqueeOverlay
                shapeCreationOverlay
                arrowCreationOverlay
                anchorPointOverlay
            }
            .coordinateSpace(name: CanvasViewModel.viewportCoordinateSpaceName)
            .clipped()
            // Tracked on the whole canvas (not just the background layer) so it
            // stays accurate while hovering over nodes too — needed for
            // Cursor-anchored Zoom (BUGS.md Vague 2 #2), which anchors pinch-zoom
            // on the last known cursor position (MagnificationGesture itself
            // carries no location).
            .onContinuousHover(coordinateSpace: .local) { phase in
                if case .active(let location) = phase {
                    lastHoverLocation = location
                    viewModel.lastKnownHoverLocation = location
                }
            }
            // .simultaneousGesture, not .gesture: magnificationGesture is
            // attached to this parent container while marqueeGesture is
            // attached to the child background view — two nested, non-
            // simultaneous .gesture() modifiers make SwiftUI favor the more
            // deeply-nested one, so the child's DragGesture could keep
            // priority (and block pinch recognition) while it was anywhere in
            // an active or oddly-terminated recognition state, until a full
            // pan/drag let it complete and release that priority. Matches the
            // intermittent pinch-stops-responding symptom in BUGS.md Vague 4
            // #2. Pinch and a single-pointer drag are physically distinct
            // inputs that don't co-occur in normal use, so recognizing them
            // independently is safe — same reasoning as the tap-gesture fix
            // in Vague 1 #1.
            .simultaneousGesture(magnificationGesture)
            .onDrop(of: [.fileURL], isTargeted: nil) { providers, location in
                onDropFile?(providers, location) ?? false
            }
            .onAppear {
                viewportSize = proxy.size
                viewModel.lastKnownViewportSize = proxy.size
                viewModel.lastKnownContentBounds = contentBounds
            }
            .onChange(of: proxy.size) { _, newSize in
                viewportSize = newSize
                viewModel.lastKnownViewportSize = newSize
            }
            .onChange(of: contentBounds) { _, newBounds in
                viewModel.lastKnownContentBounds = newBounds
            }
        }
        .overlay(alignment: .bottomLeading) { zoomCapsule }
        .overlay(alignment: .bottom) {
            // The Crop Action Bar replaces the Floating Toolbar in the same
            // spot while a Crop Tool session is active, rather than showing
            // both at once (BUGS.md Vague 10 #4).
            if viewModel.cropSession != nil {
                CropActionBar(
                    onCancel: { onCropCancel?() },
                    onSave: { onCropSave?() }
                )
            } else {
                FloatingToolbar(canvas: viewModel)
            }
        }
        .onAppear(perform: installPanMonitor)
        .onDisappear(perform: removePanMonitor)
    }

    // Floating Zoom Capsule, bottom-left — the beginning of what will grow into
    // a fuller floating toolbar in a later phase. Double-click triggers Fit to
    // Screen (BUGS.md Vague 2 #3).
    private var zoomCapsule: some View {
        Text("\(Int((viewModel.scale * 100).rounded()))%")
            .font(.system(size: 12, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
            .padding(.leading, 12)
            .padding(.bottom, 12)
            .onTapGesture(count: 2) {
                viewModel.fitToScreen(contentBounds: contentBounds, viewportSize: viewportSize)
            }
    }

    private var gridBackground: some View {
        Canvas { context, size in
            var canvasSpacing = GridMetrics.baseSpacing
            while canvasSpacing * viewModel.scale < GridMetrics.minOnScreenDotSpacing {
                canvasSpacing *= 2
            }
            let spacing = canvasSpacing * viewModel.scale
            guard spacing > 0 else { return }
            let dotColor = Color.primary.opacity(0.12)
            let startX = viewModel.offset.width.truncatingRemainder(dividingBy: spacing) - spacing
            let startY = viewModel.offset.height.truncatingRemainder(dividingBy: spacing) - spacing
            var x = startX
            while x < size.width {
                var y = startY
                while y < size.height {
                    context.fill(
                        Path(ellipseIn: CGRect(x: x - 1, y: y - 1, width: 2, height: 2)),
                        with: .color(dotColor)
                    )
                    y += spacing
                }
                x += spacing
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    // Click-drag on empty canvas is either Marquee Selection or shape creation,
    // depending on which tool is armed (Phase 2 #2) — mutually exclusive, so
    // one DragGesture branches rather than attaching two competing ones.
    private var backgroundDragGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .local)
            .onChanged { value in
                if case .shape = viewModel.activeTool {
                    shapeDragStart = value.startLocation
                    shapeDragCurrent = value.location
                } else if viewModel.activeTool == .arrow {
                    arrowDragGestureChanged(value)
                } else {
                    marqueeGestureChanged(value)
                }
            }
            .onEnded { value in
                if case .shape(let shapeType) = viewModel.activeTool {
                    let screenRect = Self.shapeDragRect(from: value.startLocation, to: value.location)
                    let corner1 = viewModel.canvasPoint(fromScreen: CGPoint(x: screenRect.minX, y: screenRect.minY))
                    let corner2 = viewModel.canvasPoint(fromScreen: CGPoint(x: screenRect.maxX, y: screenRect.maxY))
                    onShapeCreate?(shapeType, Self.normalizedRect(from: corner1, to: corner2))
                    shapeDragStart = nil
                    shapeDragCurrent = nil
                } else if viewModel.activeTool == .arrow {
                    arrowDragGestureEnded(value)
                } else {
                    marqueeGestureEnded(value)
                }
            }
    }

    // Arrow Tool creation drag (Phase 3 step 1/6, extended with Anchor Point
    // / Arrow Connection snapping in step 4/6 and 5/6): the end point is run
    // through AnchorPointFinder.snappedEndpoint(...) on every frame, exactly
    // like ArrowNodeView's own handle A/B drags — this is the initial-
    // creation counterpart, since the new arrow doesn't exist as a node yet
    // to attach a handle gesture to. The start point does not snap: Arrow
    // Connections only ever attach an arrow's endpoint to *another* arrow's
    // point at creation time via this drag's end, matching how a single
    // click-drag naturally has one point that's "let go of" onto a target
    // and one that's just "planted."
    private func arrowDragGestureChanged(_ value: DragGesture.Value) {
        if arrowDragStartCanvas == nil {
            arrowDragStartCanvas = viewModel.canvasPoint(fromScreen: value.startLocation)
        }
        let rawEnd = viewModel.canvasPoint(fromScreen: value.location)
        let result = AnchorPointFinder.snappedEndpoint(for: rawEnd, excluding: nil, allNodes: allNodes, canvas: viewModel)
        arrowDragEndCanvas = result.point
        arrowDragConnection = result.connection
    }

    private func arrowDragGestureEnded(_ value: DragGesture.Value) {
        arrowDragGestureChanged(value)
        if let start = arrowDragStartCanvas, let end = arrowDragEndCanvas {
            onArrowCreate?(start, end, arrowDragConnection)
        }
        arrowDragStartCanvas = nil
        arrowDragEndCanvas = nil
        arrowDragConnection = nil
        viewModel.anchorSnapState = nil
    }

    // Live preview while creating an arrow — a plain line from start to the
    // (possibly snapped) end point, in screen space so it stays correctly
    // positioned under pan/zoom without needing its own transform.
    @ViewBuilder
    private var arrowCreationOverlay: some View {
        if let startCanvas = arrowDragStartCanvas, let endCanvas = arrowDragEndCanvas {
            let start = viewModel.screenPoint(fromCanvas: startCanvas)
            let end = viewModel.screenPoint(fromCanvas: endCanvas)
            Path { path in
                path.move(to: start)
                path.addLine(to: end)
            }
            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .allowsHitTesting(false)
        }
    }

    // Anchor Point / Arrow Connection snap indicator (Phase 3 steps 4/6,
    // 5/6): small rings at each candidate point near the cursor, with the
    // one actually within hard-snap range drawn filled — and, when that
    // match is another arrow's own point rather than a plain Node corner,
    // in a visually distinct color so it reads as "this creates a
    // persistent link" rather than "this just positions the point once."
    @ViewBuilder
    private var anchorPointOverlay: some View {
        if let state = viewModel.anchorSnapState {
            let tintColor = state.isArrowConnection ? Color.orange : Color.accentColor
            ForEach(Array(state.candidatePoints.enumerated()), id: \.offset) { _, canvasPoint in
                let screenPoint = viewModel.screenPoint(fromCanvas: canvasPoint)
                let isClosest = state.closestPoint.map { $0 == canvasPoint } ?? false
                Circle()
                    .fill(isClosest ? tintColor : Color.clear)
                    .overlay(Circle().stroke(tintColor, lineWidth: 1.5))
                    .frame(width: isClosest ? 10 : 7, height: isClosest ? 10 : 7)
                    .position(screenPoint)
                    .allowsHitTesting(false)
            }
        }
    }

    // Marquee Selection (BUGS.md Vague 3 #2, live-updating per Vague 5 #2):
    // click-drag on empty canvas draws a selection rectangle instead of
    // panning — panning moved to two-finger trackpad swipe and middle-click-
    // drag (Vague 1). Selection updates continuously as the rectangle grows
    // (every onChanged tick), not just once on release. Holding Cmd at the
    // start of the drag (Finder-style additive selection, BUGS.md Vague 5 #3)
    // extends the selection already in place instead of replacing it —
    // marqueeBaseSelection snapshots that prior selection once, at gesture
    // start, so shrinking the rectangle back over already-covered nodes still
    // only affects nodes newly covered *by this drag*, not the base.
    private func marqueeGestureChanged(_ value: DragGesture.Value) {
        if marqueeStart == nil {
            marqueeBaseSelection = NSEvent.modifierFlags.contains(.command) ? viewModel.selectedNodeIDs : []
        }
        marqueeStart = value.startLocation
        marqueeCurrent = value.location
        updateMarqueeSelection(from: value.startLocation, to: value.location)
    }

    private func marqueeGestureEnded(_ value: DragGesture.Value) {
        updateMarqueeSelection(from: value.startLocation, to: value.location)
        marqueeStart = nil
        marqueeCurrent = nil
        marqueeBaseSelection = []
    }

    private func updateMarqueeSelection(from start: CGPoint, to end: CGPoint) {
        let screenRect = Self.normalizedRect(from: start, to: end)
        let corner1 = viewModel.canvasPoint(fromScreen: CGPoint(x: screenRect.minX, y: screenRect.minY))
        let corner2 = viewModel.canvasPoint(fromScreen: CGPoint(x: screenRect.maxX, y: screenRect.maxY))
        onMarqueeSelect?(Self.normalizedRect(from: corner1, to: corner2), marqueeBaseSelection)
    }

    private var marqueeScreenRect: CGRect? {
        guard let start = marqueeStart, let current = marqueeCurrent else { return nil }
        return Self.normalizedRect(from: start, to: current)
    }

    @ViewBuilder
    private var marqueeOverlay: some View {
        if let rect = marqueeScreenRect {
            Rectangle()
                .fill(Color.accentColor.opacity(0.12))
                .overlay(Rectangle().stroke(Color.accentColor, lineWidth: 1))
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .allowsHitTesting(false)
        }
    }

    private var shapeDragScreenRect: CGRect? {
        guard let start = shapeDragStart, let current = shapeDragCurrent else { return nil }
        return Self.shapeDragRect(from: start, to: current)
    }

    // Live preview while creating a shape, drawn as the actual shape type
    // (dashed) rather than a plain marquee box, so it's clear what's about to
    // be created (Phase 2 #2).
    @ViewBuilder
    private var shapeCreationOverlay: some View {
        if let rect = shapeDragScreenRect, case .shape(let shapeType) = viewModel.activeTool {
            shapePreviewOutline(for: shapeType)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .allowsHitTesting(false)
        }
    }

    private func shapePreviewOutline(for shapeType: ShapeType) -> AnyShape {
        switch shapeType {
        case .rectangle: AnyShape(Rectangle())
        case .ellipse: AnyShape(Ellipse())
        }
    }

    private static func normalizedRect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(b.x - a.x),
            height: abs(b.y - a.y)
        )
    }

    /// The rect a shape-creation drag is currently sizing — square (a circle
    /// for an ellipse shape, since that's just an ellipse in a square frame)
    /// while Shift is held, so the constraint is available from the creation
    /// gesture itself, not only afterward via the Resize Handle (BUGS.md
    /// Vague 7 #1). The start point stays the fixed corner the square grows
    /// from/toward, following whichever direction the drag is heading on
    /// each axis. Squaring in screen space is equivalent to canvas space
    /// here since pan/zoom is a uniform (aspect-preserving) transform.
    private static func shapeDragRect(from start: CGPoint, to current: CGPoint) -> CGRect {
        guard NSEvent.modifierFlags.contains(.shift) else {
            return normalizedRect(from: start, to: current)
        }
        let dx = current.x - start.x
        let dy = current.y - start.y
        let side = max(abs(dx), abs(dy))
        let squaredCurrent = CGPoint(
            x: start.x + (dx >= 0 ? side : -side),
            y: start.y + (dy >= 0 ? side : -side)
        )
        return normalizedRect(from: start, to: squaredCurrent)
    }

    // Independent simultaneousGesture recognizers (not `.exclusively`) so a
    // single click resolves immediately instead of waiting out the
    // double-click interval — see BUGS.md #1.
    private var backgroundSingleTapGesture: some Gesture {
        TapGesture(count: 1).onEnded {
            onBackgroundClick?()
        }
    }

    private var backgroundDoubleTapGesture: some Gesture {
        TapGesture(count: 2).onEnded {
            onBackgroundDoubleClick?(viewModel.canvasPoint(fromScreen: lastHoverLocation))
        }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let factor = value / lastMagnification
                lastMagnification = value
                viewModel.zoom(by: factor, anchor: lastHoverLocation, contentBounds: contentBounds, viewportSize: viewportSize)
            }
            .onEnded { _ in lastMagnification = 1.0 }
    }

    // hasPreciseScrollingDeltas (trackpad vs. mouse-wheel heuristic, used
    // through Vague 2) proved unreliable in practice (confirmed with an MX
    // Master + Logi Options+, smooth-scrolling toggle made no difference) —
    // replaced with an explicit modifier instead (BUGS.md Vague 3 #1): plain
    // scroll, any device, always pans; ⌘+scroll, any device, zooms
    // (cursor-anchored, like pinch). Trackpad pinch (MagnificationGesture)
    // remains its own independent zoom gesture either way.
    //
    // Middle-click (mouse wheel button) + drag is a second, mouse-friendly pan
    // method, additive to two-finger trackpad swipe — buttonNumber 2 is
    // AppKit's convention for the middle button, delivered via the
    // .otherMouse* event family rather than .leftMouse*.
    private func installPanMonitor() {
        panMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.scrollWheel, .otherMouseDragged]
        ) { [weak viewModel] event in
            guard let viewModel else { return event }
            switch event.type {
            case .scrollWheel where event.modifierFlags.contains(.command):
                let clampedDelta = max(min(event.scrollingDeltaY, 40), -40)
                let factor = 1 + clampedDelta * 0.01
                viewModel.zoom(
                    by: factor,
                    anchor: viewModel.lastKnownHoverLocation,
                    contentBounds: viewModel.lastKnownContentBounds,
                    viewportSize: viewModel.lastKnownViewportSize
                )
            case .scrollWheel:
                viewModel.panIncremental(by: CGSize(width: event.scrollingDeltaX, height: event.scrollingDeltaY))
            case .otherMouseDragged where event.buttonNumber == 2:
                viewModel.panIncremental(by: CGSize(width: event.deltaX, height: event.deltaY))
            default:
                break
            }
            return event
        }
    }

    private func removePanMonitor() {
        if let panMonitor {
            NSEvent.removeMonitor(panMonitor)
        }
        panMonitor = nil
    }
}
