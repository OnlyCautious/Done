//
//  BoardNode.swift
//  DONE
//

import Foundation
import SwiftData

enum BoardNodeKind: String, Codable {
    case text
    case image
    case shape
    case arrow
}

/// A single item on the board. Rather than a class hierarchy per node type (as
/// sketched in the early data model notes), this uses one SwiftData model with a
/// `kind` discriminator and per-kind optional fields — SwiftData's support for
/// polymorphic @Model hierarchies is still rough, and a flat model is simpler to
/// query/sort by zIndex across all node types on the board.
@Model
final class BoardNode {
    var id: UUID
    var kind: BoardNodeKind
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var zIndex: Int
    var createdAt: Date

    // Text notes
    var text: String

    // Image nodes. sourceWidth/sourceHeight are the imported image's native
    // pixel dimensions — fixed at import, never modified afterwards. They
    // replace the old `aspectRatio: Double?` (which was written at import
    // but never actually read anywhere — confirmed while diagnosing BUGS.md
    // Session 2 Vague 3): a bare ratio can't anchor a single content scale
    // the way the true native size can.
    var assetRelativePath: String?
    var sourceWidth: Double = 1
    var sourceHeight: Double = 1

    // contentScale (Session 2 Vague 3): the *single* scale factor applied to
    // the source image — canvas points per source pixel. Recomputed by
    // Crop-Resize via the "cover" formula
    // (max(width/sourceWidth, height/sourceHeight)) so the image is always
    // scaled uniformly, never stretched independently on X/Y. Previously
    // there was no such field: fullWidth/fullHeight were re-derived
    // independently per axis from width/cropWidth and height/cropHeight in
    // three different places, with nothing enforcing that the two stayed in
    // proportion to the source's real aspect ratio — the root cause of the
    // Crop-Resize deformation bug.
    var contentScale: Double = 1

    // Crop-Resize / Crop Tool (Vague 10 #3, #4) — the visible window into the
    // full imported image at its current contentScale, normalized (0...1) as
    // a fraction of sourceWidth*contentScale / sourceHeight*contentScale.
    // (0, 0, 1, 1) — the default — means uncropped, the whole image visible.
    // Crop-Resize now recomputes these to keep the window centered and
    // exactly matching the frame (the "cover" crop) every time contentScale
    // changes; the Crop Tool pans/resizes this window on its own within a
    // fixed contentScale instead. See ImageNodeContentView and NodeView's
    // Crop-Resize gesture.
    var cropX: Double = 0
    var cropY: Double = 0
    var cropWidth: Double = 1
    var cropHeight: Double = 1

    // Shape nodes (Phase 2) — reuses `text` above for the embedded text.
    var shapeType: ShapeType?

    // Arrow nodes (Phase 3, step 1/6 — foundations only: straight line, no
    // curve/style/snap/connections/text yet, see BUGS.md). An arrow's
    // geometry is these two points, not the classic position/size — x/y/
    // width/height are still kept in sync as the pair's bounding box purely
    // so generic board-wide systems that assume every node has one
    // (Marquee Selection, Fit to Screen's content bounds, group drag) work
    // for arrows without special-casing each of them individually; they are
    // never the source of truth for an arrow's own rendering.
    var arrowStartX: Double = 0
    var arrowStartY: Double = 0
    var arrowEndX: Double = 0
    var arrowEndY: Double = 0

    // Arrow curve (Phase 3 step 2/6, revised step 2 Vague 1): the quadratic
    // Bézier control point, initialized to the segment's midpoint at
    // creation (== a visually straight line, since a quadratic Bézier with
    // its control point at the segment's midpoint degenerates to that
    // segment).
    var arrowControlX: Double = 0
    var arrowControlY: Double = 0

    // Explicit curved/straight state (Arrow Tool Vague 2, replacing step
    // 2/6's original "curvature is just whatever position controlPoint
    // happens to be at" design): as long as this is false, controlPoint is
    // recomputed to the segment's midpoint on every handle A/B or body-drag
    // frame, so a straight arrow can be freely repositioned without ever
    // accidentally acquiring a curve — the bug that design produced, since
    // controlPoint stayed at its old absolute position while the segment's
    // real midpoint moved out from under it. Only dragging the Curve Handle
    // itself sets this to true; only double-clicking the Curve Handle resets
    // it back to false (along with controlPoint itself).
    var isCurved: Bool = false

