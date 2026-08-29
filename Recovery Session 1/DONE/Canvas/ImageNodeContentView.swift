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
                // geo.size is whatever frame NodeView actually gave this
                // view — the live, in-progress size during any drag (a
                // normal resize or a Crop-Resize alike), not just the
                // last-committed node.width/height. The crop fraction
                // (cropWidth/cropHeight) only changes during an active
                // Crop-Resize gesture, so deriving the full image's size at
                // its current display scale from geo.size/cropWidth here
                // (rather than from node.width/cropWidth) keeps this correct
                // live in both cases. Offsetting by the crop origin and
                // clipping to the frame reveals only the cropped window
                // without changing how "zoomed in" the picture looks
                // (Crop-Resize, BUGS.md Vague 10 #3).
                let fullWidth = geo.size.width / max(node.cropWidth, 0.001)
                let fullHeight = geo.size.height / max(node.cropHeight, 0.001)
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
        .task(id: node.assetRelativePath) {
            loadedImage = loadImage()
        }
    }

    private func loadImage() -> NSImage? {
        guard let relativePath = node.assetRelativePath else { return nil }
        return NSImage(contentsOf: boardURL.appendingPathComponent(relativePath))
    }
}
