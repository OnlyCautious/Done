//
//  ImageCropEditorView.swift
//  DONE
//

import SwiftUI
import AppKit
import SwiftData

/// Crop Tool editing mode (BUGS.md Vague 10 #4): entered by double-clicking
/// an already-selected Image Node. Shows the whole imported image — larger
/// than the node's normal (cropped) frame, in general — dimmed and blurred
/// outside the current crop rectangle, with 8 handles (4 corners, 2-axis; 4
/// edges, 1-axis) and drag-to-pan inside the rect. Everything here operates
/// on canvas.cropSession's draftCrop only; nothing is written to the actual
/// node until the Crop Action Bar's Save is pressed (ContentView.saveCrop()) —
/// Cancel, Escape, and clicking elsewhere all just discard the session.
struct ImageCropEditorView: View {
    var node: BoardNode
    var canvas: CanvasViewModel

    @Environment(\.boardURL) private var boardURL
    @State private var loadedImage: NSImage?

    private enum Handle: CaseIterable {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

        var affectsLeft: Bool { self == .topLeft || self == .left || self == .bottomLeft }
        var affectsRight: Bool { self == .topRight || self == .right || self == .bottomRight }
        var affectsTop: Bool { self == .topLeft || self == .top || self == .topRight }
        var affectsBottom: Bool { self == .bottomLeft || self == .bottom || self == .bottomRight }
    }

    // Shared by every handle + the pan gesture — only one can ever be active
    // at once. dragStartDraft snapshots draftCrop at the *start* of whichever
    // gesture is currently running, so deltas are computed cleanly instead of
    // accumulated incrementally.
    @State private var dragStartDraft: CropFraction?
    @State private var isAdjusting = false

    private static let minFraction = 0.05

    var body: some View {
        if let session = canvas.cropSession {
            let rect = CGRect(
                x: session.draftCrop.x * session.fullWidth,
                y: session.draftCrop.y * session.fullHeight,
                width: session.draftCrop.width * session.fullWidth,
                height: session.draftCrop.height * session.fullHeight
            )
            ZStack(alignment: .topLeading) {
                dimmedFullImage(session: session)
                sharpCropWindow(session: session, rect: rect)
                if isAdjusting {
                    thirdsGrid(rect: rect)
                }
                Rectangle()
                    .stroke(Color.white, lineWidth: 2)
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
                    .allowsHitTesting(false)
                ForEach(Handle.allCases, id: \.self) { handle in
                    handleView(handle, rect: rect)
                }
            }
            .frame(width: session.fullWidth, height: session.fullHeight, alignment: .topLeading)
            .offset(x: session.fullOrigin.x, y: session.fullOrigin.y)
            .task(id: node.assetRelativePath) {
                loadedImage = loadImage()
            }
        }
    }

    // Darkened + lightly blurred outside the crop rect, so the excluded area
    // reads clearly as excluded rather than just dimmer.
    @ViewBuilder
    private func dimmedFullImage(session: CropSession) -> some View {
        Group {
            if let loadedImage {
                Image(nsImage: loadedImage).resizable()
            } else {
                Rectangle().fill(Color.gray.opacity(0.15))
            }
        }
        .frame(width: session.fullWidth, height: session.fullHeight)
        .blur(radius: 6)
        .overlay(Color.black.opacity(0.55))
    }

    // The sharp (unblurred, undimmed) crop window — same offset-then-frame-
    // and-clip windowing technique as ImageNodeContentView/Crop-Resize, just
    // positioned within this editor's larger full-image canvas. Also the
    // surface for "drag inside the rect (not on a handle) pans the crop
    // window" per spec.
    @ViewBuilder
    private func sharpCropWindow(session: CropSession, rect: CGRect) -> some View {
        Group {
            if let loadedImage {
                Image(nsImage: loadedImage)
                    .resizable()
                    .frame(width: session.fullWidth, height: session.fullHeight)
                    .offset(x: -rect.minX, y: -rect.minY)
            }
        }
        .frame(width: rect.width, height: rect.height, alignment: .topLeading)
        .clipped()
        .contentShape(Rectangle())
        .offset(x: rect.minX, y: rect.minY)
        .gesture(panGesture)
    }

