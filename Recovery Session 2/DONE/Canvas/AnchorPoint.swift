//
//  AnchorPoint.swift
//  DONE
//

import Foundation
import CoreGraphics

/// What a snap candidate actually is — a generic Node's bounding-box corner
/// (Phase 3 step 4/6), or another Arrow's own start/end/Curve Handle point
/// (Phase 3 step 5/6, which can become a persistent Arrow Connection rather
/// than a one-off position snap).
enum AnchorTargetKind: Equatable {
    case node
    case arrowPoint(ArrowPointRole)
}

/// A single snap candidate: one of a Node's 4 bounding-box midpoints, or
/// (for an Arrow Node specifically) one of its 3 own points — tagged with
/// which Node it belongs to and what kind of target it is.
struct AnchorPointCandidate {
    var nodeID: UUID
    var position: CGPoint
    var kind: AnchorTargetKind
}

/// Visual feedback state for an in-progress Anchor Point / Arrow Connection
/// snap (shown while dragging an Arrow's A/B endpoint, or the initial
/// creation drag) — CanvasViewModel.anchorSnapState.
///
/// For a `.node` match, `candidatePoints` holds all 4 of that Node's
/// cardinal points (so all the options are visible, with the closest one
/// distinguished) — but for an `.arrowPoint` match it holds just that one
/// point: unlike a Node's 4 corners, which sit close together around one
/// shape, an arrow's start/end/Curve Handle can be far apart, so showing
/// all 3 regardless of which is actually nearby would put indicators in
/// places that have nothing to do with where the cursor is.
struct AnchorSnapState {
    var nearbyNodeID: UUID
    var candidatePoints: [CGPoint]
    var closestPoint: CGPoint?
    /// True when `closestPoint` (or the sole candidate, for an .arrowPoint
    /// match) represents an Arrow Connection rather than a plain Node
    /// anchor — CanvasView renders these in a visually distinct color per
    /// spec, so it reads as "this snap creates a persistent link" rather
    /// than "this just positions the point once."
    var isArrowConnection: Bool
}

/// Finds and snaps to Anchor Points — the 4 cardinal (top/bottom/left/right)
/// midpoints of a Node's bounding box, plus (for Arrow Node targets) their
/// own start/end/Curve Handle points — for Arrow endpoint dragging (Phase 3
/// steps 4/6 and 5/6). Used identically by ArrowNodeView (handle A/B on an
/// existing arrow) and CanvasView (the initial creation drag's end point),
/// which is why this lives as a standalone enum rather than inside either.
enum AnchorPointFinder {
    /// Hard snap radius (canvas space, so it scales with zoom rather than
    /// staying a fixed screen size like a handle — consistent with
    /// GridAttach.spacing, the other zoom-dependent proximity threshold
    /// already in the app): within this, the endpoint locks exactly onto
    /// the anchor point.
    static let snapRadius: CGFloat = 16
    /// Display radius: noticeably larger than snapRadius, so a candidate's
    /// point(s) appear a little before the hard snap actually engages,
    /// rather than the endpoint snapping abruptly with no visual lead-up.
    static let displayRadius: CGFloat = 28

    /// The 4 cardinal points of a Node's bounding box, in canvas space.
    static func cardinalPoints(x: Double, y: Double, width: Double, height: Double) -> [CGPoint] {
        [
            CGPoint(x: x + width / 2, y: y),              // top
            CGPoint(x: x + width / 2, y: y + height),      // bottom
            CGPoint(x: x, y: y + height / 2),              // left
            CGPoint(x: x + width, y: y + height / 2),      // right
        ]
    }