    // Arrow style (Phase 3 step 3/6): defaults match the values hard-coded
    // since step 1/6 (solid, 2pt), so existing arrows look identical until
    // the Arrow Style Panel is actually touched.
    //
    // arrowStrokeStyle is Optional (Arrow Tool Vague 4), not a non-optional
    // property with an inline default — that crashed on every board created
    // before this step (SIGABRT in the generated getValue(forKey:)
    // accessor). Every *other* non-optional property added incrementally to
    // this model (isCurved: Bool, arrowControlX/Y: Double, contentScale:
    // Double, ...) is a primitive type SQLite/Core Data stores natively, so
    // lightweight migration backfills their default trivially at the column
    // level. arrowStrokeStyle was the first non-optional *custom enum* added
    // — SwiftData/Core Data's automatic lightweight migration doesn't
    // reliably encode a concrete default for a transformable/custom-type
    // attribute into rows that predate the property, and the generated
    // accessor had nothing to fall back to at read time. shapeType: ShapeType?
    // already proved the optional-custom-enum path migrates cleanly (added
    // in Phase 2, never an issue) since nil needs no encoding at all — so
    // this property now follows that same proven shape, with nil treated as
    // .solid at every read site instead of asking SwiftData to backfill a
    // real value.
    var arrowStrokeStyle: ArrowStrokeStyle?
    var arrowStrokeWidth: Double = 2

    // Arrow Connections (Phase 3 step 5/6, GLOSSARY.md): a persistent link
    // from this arrow's start/end point to another arrow's start/end/Curve
    // Handle point, which it then follows automatically if that target
    // moves. Stored as flattened Optional primitives — targetID: UUID? and
    // targetPointRole: ArrowPointRole? — rather than an ArrowConnection?
    // struct property directly: arrowStrokeStyle (just above) already
    // showed that a *non-optional* custom type crashes on migration for
    // boards predating the property, and a struct wrapping another custom
    // enum is even further from the primitive/optional-enum shape that's
    // actually proven safe. Both halves of each pair are next to each other
    // and always read/written together via the computed startConnection/
    // endConnection properties below, so this is no less safe than storing
    // the struct directly, just via a route already known not to crash.
    var startConnectionTargetID: UUID?
    var startConnectionTargetPointRole: ArrowPointRole?
    var endConnectionTargetID: UUID?
    var endConnectionTargetPointRole: ArrowPointRole?

    /// nil = point A (startPoint) is free and uses arrowStartX/Y directly;
    /// non-nil = A's *effective* position is derived every frame from the
    /// target instead (ArrowConnectionResolver) — arrowStartX/Y are only
    /// ever read when this is nil, never both at once, so there's exactly
    /// one source of truth for A's position at any given time.
    var startConnection: ArrowConnection? {
        get {
            guard let id = startConnectionTargetID, let role = startConnectionTargetPointRole else { return nil }
            return ArrowConnection(targetArrowID: id, targetPoint: role)
        }
        set {
            startConnectionTargetID = newValue?.targetArrowID
            startConnectionTargetPointRole = newValue?.targetPoint
        }
    }

    /// Same contract as startConnection, for point B (endPoint).
    var endConnection: ArrowConnection? {
        get {
            guard let id = endConnectionTargetID, let role = endConnectionTargetPointRole else { return nil }
            return ArrowConnection(targetArrowID: id, targetPoint: role)
        }
        set {
            endConnectionTargetID = newValue?.targetArrowID
            endConnectionTargetPointRole = newValue?.targetPoint
        }
    }

    init(
        id: UUID = UUID(),
        kind: BoardNodeKind,
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        zIndex: Int,
        text: String = "",
        assetRelativePath: String? = nil,
        sourceWidth: Double = 1,
        sourceHeight: Double = 1,
        contentScale: Double = 1,
        shapeType: ShapeType? = nil,
        arrowStartX: Double = 0,
        arrowStartY: Double = 0,
        arrowEndX: Double = 0,
        arrowEndY: Double = 0,
        arrowControlX: Double = 0,
        arrowControlY: Double = 0
    ) {
        self.id = id
        self.kind = kind
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.zIndex = zIndex
        self.createdAt = Date()
        self.text = text
        self.assetRelativePath = assetRelativePath
        self.sourceWidth = sourceWidth
        self.sourceHeight = sourceHeight
        self.contentScale = contentScale
        self.shapeType = shapeType
        self.arrowStartX = arrowStartX
        self.arrowStartY = arrowStartY
        self.arrowEndX = arrowEndX
        self.arrowEndY = arrowEndY
        self.arrowControlX = arrowControlX
        self.arrowControlY = arrowControlY
    }
}
