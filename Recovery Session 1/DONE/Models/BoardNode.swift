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

    // Image nodes
    var assetRelativePath: String?
    var aspectRatio: Double?

    // Crop-Resize / Crop Tool (Vague 10 #3, #4) — the visible window into the
    // full imported image, normalized (0...1) as a fraction of that full
    // image's own bounds. (0, 0, 1, 1) — the default — means uncropped, the
    // whole image visible. The node's own width/height is always exactly
    // this window's size at the image's current display scale, so that
    // scale can always be recovered on demand as width/cropWidth (rather
    // than needing its own separately-persisted field): see
    // ImageNodeContentView and NodeView's Crop-Resize gesture.
    var cropX: Double = 0
    var cropY: Double = 0
    var cropWidth: Double = 1
    var cropHeight: Double = 1

    // Shape nodes (Phase 2) — reuses `text` above for the embedded text.
    var shapeType: ShapeType?

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
        aspectRatio: Double? = nil,
        shapeType: ShapeType? = nil
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
        self.aspectRatio = aspectRatio
        self.shapeType = shapeType
    }
}
