//
//  ArrowNode.swift
//  DONE
//

import SwiftUI
import SwiftData
import AppKit

/// Trait/thickness style (Phase 3 step 3/6) — persisted directly on
/// BoardNode, same String-raw-value/Codable approach as ShapeType.
enum ArrowStrokeStyle: String, Codable, CaseIterable {
    case solid
    case dashed
}

/// Arrow Tool (Phase 3, SPEC.md roadmap item 2). Step 1/6 laid the straight
/// line and startPoint/endPoint handles; step 2/6 added curving via a
/// quadratic Bézier control point and its own Curve Handle; step 3/6 added
/// stroke style (solid/dashed) and width via the Arrow Style Panel
/// (ArrowStylePanel.swift); step 4/6 added Anchor Point snapping onto other
/// Nodes; step 5/6 added persistent Arrow-to-Arrow Connections
/// (ArrowConnection.swift). Still no text on the arrow — a later step.
///
/// Rendered by its own view rather than reusing NodeView: an arrow's
/// geometry is two independent endpoints (plus a curve control point), not
/// a rectangular frame with a single bottom-right Resize Handle, so the
/// interaction model (three handles, body-drag moving every point together)
/// doesn't fit NodeView's chrome. ContentView routes .arrow-kind nodes here
/// directly instead of through NodeView.
struct ArrowNodeView: View {
    @Bindable var node: BoardNode
    var canvas: CanvasViewModel
    var onInteract: () -> Void
    /// Commits a group move (BUGS.md Vague 6 #1), same contract as
    /// NodeView's: applies `delta` to every currently-selected node in one
    /// step, as a single undo entry.
    var onGroupDragEnd: (CGSize) -> Void
    /// Every node on the board, for Anchor Point candidate search (Phase 3
    /// step 4/6) during handle A/B drags — passed down from ContentView's
    /// own @Query rather than queried again here.
    var allNodes: [BoardNode]

    @Environment(\.modelContext) private var modelContext

    // Live overrides during a drag, mirroring NodeView's liveResizeSize/
    // Origin pattern — nil outside an active gesture, when display falls
    // back to the node's own committed points.
    @State private var liveStartPoint: CGPoint?
    @State private var liveEndPoint: CGPoint?
    @State private var liveControlPoint: CGPoint?

    @State private var bodyDragStart: (start: CGPoint, end: CGPoint, control: CGPoint)?
    @State private var isGroupDragForThisGesture = false
    @State private var handleAStart: CGPoint?
    @State private var handleBStart: CGPoint?

    private var isSelected: Bool { canvas.selectedNodeIDs.contains(node.id) }

    /// Every *arrow* node on the board, keyed by id — for
    /// ArrowConnectionResolver lookups. Rebuilt from `allNodes` on every
    /// access rather than cached: same acceptable-for-this-scale tradeoff
    /// as AnchorPointFinder.candidates(_:), simpler than keeping a
    /// second source of truth in sync.
    private var arrowsByID: [UUID: BoardNode] {
        Dictionary(uniqueKeysWithValues: allNodes.filter { $0.kind == .arrow }.map { ($0.id, $0) })
    }

    /// Point A's effective position (Phase 3 step 5/6): when startConnection
    /// is set, derived every frame from the target via
    /// ArrowConnectionResolver rather than read from arrowStartX/Y at all —
    /// arrowStartX/Y are stale leftovers whenever a connection exists (kept
    /// around only so there's a sane last value if the connection is later
    /// broken), never the source of truth while it's non-nil.
    private var displayStart: CGPoint {
        if let liveStartPoint { return liveStartPoint }
        let base: CGPoint
        if let connection = node.startConnection {
            base = ArrowConnectionResolver.resolvedPoint(role: connection.targetPoint, of: connection.targetArrowID, nodesByID: arrowsByID)
        } else {
            base = CGPoint(x: node.arrowStartX, y: node.arrowStartY)
        }
        if canvas.isGroupDragActive && isSelected {
            return CGPoint(x: base.x + canvas.groupDragDelta.width, y: base.y + canvas.groupDragDelta.height)
        }
        return base
    }