    /// Every candidate anchor point from `nodes`, excluding
    /// `excludingNodeID` (an arrow can't snap onto its own bounding box or
    /// its own points — nil during creation, since the new arrow isn't a
    /// Node yet) and any Node whose bounding box doesn't intersect
    /// `visibleRect` (performance: skip distance checks against anything
    /// off-screen). Arrow Nodes contribute both their 4 generic cardinal
    /// points (step 4/6, unchanged) *and* their own start/end/Curve Handle
    /// points (step 5/6, using the *resolved* — not raw stored — position,
    /// so snapping onto an already-connected arrow's point targets where it
    /// actually is right now).
    static func candidates(in nodes: [BoardNode], excluding excludingNodeID: UUID?, visibleRect: CGRect) -> [AnchorPointCandidate] {
        let arrowsByID = Dictionary(uniqueKeysWithValues: nodes.filter { $0.kind == .arrow }.map { ($0.id, $0) })
        return nodes.flatMap { node -> [AnchorPointCandidate] in
            guard node.id != excludingNodeID else { return [] }
            let rect = CGRect(x: node.x, y: node.y, width: node.width, height: node.height)
            guard rect.intersects(visibleRect) else { return [] }

            var result = cardinalPoints(x: node.x, y: node.y, width: node.width, height: node.height)
                .map { AnchorPointCandidate(nodeID: node.id, position: $0, kind: .node) }

            if node.kind == .arrow {
                for role in [ArrowPointRole.start, .end, .control] {
                    let position = ArrowConnectionResolver.resolvedPoint(role: role, of: node.id, nodesByID: arrowsByID)
                    result.append(AnchorPointCandidate(nodeID: node.id, position: position, kind: .arrowPoint(role)))
                }
            }
            return result
        }
    }

    /// The single closest candidate to `point` within `radius`, if any.
    static func closest(to point: CGPoint, among candidates: [AnchorPointCandidate], within radius: CGFloat) -> AnchorPointCandidate? {
        var best: (candidate: AnchorPointCandidate, distanceSquared: CGFloat)?
        let radiusSquared = radius * radius
        for candidate in candidates {
            let dx = candidate.position.x - point.x
            let dy = candidate.position.y - point.y
            let distanceSquared = dx * dx + dy * dy
            guard distanceSquared <= radiusSquared else { continue }
            if best == nil || distanceSquared < best!.distanceSquared {
                best = (candidate, distanceSquared)
            }
        }
        return best?.candidate
    }

    /// What a completed snap resolves to: the point the endpoint should
    /// use, and — only when the hard-matched candidate was another arrow's
    /// point — the ArrowConnection that should be created (Phase 3 step
    /// 5/6). `connection` is nil for a plain Node anchor snap (step 4/6,
    /// unchanged) or when nothing was within the hard snap radius at all.
    struct Result {
        var point: CGPoint
        var connection: ArrowConnection?
    }

    /// Checks `rawPoint` (canvas space, the endpoint's position before any
    /// snapping) against every visible Node's anchor points, updates
    /// `canvas.anchorSnapState` for the visual indicator, and returns the
    /// resolved point/connection. Anchor snap takes priority over Grid
    /// Attach — callers should only fall back to grid snapping when
    /// `result.point == rawPoint`.
    @MainActor
    static func snappedEndpoint(
        for rawPoint: CGPoint,
        excluding excludingNodeID: UUID?,
        allNodes: [BoardNode],
        canvas: CanvasViewModel
    ) -> Result {
        let candidates = candidates(in: allNodes, excluding: excludingNodeID, visibleRect: canvas.visibleCanvasRect)
        guard let nearest = closest(to: rawPoint, among: candidates, within: displayRadius) else {
            canvas.anchorSnapState = nil
            return Result(point: rawPoint, connection: nil)
        }

        let isArrowConnection: Bool
        let displayPoints: [CGPoint]
        switch nearest.kind {
        case .node:
            // All 4 of that Node's corners — they sit close together
            // around one shape, so showing all of them (with the closest
            // one distinguished) is clear rather than cluttered.
            isArrowConnection = false
            displayPoints = candidates
                .filter { $0.nodeID == nearest.nodeID && $0.kind == .node }
                .map(\.position)
        case .arrowPoint:
            // Just the one matching point — an arrow's 3 points can be far
            // apart, so showing all of them regardless of which is nearby
            // would put indicators where the cursor isn't anywhere near.
            isArrowConnection = true
            displayPoints = [nearest.position]
        }

        let dx = nearest.position.x - rawPoint.x
        let dy = nearest.position.y - rawPoint.y
        let isHardMatch = (dx * dx + dy * dy) <= snapRadius * snapRadius
        canvas.anchorSnapState = AnchorSnapState(
            nearbyNodeID: nearest.nodeID,
            candidatePoints: displayPoints,
            closestPoint: isHardMatch ? nearest.position : nil,
            isArrowConnection: isArrowConnection
        )

        guard isHardMatch else {
            return Result(point: rawPoint, connection: nil)
        }
        if case .arrowPoint(let role) = nearest.kind {
            return Result(point: nearest.position, connection: ArrowConnection(targetArrowID: nearest.nodeID, targetPoint: role))
        }
        return Result(point: nearest.position, connection: nil)
    }
}
