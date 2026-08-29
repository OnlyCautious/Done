//
//  GridAttach.swift
//  DONE
//

import CoreGraphics

/// Grid Attach (BUGS.md Vague 2 #1, GLOSSARY.md): shared snap math so every
/// Node kind that supports Shift-held grid snapping uses the exact same
/// grid — originally implemented only inside NodeView, then extracted here
/// (Arrow Tool Vague 1 #2) so ArrowNodeView could reuse it instead of
/// redefining its own copy of the same 24pt canvas-space grid.
enum GridAttach {
    /// Canvas-space grid spacing — matches the dotted grid CanvasView draws.
    static let spacing: CGFloat = 24

    static func snapped(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: (point.x / spacing).rounded() * spacing,
            y: (point.y / spacing).rounded() * spacing
        )
    }

    /// The delta that would land `start` on the grid — for a group/multi-
    /// point translation, applying this same delta to every point being
    /// moved keeps them all snapped together without each one drifting to
    /// its own nearest grid line independently.
    static func snappedDelta(from start: CGPoint, translation: CGSize) -> CGSize {
        let raw = CGPoint(x: start.x + translation.width, y: start.y + translation.height)
        let snappedPoint = snapped(raw)
        return CGSize(width: snappedPoint.x - start.x, height: snappedPoint.y - start.y)
    }
}