    /// Point B's effective position — same contract as displayStart, for
    /// endConnection.
    private var displayEnd: CGPoint {
        if let liveEndPoint { return liveEndPoint }
        let base: CGPoint
        if let connection = node.endConnection {
            base = ArrowConnectionResolver.resolvedPoint(role: connection.targetPoint, of: connection.targetArrowID, nodesByID: arrowsByID)
        } else {
            base = CGPoint(x: node.arrowEndX, y: node.arrowEndY)
        }
        if canvas.isGroupDragActive && isSelected {
            return CGPoint(x: base.x + canvas.groupDragDelta.width, y: base.y + canvas.groupDragDelta.height)
        }
        return base
    }

    /// The quadratic Bézier control point (Phase 3 step 2/6) — follows the
    /// same live-override/group-drag-follow pattern as displayStart/End, so
    /// the curve's shape stays consistent with the rest of the arrow while
    /// it's being dragged as part of a multi-select group.
    private var displayControl: CGPoint {
        if let liveControlPoint { return liveControlPoint }
        let base = CGPoint(x: node.arrowControlX, y: node.arrowControlY)
        if canvas.isGroupDragActive && isSelected {
            return CGPoint(x: base.x + canvas.groupDragDelta.width, y: base.y + canvas.groupDragDelta.height)
        }
        return base
    }

    // A modest margin around the three points' bounding box so the stroke
    // width, hit-test margin, and handle circles never sit flush against
    // the container's own edge — SwiftUI doesn't clip a view's children to
    // its frame by default, so this is tidiness rather than correctness.
    private static let margin: CGFloat = 20

    private static func boundingRect(start: CGPoint, end: CGPoint, control: CGPoint) -> CGRect {
        let minX = min(start.x, end.x, control.x)
        let minY = min(start.y, end.y, control.y)
        let maxX = max(start.x, end.x, control.x)
        let maxY = max(start.y, end.y, control.y)
        return CGRect(
            x: minX - margin,
            y: minY - margin,
            width: maxX - minX + margin * 2,
            height: maxY - minY + margin * 2
        )
    }

    private static let hitTestLineWidth: CGFloat = 20

    var body: some View {
        let start = displayStart
        let end = displayEnd
        let control = displayControl
        let rect = Self.boundingRect(start: start, end: end, control: control)
        let localStart = CGPoint(x: start.x - rect.minX, y: start.y - rect.minY)
        let localEnd = CGPoint(x: end.x - rect.minX, y: end.y - rect.minY)
        let localControl = CGPoint(x: control.x - rect.minX, y: control.y - rect.minY)
        // strokeWidth/strokeStyle (Phase 3 step 3/6, Arrow Style Panel): the
        // arrowhead's own size always follows strokeWidth (a thicker line
        // gets a proportionally bigger head), and a dashed style's dash
        // pattern is sized off strokeWidth too rather than a fixed dash
        // length, so it stays proportioned at any thickness instead of
        // looking crowded on a thin line or vanishingly small on a thick one.
        let strokeWidth = CGFloat(node.arrowStrokeWidth)
        let (shaftPath, headPath) = Self.arrowPaths(from: localStart, control: localControl, to: localEnd, headLength: strokeWidth * 6)
        // Dash only applies to the shaft (Arrow Tool Vague 5 #1) — the head
        // is always stroked solid, regardless of strokeStyle.
        let shaftStyle = StrokeStyle(
            lineWidth: strokeWidth,
            lineCap: .round,
            lineJoin: .round,
            dash: node.arrowStrokeStyle == .dashed ? [strokeWidth * 3, strokeWidth * 2.5] : []
        )
        let headStyle = StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round)
        // Only the halo/hit-test care about the whole arrow as one shape —
        // neither is ever dashed, so combining shaft+head back into one path
        // for those two purposes is safe. Built via an immediately-invoked
        // closure (not a bare `combinedPath.addPath(headPath)` statement)
        // since `body`'s implicit ViewBuilder would otherwise try to treat
        // that mutating call's Void result as a View.
        let combinedPath: Path = {
            var path = shaftPath
            path.addPath(headPath)
            return path
        }()
        // The visual midpoint of the curve (t=0.5) — where the Curve Handle
        // is shown, not controlPoint itself, since that's more intuitive to
        // grab (it always sits right on the visible stroke).
        let localCurveMidpoint = Self.curveMidpoint(start: localStart, control: localControl, end: localEnd)

