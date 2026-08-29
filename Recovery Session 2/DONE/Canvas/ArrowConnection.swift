//
//  ArrowConnection.swift
//  DONE
//

import Foundation
import CoreGraphics

/// Which point on an Arrow Node a connection targets (Phase 3 step 5/6,
/// GLOSSARY.md's Arrow Connection). Only .start/.end can be a connection's
/// *source* — the Curve Handle is always driven by its own drag (Phase 3
/// step 2/6) and never itself connects outward — but any of the three,
/// including .control, can be a connection's *target*.
enum ArrowPointRole: String, Codable {
    case start
    case end
    case control
}

/// A persistent link from one Arrow Node's start or end point to another
/// Arrow Node's point (GLOSSARY.md's Arrow Connection). Stored on BoardNode
/// as two flattened Optional primitives (targetArrowID: UUID?,
/// targetPointRole: ArrowPointRole?) rather than this struct directly —
/// see BoardNode.startConnection's doc comment for why — with this struct
/// as the ergonomic get/set surface bridging the two.
struct ArrowConnection: Equatable {
    var targetArrowID: UUID
    var targetPoint: ArrowPointRole
}

/// Resolves an Arrow Node's *effective* start/end/curve-midpoint position,
/// chasing a chain of ArrowConnections recursively — this recursion IS
/// topological resolution (a target is always fully resolved before its
/// dependent reads it, since the read only happens inside the recursive
/// call), so nothing is ever a frame stale, without needing a separate
/// graph-wide sort pass. Used by ArrowNodeView (to render/drag a connected
/// arrow), AnchorPointFinder (to offer another arrow's *current* points as
/// snap candidates), and ContentView's delete cascade (to freeze a
/// connected arrow's position before its target is removed).
enum ArrowConnectionResolver {
    /// (nodeID, role) — used as the cycle-guard's visited set, since the
    /// same node can legitimately appear twice for *different* roles in a
    /// non-cyclic graph (e.g. two arrows connected start-to-end and
    /// end-to-start); only revisiting the same (nodeID, role) pair means an
    /// actual cycle.
    private struct Key: Hashable {
        var nodeID: UUID
        var role: ArrowPointRole
    }

    /// The current effective canvas-space position of `role` on the arrow
    /// `nodeID`. `nodesByID` must map every *arrow* node's id to itself
    /// (non-arrow nodes never participate in a connection chain).
    static func resolvedPoint(role: ArrowPointRole, of nodeID: UUID, nodesByID: [UUID: BoardNode]) -> CGPoint {
        resolvedPoint(role: role, of: nodeID, nodesByID: nodesByID, visited: [])
    }

    private static func resolvedPoint(role: ArrowPointRole, of nodeID: UUID, nodesByID: [UUID: BoardNode], visited: Set<Key>) -> CGPoint {
        guard let node = nodesByID[nodeID] else { return .zero }
        let key = Key(nodeID: nodeID, role: role)
        // Cycle guard — connection creation already refuses anything that
        // would form one, so this should be unreachable in practice; it's
        // here purely so a hand-edited or otherwise corrupted board can
        // never hang or crash, just fall back to the raw stored value.
        guard !visited.contains(key) else { return rawPoint(role: role, of: node) }
        let visited = visited.union([key])

        switch role {
        case .start:
            guard let connection = node.startConnection else {
                return CGPoint(x: node.arrowStartX, y: node.arrowStartY)
            }
            return resolvedPoint(role: connection.targetPoint, of: connection.targetArrowID, nodesByID: nodesByID, visited: visited)
        case .end:
            guard let connection = node.endConnection else {
                return CGPoint(x: node.arrowEndX, y: node.arrowEndY)
            }
            return resolvedPoint(role: connection.targetPoint, of: connection.targetArrowID, nodesByID: nodesByID, visited: visited)
        case .control:
            // The Curve Handle's *visual* position (curveMidpoint, Phase 3
            // step 2/6) — not the raw stored control point — is what other
            // arrows actually see and target, per spec. It depends on this
            // same arrow's own resolved start/end, which may themselves be
            // connected elsewhere, so those are chased first.
            let start = resolvedPoint(role: .start, of: nodeID, nodesByID: nodesByID, visited: visited)
            let end = resolvedPoint(role: .end, of: nodeID, nodesByID: nodesByID, visited: visited)
            let control = CGPoint(x: node.arrowControlX, y: node.arrowControlY)
            return curveMidpoint(start: start, control: control, end: end)
        }
    }

