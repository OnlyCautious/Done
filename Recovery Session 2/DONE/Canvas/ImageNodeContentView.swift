//
//  ImageNodeContentView.swift
//  DONE
//

import SwiftUI
import AppKit

struct ImageNodeContentView: View {
    var node: BoardNode
    var boardURL: URL

    @State private var loadedImage: NSImage?

    var body: some View {
        GeometryReader { geo in
            if let loadedImage {
                // fullWidth/fullHeight (Session 2 Vague 3): the full source
                // image's size at its current contentScale — the single
                // scale factor NodeView's Crop-Resize maintains via the
                // "cover" formula. Previously derived independently per axis
                // from geo.size/cropWidth and geo.size/cropHeight, with
                // nothing tying the two back to the source's real aspect
                // ratio; any non-square crop made that pair inconsistent and
                // Image(...).resizable() rendered visibly stretched — the
                // root cause of the Crop-Resize deformation bug. Deriving
                // both axes from the one shared contentScale instead makes
                // that impossible. Offsetting by the crop origin and clipping
                // to the frame reveals only the cropped window without
                // changing how "zoomed in" the picture looks (Crop-Resize,
                // BUGS.md Vague 10 #3).
                let fullWidth = node.sourceWidth * node.contentScale
                let fullHeight = node.sourceHeight * node.contentScale
                Image(nsImage: loadedImage)
                    .resizable()
                    .frame(width: fullWidth, height: fullHeight)
                    .offset(x: -node.cropX * fullWidth, y: -node.cropY * fullHeight)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.15))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        // clipShape only restricts what's drawn, not what's hit-tested — the
        // resizable Image inside is laid out at its full (often much larger
        // than the frame) fullWidth/fullHeight, so without an explicit
        // contentShape here clicks/drags landing in the clipped-away portion
        // of that oversized image still hit this view instead of passing
        // through to whatever's behind it (BUGS.md Session 2 Vague 3).
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .task(id: node.assetRelativePath) {
            loadedImage = loadImage()
        }
    }

    private func loadImage() -> NSImage? {
        guard let relativePath = node.assetRelativePath else { return nil }
        return NSImage(contentsOf: boardURL.appendingPathComponent(relativePath))
    }
}