        ZStack {
            if isSelected {
                combinedPath
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: strokeWidth + 5, lineCap: .round, lineJoin: .round))
                    .opacity(0.35)
                    .allowsHitTesting(false)
            }
            // Theme-adaptive (dark/light both supported).
            shaftPath
                .stroke(Color.primary, style: shaftStyle)
                .allowsHitTesting(false)
            headPath
                .stroke(Color.primary, style: headStyle)
                .allowsHitTesting(false)

            // A fat invisible stroke as the hit-test region, fixed
            // regardless of strokeWidth — even the thickest width the Arrow
            // Style Panel allows is still thinner than a comfortable click
            // target. Same reasoning as the explicit contentShape fix for
            // Image Node's hit-testing (BUGS.md Session 2 Vague 2 #3).
            Color.clear
                .contentShape(combinedPath.strokedPath(StrokeStyle(lineWidth: Self.hitTestLineWidth, lineCap: .round, lineJoin: .round)))
                .gesture(bodyDragGesture)
                .simultaneousGesture(singleTapGesture)

            handleOverlay(at: localStart, isStart: true)
            handleOverlay(at: localEnd, isStart: false)
            if isSelected {
                curveHandleOverlay(at: localCurveMidpoint)
            }
        }
        .frame(width: rect.width, height: rect.height)
        .offset(x: rect.minX, y: rect.minY)
    }

    // MARK: - Geometry

    /// Quadratic Bézier curve (straight when control sits at the segment's
    /// midpoint) plus an open chevron arrowhead at `end` only — no head at
    /// `start`, per spec. The head's angle follows the curve's tangent at
    /// t=1 — the direction of (end − control) — rather than the raw
    /// (end − start) direction, so it visually points along the curve
    /// instead of "cutting the corner" on a curved arrow (Phase 3 step 2/6).
    /// On a straight arrow the two directions coincide (control is on the
    /// segment), so this doesn't change step 1/6's behavior at all.
    ///
    /// Returned as two separate paths, not one (Arrow Tool Vague 5 #1):
    /// `shaft` is the curve trimmed to stop where the head begins, meant to
    /// take strokeStyle's dash pattern; `head` is the chevron on its own,
    /// always meant to be stroked solid regardless of style — a single
    /// combined path would apply one StrokeStyle to both, dashing the head
    /// right along with the shaft. `shaft` is trimmed (not just left running
    /// the full curve to `end` underneath a solid head drawn on top) so a
    /// dash's gap can't fall exactly at the tip and peek out from beside the
    /// head. The trim point is a first-order arc-length approximation: a
    /// quadratic Bézier's speed at t=1 is 2|end−control|, so stepping back
    /// by `headLength` in arc length is approximately
    /// deltaT = headLength / (2|end−control|) — exact closed-form arc-length
    /// parameterization doesn't exist for a Bézier, but this is accurate
    /// enough for a trim of this size relative to a typical arrow's length.
    /// Points are in whatever local coordinate space the caller already
    /// converted to. `headLength` is the caller's responsibility (Phase 3
    /// step 3/6: tied to strokeWidth).
    private static func arrowPaths(from start: CGPoint, control: CGPoint, to end: CGPoint, headLength: CGFloat) -> (shaft: Path, head: Path) {
        let angle = atan2(end.y - control.y, end.x - control.x)
        let headAngle: CGFloat = .pi / 7
        let left = CGPoint(x: end.x - headLength * cos(angle - headAngle), y: end.y - headLength * sin(angle - headAngle))
        let right = CGPoint(x: end.x - headLength * cos(angle + headAngle), y: end.y - headLength * sin(angle + headAngle))
        var head = Path()
        head.move(to: left)
        head.addLine(to: end)
        head.addLine(to: right)

        let tangentSpeed = hypot(end.x - control.x, end.y - control.y) * 2
        let deltaT = tangentSpeed > 0 ? min(headLength / tangentSpeed, 1) : 0
        let t = max(1 - deltaT, 0)
        // De Casteljau split of [start, control, end] at t: the shaft is the
        // sub-curve from t=0 to t, a valid quadratic Bézier in its own right
        // with control point q1 and endpoint shaftEnd — both derived from
        // the same two lerps that give any point on the original curve.
        let q1 = CGPoint(x: start.x + (control.x - start.x) * t, y: start.y + (control.y - start.y) * t)
        let r1 = CGPoint(x: control.x + (end.x - control.x) * t, y: control.y + (end.y - control.y) * t)
        let shaftEnd = CGPoint(x: q1.x + (r1.x - q1.x) * t, y: q1.y + (r1.y - q1.y) * t)

        var shaft = Path()
        shaft.move(to: start)
        shaft.addQuadCurve(to: shaftEnd, control: q1)

        return (shaft, head)
    }

    /// The point ON the curve at t=0.5, for a quadratic Bézier:
    /// 0.25·start + 0.5·control + 0.25·end. This is what the Curve Handle
    /// displays at and drags from — more intuitive than controlPoint itself,
    /// which generally sits *off* the visible curve once it's been dragged.
    private static func curveMidpoint(start: CGPoint, control: CGPoint, end: CGPoint) -> CGPoint {
        CGPoint(
            x: 0.25 * start.x + 0.5 * control.x + 0.25 * end.x,
            y: 0.25 * start.y + 0.5 * control.y + 0.25 * end.y
        )
    }

    private static func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }

    /// Keeps x/y/width/height in sync as the bounding box of arrowStart/End/
    /// ControlX/Y after any single-node commit — generic board-wide systems
    /// (Marquee Selection, Fit to Screen, the Arrow Style Panel's position)
    /// read those, not the arrow-specific fields directly. See
    /// BoardNode.syncArrowBoundingBox() (ArrowConnection.swift) — shared
    /// with ContentView's delete cascade, which mutates the same raw fields
    /// when freezing a connection.
    private func syncBoundingBox() {
        node.syncArrowBoundingBox()
    }

    /// Mirrors this view's current live points onto canvas.liveArrowGeometry
    /// (Arrow Tool Vague 5 #2), so the Arrow Style Panel's position — computed
    /// in ContentView, entirely outside this view — can track a handle A/B,
    /// body, or Curve Handle drag frame-by-frame instead of only once it
    /// commits. Call from every onChanged; each onEnded clears it back to nil.
    private func publishLiveArrowGeometry() {
        canvas.liveArrowGeometry = LiveArrowGeometry(nodeID: node.id, start: displayStart, end: displayEnd, control: displayControl)
    }

    /// Anchor Point / Arrow Connection snap (Phase 3 steps 4/6 and 5/6)
    /// takes priority over Grid Attach, per spec — only falls back to the
    /// grid when nothing is within the hard snap radius. Used by handle A/B
    /// only: body and Curve Handle drags don't snap to anchors at all (only
    /// A/B, since those are the endpoints that make sense to attach
    /// elsewhere).
    private func resolvedEndpoint(_ rawPoint: CGPoint) -> AnchorPointFinder.Result {
        let result = AnchorPointFinder.snappedEndpoint(for: rawPoint, excluding: node.id, allNodes: allNodes, canvas: canvas)
        guard result.point == rawPoint else { return result }
        let gridPoint = Self.isShiftHeld ? GridAttach.snapped(rawPoint) : rawPoint
        return AnchorPointFinder.Result(point: gridPoint, connection: nil)
    }

    /// Commits whatever resolvedEndpoint(_:) found for a source point
    /// (start or end) at a handle A/B drag's onEnded: sets the connection
    /// if the snap was to another arrow's point *and* it wouldn't create a
    /// cycle (Phase 3 step 5/6 — refused silently, per spec, by just
    /// falling back to a plain position instead of a connection), or clears
    /// it otherwise — re-dragging an already-connected point always either
    /// reconnects it (to the same or a different target) or frees it, never
    /// leaves the old connection dangling alongside a new position.
    private func commitConnection(_ result: AnchorPointFinder.Result, role: ArrowPointRole, set: (ArrowConnection?) -> Void) {
        guard let connection = result.connection else {
            set(nil)
            return
        }
        let arrowsByID = Dictionary(uniqueKeysWithValues: allNodes.filter { $0.kind == .arrow }.map { ($0.id, $0) })
        let wouldCycle = ArrowConnectionResolver.wouldCreateCycle(
            connectingSource: node.id, sourceRole: role,
            toTarget: connection.targetArrowID, targetPoint: connection.targetPoint,
            nodesByID: arrowsByID
        )
        set(wouldCycle ? nil : connection)
    }

    // MARK: - Selection

    // Independent simultaneousGesture (not `.exclusively`) so a single tap
    // resolves immediately rather than waiting out the double-click
    // interval — same reasoning as NodeView's own singleTapGesture
    // (BUGS.md #1). No double-tap behavior for arrows at this stage.
    private var singleTapGesture: some Gesture {
        TapGesture(count: 1).onEnded {
            onInteract()
            if NSEvent.modifierFlags.contains(.command) {
                canvas.toggleSelection(node.id)
            } else {
                canvas.select(node.id)
            }
        }
    }

    // MARK: - Body drag (moves both points together)

    /// Named coordinate space + explicit /canvas.scale, not .local (Arrow
    /// Tool Vague 1 #1): NodeView's own move gesture gets away with .local
    /// and a bare value.translation because it's attached directly to the
    /// node's own single top-level view. This gesture is instead attached to
    /// a Color.clear sibling nested inside this view's ZStack, and .local's
    /// automatic ancestor-scale compensation turned out not to hold there in
    /// practice — the same category of failure already diagnosed once for
    /// the standard Resize Handle (BUGS.md Vague 9 #1), which is exactly why
    /// that one (and Arrow's own handleAGesture/handleBGesture right below)
    /// use this same named-space-plus-manual-division technique instead of
    /// trusting .local to do it automatically.
    private var bodyDragGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(CanvasViewModel.viewportCoordinateSpaceName))
            .onChanged { value in
                if bodyDragStart == nil {
                    // displayStart/End, not arrowStartX/Y/arrowEndX/Y
                    // directly (Phase 3 step 5/6) — same reasoning as
                    // handleAGesture/handleBGesture: starting from the raw
                    // stored fields would jump a connected point the
                    // instant this drag begins.
                    bodyDragStart = (displayStart, displayEnd, displayControl)
                    onInteract()
                    // Same rule as NodeView's move gesture (Vague 3/5): only
                    // a node already part of a multi-selection before this
                    // gesture began drags the whole group.
                    let wasAlreadyMultiSelected = isSelected && canvas.selectedNodeIDs.count > 1
                    isGroupDragForThisGesture = wasAlreadyMultiSelected
                    if !wasAlreadyMultiSelected {
                        canvas.select(node.id)
                    }
                }
                guard let bodyDragStart else { return }
                // Grid Attach (Arrow Tool Vague 1 #2): the delta that would
                // snap startPoint to the grid is applied identically to
                // endPoint too, so the two points move together and keep
                // their relative geometry — same "one reference point's
                // delta, applied to every point being moved together" idea
                // as NodeView's own group-drag snap (Vague 6 #1), just with
                // this arrow's two points standing in for a group's members.
                let rawTranslation = Self.canvasTranslation(value, scale: canvas.scale)
                let translation = Self.isShiftHeld
                    ? GridAttach.snappedDelta(from: bodyDragStart.start, translation: rawTranslation)
                    : rawTranslation
                if isGroupDragForThisGesture {
                    canvas.isGroupDragActive = true
                    canvas.groupDragDelta = translation
                } else {
                    liveStartPoint = CGPoint(x: bodyDragStart.start.x + translation.width, y: bodyDragStart.start.y + translation.height)
                    liveEndPoint = CGPoint(x: bodyDragStart.end.x + translation.width, y: bodyDragStart.end.y + translation.height)
                    // The curve's control point moves with the rest of the
                    // arrow during a whole-body drag, so its shape is kept
                    // (Phase 3 step 2/6) — unlike handle A/B, which leave it
                    // in place.
                    liveControlPoint = CGPoint(x: bodyDragStart.control.x + translation.width, y: bodyDragStart.control.y + translation.height)
                }
                publishLiveArrowGeometry()
            }
            .onEnded { value in
                guard let bodyDragStart else { return }
                let rawTranslation = Self.canvasTranslation(value, scale: canvas.scale)
                let translation = Self.isShiftHeld
                    ? GridAttach.snappedDelta(from: bodyDragStart.start, translation: rawTranslation)
                    : rawTranslation
                if isGroupDragForThisGesture {
                    onGroupDragEnd(translation)
                    canvas.isGroupDragActive = false
                    canvas.groupDragDelta = .zero
                } else {
                    node.arrowStartX = bodyDragStart.start.x + translation.width
                    node.arrowStartY = bodyDragStart.start.y + translation.height
                    node.arrowEndX = bodyDragStart.end.x + translation.width
                    node.arrowEndY = bodyDragStart.end.y + translation.height
                    node.arrowControlX = bodyDragStart.control.x + translation.width
                    node.arrowControlY = bodyDragStart.control.y + translation.height
                    syncBoundingBox()
                    try? modelContext.save()
                }
                self.bodyDragStart = nil
                liveStartPoint = nil
                liveEndPoint = nil
                liveControlPoint = nil
                isGroupDragForThisGesture = false
                canvas.liveArrowGeometry = nil
            }
    }

    // MARK: - Endpoint handles

    // Fixed on-screen size regardless of zoom, same convention as the
    // standard Resize Handle (BUGS.md #6, CLAUDE.md).
    private var handleScreenDiameter: CGFloat { 10 }
    private var handleScreenStrokeWidth: CGFloat { 1.5 }

    @ViewBuilder
    private func handleOverlay(at point: CGPoint, isStart: Bool) -> some View {
        if isSelected {
            Circle()
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(Circle().stroke(Color.accentColor, lineWidth: handleScreenStrokeWidth / canvas.scale))
                .frame(width: handleScreenDiameter / canvas.scale, height: handleScreenDiameter / canvas.scale)
                .position(point)
                .gesture(isStart ? handleAGesture : handleBGesture)
        }
    }

    // Named coordinate space (not .local): same reasoning as NodeView's
    // Resize Handle (BUGS.md Vague 9 #1) — these handles sit nested inside
    // the canvas's pan/zoom transform, so the drag's screen-space
    // translation needs an explicit divide-by-scale to become a canvas-space
    // one; relying on .local to already account for the ancestor
    // .scaleEffect doesn't hold in practice.
    private static func translated(_ point: CGPoint, by value: DragGesture.Value, scale: CGFloat) -> CGPoint {
        CGPoint(
            x: point.x + (value.location.x - value.startLocation.x) / scale,
            y: point.y + (value.location.y - value.startLocation.y) / scale
        )
    }

    /// Same conversion as `translated(_:by:scale:)`, as a translation
    /// (CGSize) rather than applied to a specific point — used by
    /// bodyDragGesture, which moves two points by the same delta.
    private static func canvasTranslation(_ value: DragGesture.Value, scale: CGFloat) -> CGSize {
        CGSize(
            width: (value.location.x - value.startLocation.x) / scale,
            height: (value.location.y - value.startLocation.y) / scale
        )
    }

    private static var isShiftHeld: Bool {
        NSEvent.modifierFlags.contains(.shift)
    }

    /// Handle A: drags startPoint only: endPoint (and so the arrowhead,
    /// which always renders at the current end) stays put.
    ///
    /// Explicitly erased to AnyGesture (rather than `some Gesture`, as every
    /// other gesture in this file and NodeView is): handleOverlay picks
    /// between this and handleBGesture with a plain `isStart ? … : …`
    /// ternary, and the Swift compiler won't treat two `some Gesture`-typed
    /// properties — even structurally identical ones — as the same type
    /// there, since each opaque return type is only known to be *some*
    /// Gesture, not statically which one.
    private var handleAGesture: AnyGesture<DragGesture.Value> {
        AnyGesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .named(CanvasViewModel.viewportCoordinateSpaceName))
                .onChanged { value in
                    if handleAStart == nil {
                        // displayStart, not arrowStartX/Y directly (Phase 3
                        // step 5/6): if A is already connected, the raw
                        // stored fields are a stale leftover — starting the
                        // drag from them would jump the point the instant
                        // the drag begins instead of continuing smoothly
                        // from wherever it's actually displayed right now.
                        handleAStart = displayStart
                        onInteract()
                    }
                    guard let handleAStart else { return }
                    // Grid Attach (Arrow Tool Vague 1 #2), Anchor Point
                    // snap (Phase 3 step 4/6), or Arrow Connection snap
                    // (step 5/6) — snaps this point alone, endPoint isn't
                    // touched by this gesture at all, matching the standard
                    // single-node move's own snap. The connection itself
                    // (if any) is only ever committed at onEnded, below —
                    // this is just the live preview position.
                    let point = Self.translated(handleAStart, by: value, scale: canvas.scale)
                    let newStart = resolvedEndpoint(point).point
                    liveStartPoint = newStart
                    // Arrow Tool Vague 2: while the arrow is still straight,
                    // keep controlPoint pinned to the segment's midpoint on
                    // every frame, so repositioning A can't accidentally
                    // curve it — the bug this whole isCurved flag exists to
                    // fix (controlPoint used to stay at its old absolute
                    // position while the segment's real midpoint moved out
                    // from under it).
                    if !node.isCurved {
                        liveControlPoint = Self.midpoint(newStart, CGPoint(x: node.arrowEndX, y: node.arrowEndY))
                    }
                    publishLiveArrowGeometry()
                }
                .onEnded { value in
                    guard let handleAStart else { return }
                    let point = Self.translated(handleAStart, by: value, scale: canvas.scale)
                    let result = resolvedEndpoint(point)
                    node.arrowStartX = result.point.x
                    node.arrowStartY = result.point.y
                    commitConnection(result, role: .start) { node.startConnection = $0 }
                    if !node.isCurved {
                        let mid = Self.midpoint(result.point, CGPoint(x: node.arrowEndX, y: node.arrowEndY))
                        node.arrowControlX = mid.x
                        node.arrowControlY = mid.y
                    }
                    syncBoundingBox()
                    try? modelContext.save()
                    self.handleAStart = nil
                    liveStartPoint = nil
                    liveControlPoint = nil
                    canvas.liveArrowGeometry = nil
                    canvas.anchorSnapState = nil
                }
        )
    }

    /// Handle B: drags endPoint only — the arrowhead reorients live since
    /// its angle is always recomputed from the current start/end on every
    /// render. See handleAGesture's doc comment for why this is erased.
    private var handleBGesture: AnyGesture<DragGesture.Value> {
        AnyGesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .named(CanvasViewModel.viewportCoordinateSpaceName))
                .onChanged { value in
                    if handleBStart == nil {
                        // displayEnd, not arrowEndX/Y directly — same
                        // reasoning as handleAGesture's matching comment.
                        handleBStart = displayEnd
                        onInteract()
                    }
                    guard let handleBStart else { return }
                    // Grid Attach (Arrow Tool Vague 1 #2), Anchor Point
                    // snap (Phase 3 step 4/6), or Arrow Connection snap
                    // (step 5/6) — snaps this point alone, startPoint isn't
                    // touched by this gesture. The connection itself is
                    // only ever committed at onEnded, below.
                    let point = Self.translated(handleBStart, by: value, scale: canvas.scale)
                    let newEnd = resolvedEndpoint(point).point
                    liveEndPoint = newEnd
                    // Arrow Tool Vague 2: see handleAGesture's matching
                    // comment — same "pin to midpoint while straight" fix.
                    if !node.isCurved {
                        liveControlPoint = Self.midpoint(CGPoint(x: node.arrowStartX, y: node.arrowStartY), newEnd)
                    }
                    publishLiveArrowGeometry()
                }
                .onEnded { value in
                    guard let handleBStart else { return }
                    let point = Self.translated(handleBStart, by: value, scale: canvas.scale)
                    let result = resolvedEndpoint(point)
                    node.arrowEndX = result.point.x
                    node.arrowEndY = result.point.y
                    commitConnection(result, role: .end) { node.endConnection = $0 }
                    if !node.isCurved {
                        let mid = Self.midpoint(CGPoint(x: node.arrowStartX, y: node.arrowStartY), result.point)
                        node.arrowControlX = mid.x
                        node.arrowControlY = mid.y
                    }
                    syncBoundingBox()
                    try? modelContext.save()
                    self.handleBStart = nil
                    liveEndPoint = nil
                    liveControlPoint = nil
                    canvas.liveArrowGeometry = nil
                    canvas.anchorSnapState = nil
                }
        )
    }

    // MARK: - Curve Handle

    // Same fixed-on-screen-size convention as the endpoint handles.
    private var curveHandleScreenDiameter: CGFloat { 10 }
    private var curveHandleScreenStrokeWidth: CGFloat { 1.5 }

    @State private var isDraggingCurveHandle = false

    private func curveHandleOverlay(at point: CGPoint) -> some View {
        Circle()
            .fill(Color(nsColor: .controlBackgroundColor))
            .overlay(Circle().stroke(Color.accentColor, lineWidth: curveHandleScreenStrokeWidth / canvas.scale))
            .frame(width: curveHandleScreenDiameter / canvas.scale, height: curveHandleScreenDiameter / canvas.scale)
            .position(point)
            .gesture(curveHandleDragGesture)
            .simultaneousGesture(curveHandleDoubleTapGesture)
    }

    /// Unlike every other gesture in this file, this maps the cursor
    /// directly to the target position rather than accumulating a delta
    /// from a captured start point — per spec, the desired curveMidpoint
    /// *is* the cursor's canvas position on every frame, so there's no
    /// gesture-start reference to anchor or re-anchor at all: the 1:1
    /// precision the project's past Crop-Resize bugs had to fight for is
    /// automatic here since the mapping is direct.
    private var curveHandleDragGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(CanvasViewModel.viewportCoordinateSpaceName))
            .onChanged { value in
                if !isDraggingCurveHandle {
                    isDraggingCurveHandle = true
                    onInteract()
                }
                let desiredCurveMidpoint = canvas.canvasPoint(fromScreen: value.location)
                liveControlPoint = Self.controlPoint(
                    forDesiredCurveMidpoint: desiredCurveMidpoint,
                    start: CGPoint(x: node.arrowStartX, y: node.arrowStartY),
                    end: CGPoint(x: node.arrowEndX, y: node.arrowEndY)
                )
                publishLiveArrowGeometry()
            }
            .onEnded { value in
                let desiredCurveMidpoint = canvas.canvasPoint(fromScreen: value.location)
                let newControl = Self.controlPoint(
                    forDesiredCurveMidpoint: desiredCurveMidpoint,
                    start: CGPoint(x: node.arrowStartX, y: node.arrowStartY),
                    end: CGPoint(x: node.arrowEndX, y: node.arrowEndY)
                )
                node.arrowControlX = newControl.x
                node.arrowControlY = newControl.y
                // Arrow Tool Vague 2: dragging the Curve Handle away from
                // the segment's midpoint is the one and only way an arrow
                // becomes curved — this transition is one-way until an
                // explicit reset (double-click, below).
                node.isCurved = !Self.isApproximatelyMidpoint(
                    newControl,
                    start: CGPoint(x: node.arrowStartX, y: node.arrowStartY),
                    end: CGPoint(x: node.arrowEndX, y: node.arrowEndY)
                )
                // Arrow Tool Vague 5 #2: this was previously missing here —
                // controlPoint moving is the *only* case that could change
                // the bounding box without also touching startPoint/endPoint,
                // so the Arrow Style Panel's (and Marquee Selection's) sense
                // of this arrow's bounds went stale after every Curve Handle
                // drag that didn't also move A or B.
                syncBoundingBox()
                try? modelContext.save()
                isDraggingCurveHandle = false
                liveControlPoint = nil
                canvas.liveArrowGeometry = nil
            }
    }

    /// Inverts curveMidpoint = 0.25·start + 0.5·control + 0.25·end for
    /// control, given a desired curveMidpoint and the arrow's current
    /// start/end.
    private static func controlPoint(forDesiredCurveMidpoint curveMidpoint: CGPoint, start: CGPoint, end: CGPoint) -> CGPoint {
        CGPoint(
            x: 2 * curveMidpoint.x - 0.5 * (start.x + end.x),
            y: 2 * curveMidpoint.y - 0.5 * (start.y + end.y)
        )
    }

    /// Whether `control` is (near enough to) the segment's midpoint that the
    /// arrow still reads as straight — a tiny tolerance rather than exact
    /// equality, since floating-point drag math essentially never lands on
    /// the midpoint exactly even when the user's intent was "don't curve
    /// this."
    private static func isApproximatelyMidpoint(_ control: CGPoint, start: CGPoint, end: CGPoint) -> Bool {
        let mid = midpoint(start, end)
        let dx = control.x - mid.x
        let dy = control.y - mid.y
        return (dx * dx + dy * dy) < 0.25
    }

    /// Double-click on the Curve Handle resets the arrow to a straight line
    /// (GLOSSARY.md's Curve Handle entry) — a single, ordinarily-registered
    /// undo step, same as every other discrete (non-continuous-drag) commit
    /// in this file.
    private var curveHandleDoubleTapGesture: some Gesture {
        TapGesture(count: 2).onEnded {
            onInteract()
            node.arrowControlX = (node.arrowStartX + node.arrowEndX) / 2
            node.arrowControlY = (node.arrowStartY + node.arrowEndY) / 2
            // Arrow Tool Vague 2: a full reset to "straight," not just a
            // one-off visual snap-back — isCurved must go false too, so a
            // later handle A/B or body drag pins controlPoint back to the
            // midpoint again instead of treating this as still curved.
            node.isCurved = false
            // Arrow Tool Vague 5 #2: same missing call as the drag's own
            // onEnded — resetting controlPoint can shrink the bounding box
            // back down from whatever it bulged out to while curved.
            syncBoundingBox()
            try? modelContext.save()
        }
    }
}