    private static func rawPoint(role: ArrowPointRole, of node: BoardNode) -> CGPoint {
        switch role {
        case .start: return CGPoint(x: node.arrowStartX, y: node.arrowStartY)
        case .end: return CGPoint(x: node.arrowEndX, y: node.arrowEndY)
        case .control: return CGPoint(x: node.arrowControlX, y: node.arrowControlY)
        }
    }

    private static func curveMidpoint(start: CGPoint, control: CGPoint, end: CGPoint) -> CGPoint {
        CGPoint(
            x: 0.25 * start.x + 0.5 * control.x + 0.25 * end.x,
            y: 0.25 * start.y + 0.5 * control.y + 0.25 * end.y
        )
    }

    /// Whether connecting `sourceNodeID`'s `sourceRole` point to
    /// `targetNodeID`'s `targetPoint` would create a cycle — walks the
    /// chain of connections starting at the target; if it ever leads back
    /// to (sourceNodeID, sourceRole), the new connection would close a
    /// loop. Checked before a connection is ever created (BUGS.md/spec:
    /// refuse silently, no crash, just no snap) — resolvedPoint's own
    /// cycle guard is a last-resort backstop, not a substitute for this.
    static func wouldCreateCycle(
        connectingSource sourceNodeID: UUID,
        sourceRole: ArrowPointRole,
        toTarget targetNodeID: UUID,
        targetPoint: ArrowPointRole,
        nodesByID: [UUID: BoardNode]
    ) -> Bool {
        var currentNodeID = targetNodeID
        var currentRole = targetPoint
        // An acyclic chain can be at most as long as the number of arrows on
        // the board; capping the walk at that guarantees termination even
        // if some other bug ever let an actual cycle slip through.
        var stepsRemaining = nodesByID.count + 1
        while stepsRemaining > 0 {
            if currentNodeID == sourceNodeID && currentRole == sourceRole {
                return true
            }
            guard let node = nodesByID[currentNodeID] else { return false }
            let nextConnection: ArrowConnection?
            switch currentRole {
            case .start: nextConnection = node.startConnection
            case .end: nextConnection = node.endConnection
            case .control: nextConnection = nil // .control is never itself a connection source
            }
            guard let nextConnection else { return false }
            currentNodeID = nextConnection.targetArrowID
            currentRole = nextConnection.targetPoint
            stepsRemaining -= 1
        }
        return false
    }
}

extension BoardNode {
    /// Recomputes x/y/width/height as the bounding box of arrowStart/End/
    /// ControlX/Y — shared between ArrowNodeView's own gestures and
    /// ContentView's delete-cascade connection freeze (Phase 3 step 5/6),
    /// both of which mutate those raw fields directly and need generic
    /// board-wide systems (Marquee Selection, Fit to Screen, the Arrow
    /// Style Panel's position) to see the update rather than reading a
    /// stale box.
    func syncArrowBoundingBox() {
        let minX = min(arrowStartX, arrowEndX, arrowControlX)
        let minY = min(arrowStartY, arrowEndY, arrowControlY)
        let maxX = max(arrowStartX, arrowEndX, arrowControlX)
        let maxY = max(arrowStartY, arrowEndY, arrowControlY)
        x = minX
        y = minY
        width = maxX - minX
        height = maxY - minY
    }
}