    // Rule-of-thirds guide, shown only while actively adjusting (dragging a
    // handle or panning), per spec.
    private func thirdsGrid(rect: CGRect) -> some View {
        Path { path in
            for i in 1...2 {
                let x = rect.minX + rect.width * CGFloat(i) / 3
                path.move(to: CGPoint(x: x, y: rect.minY))
                path.addLine(to: CGPoint(x: x, y: rect.maxY))
                let y = rect.minY + rect.height * CGFloat(i) / 3
                path.move(to: CGPoint(x: rect.minX, y: y))
                path.addLine(to: CGPoint(x: rect.maxX, y: y))
            }
        }
        .stroke(Color.white.opacity(0.7), lineWidth: 1)
        .allowsHitTesting(false)
    }

    // Fixed on-screen size regardless of zoom, same reasoning as the Resize
    // Handle elsewhere (BUGS.md #6).
    private func handleView(_ handle: Handle, rect: CGRect) -> some View {
        let x: CGFloat = handle.affectsLeft ? rect.minX : (handle.affectsRight ? rect.maxX : rect.midX)
        let y: CGFloat = handle.affectsTop ? rect.minY : (handle.affectsBottom ? rect.maxY : rect.midY)
        let diameter: CGFloat = 10 / canvas.scale
        return Circle()
            .fill(Color(nsColor: .controlBackgroundColor))
            .overlay(Circle().stroke(Color.accentColor, lineWidth: 1.5 / canvas.scale))
            .frame(width: diameter, height: diameter)
            .position(x: x, y: y)
            .gesture(handleDragGesture(handle))
    }

    // Shift/Option modifiers (Session 2 Vague 5), matching the same
    // conventions as NodeView's own Resize Handle: Option anchors the crop
    // rectangle at its center (both edges of each dragged axis move
    // together, opposite the handle, rather than just the one under the
    // cursor); Shift locks the rectangle to the node's on-screen aspect
    // ratio while doing so. Without Option, a single handle always anchors
    // at the opposite corner/edge, exactly as before.
    private func handleDragGesture(_ handle: Handle) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(CanvasViewModel.viewportCoordinateSpaceName))
            .onChanged { value in
                if dragStartDraft == nil {
                    dragStartDraft = canvas.cropSession?.draftCrop
                    isAdjusting = true
                }
                guard let start = dragStartDraft, let session = canvas.cropSession else { return }
                let (dxFraction, dyFraction) = fractionDelta(value: value, session: session)
                if Self.isOptionHeld {
                    canvas.cropSession?.draftCrop = Self.centerAnchoredAdjusted(
                        start: start, dxFraction: dxFraction, dyFraction: dyFraction,
                        handle: handle, lockRatio: Self.isShiftHeld
                    )
                } else {
                    canvas.cropSession?.draftCrop = Self.adjusted(start: start, dxFraction: dxFraction, dyFraction: dyFraction, handle: handle)
                }
            }
            .onEnded { _ in
                dragStartDraft = nil
                isAdjusting = false
            }
    }

    private static var isShiftHeld: Bool { NSEvent.modifierFlags.contains(.shift) }
    private static var isOptionHeld: Bool { NSEvent.modifierFlags.contains(.option) }

    // Drag inside the rect (not on a handle): pans the crop window over the
    // image without resizing it, per spec.
    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(CanvasViewModel.viewportCoordinateSpaceName))
            .onChanged { value in
                if dragStartDraft == nil {
                    dragStartDraft = canvas.cropSession?.draftCrop
                    isAdjusting = true
                }
                guard let start = dragStartDraft, let session = canvas.cropSession else { return }
                let (dxFraction, dyFraction) = fractionDelta(value: value, session: session)
                canvas.cropSession?.draftCrop = Self.panned(start: start, dxFraction: dxFraction, dyFraction: dyFraction)
            }
            .onEnded { _ in
                dragStartDraft = nil
                isAdjusting = false
            }
    }

    private func fractionDelta(value: DragGesture.Value, session: CropSession) -> (Double, Double) {
        let translation = CGSize(
            width: (value.location.x - value.startLocation.x) / canvas.scale,
            height: (value.location.y - value.startLocation.y) / canvas.scale
        )
        return (translation.width / session.fullWidth, translation.height / session.fullHeight)
    }

    // Always clamped to 0...1 — the source image's own real bounds — so it's
    // never possible to "crop" outside pixels that actually exist.
    private static func adjusted(start: CropFraction, dxFraction: Double, dyFraction: Double, handle: Handle) -> CropFraction {
        var crop = start
        if handle.affectsLeft {
            let rightEdge = start.x + start.width
            let newX = min(max(start.x + dxFraction, 0), rightEdge - minFraction)
            crop.x = newX
            crop.width = rightEdge - newX
        }
        if handle.affectsRight {
            crop.width = min(max(start.width + dxFraction, minFraction), 1 - start.x)
        }
        if handle.affectsTop {
            let bottomEdge = start.y + start.height
            let newY = min(max(start.y + dyFraction, 0), bottomEdge - minFraction)
            crop.y = newY
            crop.height = bottomEdge - newY
        }
        if handle.affectsBottom {
            crop.height = min(max(start.height + dyFraction, minFraction), 1 - start.y)
        }
        return crop
    }

    /// Option-held variant: the two edges of each axis a handle affects move
    /// symmetrically outward/inward from the rectangle's own center, rather
    /// than just the one edge under the cursor with the opposite one fixed.
    /// Because both edges of an axis can move at once here, the available
    /// room before hitting the source image's 0...1 bounds is whichever of
    /// the two sides is closer to its own edge — clamping only the dragged
    /// side (as `adjusted` above does, safe there since its opposite edge
    /// never moves) would let the far side run past the image's actual
    /// bounds. maxHalfExtent below takes the smaller of the two distances on
    /// each axis so both edges stay within 0...1 together (the "4-side"
    /// bounds fix, Session 2 Vague 5).
    private static func centerAnchoredAdjusted(start: CropFraction, dxFraction: Double, dyFraction: Double, handle: Handle, lockRatio: Bool) -> CropFraction {
        var crop = start
        let centerX = start.x + start.width / 2
        let centerY = start.y + start.height / 2
        let maxHalfExtentX = min(centerX, 1 - centerX)
        let maxHalfExtentY = min(centerY, 1 - centerY)

        var halfWidth = start.width / 2
        var halfHeight = start.height / 2
        if handle.affectsLeft || handle.affectsRight {
            let signedDelta = handle.affectsRight ? dxFraction : -dxFraction
            halfWidth = min(max(halfWidth + signedDelta, minFraction / 2), maxHalfExtentX)
        }
        if handle.affectsTop || handle.affectsBottom {
            let signedDelta = handle.affectsBottom ? dyFraction : -dyFraction
            halfHeight = min(max(halfHeight + signedDelta, minFraction / 2), maxHalfExtentY)
        }

        if lockRatio, start.width > 0, start.height > 0 {
            let aspect = start.width / start.height
            if handle.affectsLeft || handle.affectsRight {
                halfHeight = min(halfWidth / aspect, maxHalfExtentY)
                halfWidth = halfHeight * aspect
            } else {
                halfWidth = min(halfHeight * aspect, maxHalfExtentX)
                halfHeight = halfWidth / aspect
            }
        }

        crop.width = halfWidth * 2
        crop.height = halfHeight * 2
        crop.x = centerX - halfWidth
        crop.y = centerY - halfHeight
        return crop
    }

    private static func panned(start: CropFraction, dxFraction: Double, dyFraction: Double) -> CropFraction {
        var crop = start
        crop.x = min(max(start.x + dxFraction, 0), 1 - start.width)
        crop.y = min(max(start.y + dyFraction, 0), 1 - start.height)
        return crop
    }

    private func loadImage() -> NSImage? {
        guard let relativePath = node.assetRelativePath else { return nil }
        return NSImage(contentsOf: boardURL.appendingPathComponent(relativePath))
    }
}
