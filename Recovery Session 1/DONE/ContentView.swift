//
//  ContentView.swift
//  DONE
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import ImageIO

struct ContentView: View {
    @State private var canvasViewModel = CanvasViewModel()
    @Environment(\.modelContext) private var modelContext
    @Environment(\.undoManager) private var undoManager
    @Environment(\.boardURL) private var boardURL
    @Query(sort: \BoardNode.zIndex) private var nodes: [BoardNode]

    // The canvas otherwise has no persistent keyboard focus target: the only
    // other @FocusState in the app is the text note's TextEditor, which only
    // holds focus while actively editing. Without this, .onDeleteCommand and
    // the TextEditor's .onExitCommand have nothing reliable in the responder
    // chain to route to once that TextEditor engages and resigns focus (or
    // even before it ever does) — Delete/Backspace/Escape silently no-op with
    // a system beep instead of being handled. Diagnosed for BUGS.md Vague 4 #1.
    @FocusState private var isCanvasFocused: Bool

    var body: some View {
        CanvasView(
            viewModel: canvasViewModel,
            contentBounds: contentBounds,
            onBackgroundDoubleClick: createTextNote,
            onBackgroundClick: { canvasViewModel.deselectAll() },
            onMarqueeSelect: handleMarqueeSelect,
            onShapeCreate: createShapeNode,
            onDropFile: handleDrop,
            onCropCancel: { canvasViewModel.cancelCropping() },
            onCropSave: saveCrop
        ) {
            ForEach(nodes) { node in
                NodeView(node: node, canvas: canvasViewModel, onInteract: {
                    bringToFront(node)
                }, onGroupDragEnd: { delta in
                    commitGroupDrag(by: delta)
                })
            }
        }
        .ignoresSafeArea()
        .focusable()
        // Without this, macOS draws (and, while the window is key, keeps
        // redrawing on every view update — including every pan tick, since
        // panning changes viewModel.offset) the default system focus ring
        // around this view, which covers the whole canvas. Inactive windows
        // never show a focus ring at all, which is why panning was only
        // choppy while DONE was the active window. Diagnosed for BUGS.md
        // Vague 5 #1 — this .focusable() was added in Vague 4 #1 and the
        // timing lines up exactly with when the choppiness was first
        // reported. Keyboard focus/responder-chain behavior (Delete/Escape)
        // is unaffected; only the visual ring is suppressed.
        .focusEffectDisabled()
        .focused($isCanvasFocused)
        .onDeleteCommand(perform: deleteSelectedNodes)
        // A newly-created shape stays selected until the user clicks elsewhere
        // or presses Escape (Phase 2 #2) — deselecting is otherwise not tied
        // to any existing command. Escape during a Crop Tool session instead
        // has the same effect as Cancel (discard the draft, keep the node
        // selected), per spec — not a full deselect (BUGS.md Vague 10 #4).
        .onExitCommand {
            if canvasViewModel.cropSession != nil {
                canvasViewModel.cancelCropping()
            } else {
                canvasViewModel.deselectAll()
            }
        }
        .onAppear {
            connectUndoManager()
            isCanvasFocused = true
        }
        .onChange(of: undoManager) { _, _ in connectUndoManager() }
        // Restore canvas focus whenever text-editing ends, however it ends
        // (Escape, clicking elsewhere, deleting the node) — the TextEditor is
        // the only other thing in the app that ever takes focus away.
        .onChange(of: canvasViewModel.editingNodeID) { _, newValue in
            if newValue == nil {
                isCanvasFocused = true
            }
        }
    }

    private func connectUndoManager() {
        modelContext.undoManager = undoManager
    }

    private func nextZIndex() -> Int {
        (nodes.map(\.zIndex).max() ?? 0) + 1
    }

    private var contentBounds: CGRect? {
        guard !nodes.isEmpty else { return nil }
        let minX = nodes.map(\.x).min() ?? 0
        let minY = nodes.map(\.y).min() ?? 0
        let maxX = nodes.map { $0.x + $0.width }.max() ?? 0
        let maxY = nodes.map { $0.y + $0.height }.max() ?? 0
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func bringToFront(_ node: BoardNode) {
        guard node.zIndex != nextZIndex() - 1 else { return }
        // Selecting a node shouldn't itself become an undo step (only create,
        // move, resize, and delete should) — bumping stacking order is an
        // incidental side effect of selection, so it's excluded here.
        let manager = modelContext.undoManager
        modelContext.undoManager = nil
        node.zIndex = nextZIndex()
        try? modelContext.save()
        modelContext.undoManager = manager
    }

    private func createTextNote(at canvasPoint: CGPoint) {
        canvasViewModel.deselectAll()
        let node = BoardNode(
            kind: .text,
            x: canvasPoint.x - 110,
            y: canvasPoint.y - 70,
            width: 220,
            height: 140,
            zIndex: nextZIndex()
        )
        modelContext.insert(node)
        try? modelContext.save()
        canvasViewModel.select(node.id)
        canvasViewModel.editingNodeID = node.id
    }

    // Group drag (BUGS.md Vague 6 #1): applies the same delta to every
    // selected node in one synchronous pass, so it registers as a single
    // undo step rather than one per node — same reasoning as
    // deleteSelectedNodes below.
    private func commitGroupDrag(by delta: CGSize) {
        let selectedIDs = canvasViewModel.selectedNodeIDs
        for node in nodes where selectedIDs.contains(node.id) {
            node.x += delta.width
            node.y += delta.height
        }
        try? modelContext.save()
    }

    // Shape Tool (Phase 2 #2): click-drag on the canvas while a shape type is
    // armed creates that shape sized to the drag, then hands control back to
    // the Selection Tool with the new shape selected — Resize Handle visible
    // — until the user clicks elsewhere or presses Escape.
    private static let minShapeDragSize: CGFloat = 8

    private func createShapeNode(type: ShapeType, in canvasRect: CGRect) {
        canvasViewModel.activeTool = .selection
        guard canvasRect.width >= Self.minShapeDragSize, canvasRect.height >= Self.minShapeDragSize else { return }

        let node = BoardNode(
            kind: .shape,
            x: canvasRect.minX,
            y: canvasRect.minY,
            width: canvasRect.width,
            height: canvasRect.height,
            zIndex: nextZIndex(),
            shapeType: type
        )
        modelContext.insert(node)
        try? modelContext.save()
        canvasViewModel.select(node.id)
    }

    // Crop Tool Save (BUGS.md Vague 10 #4): writes the session's draft crop
    // to the actual node — the only place this happens; every other exit
    // path (Cancel, Escape, clicking elsewhere) just discards
    // canvasViewModel.cropSession without ever reaching here, so an
    // unconfirmed crop is never silently persisted. The node's frame
    // (width/height/x/y) is derived from the draft against the session's
    // fixed full-image reference, matching Crop-Resize/ImageCropEditorView's
    // own math.
    private func saveCrop() {
        defer { canvasViewModel.cropSession = nil }
        guard let session = canvasViewModel.cropSession,
              let node = nodes.first(where: { $0.id == session.nodeID }) else { return }
        let crop = session.draftCrop
        node.width = crop.width * session.fullWidth
        node.height = crop.height * session.fullHeight
        node.x = session.fullOrigin.x + crop.x * session.fullWidth
        node.y = session.fullOrigin.y + crop.y * session.fullHeight
        node.cropX = crop.x
        node.cropY = crop.y
        node.cropWidth = crop.width
        node.cropHeight = crop.height
        try? modelContext.save()
    }

    private func deleteSelectedNodes() {
        let idsToDelete = canvasViewModel.selectedNodeIDs
        guard !idsToDelete.isEmpty else { return }
        canvasViewModel.deselectAll()
        for node in nodes where idsToDelete.contains(node.id) {
            modelContext.delete(node)
        }
        try? modelContext.save()
    }

    // Marquee Selection (BUGS.md Vague 3 #2, live per Vague 5 #2): selects
    // every node whose frame intersects the dragged rectangle (canvas
    // space), continuously as the rectangle changes. `additiveBase` is the
    // selection to preserve underneath it (Cmd-held Finder-style extend,
    // Vague 5 #3) — empty for a plain marquee, which just replaces.
    private func handleMarqueeSelect(_ canvasRect: CGRect, additiveBase: Set<UUID>) {
        let matchingIDs = nodes.filter { node in
            CGRect(x: node.x, y: node.y, width: node.width, height: node.height).intersects(canvasRect)
        }.map(\.id)
        canvasViewModel.setSelection(additiveBase.union(matchingIDs))
    }

    private func handleDrop(providers: [NSItemProvider], location: CGPoint) -> Bool {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: URL.self) }) else {
            return false
        }
        let canvasPoint = canvasViewModel.canvasPoint(fromScreen: location)
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            DispatchQueue.main.async {
                createImageNode(from: url, at: canvasPoint)
            }
        }
        return true
    }

    private func createImageNode(from sourceURL: URL, at canvasPoint: CGPoint) {
        guard let utType = UTType(filenameExtension: sourceURL.pathExtension),
              utType.conforms(to: .image),
              let pixelSize = Self.pixelSize(of: sourceURL) else { return }

        let assetsURL = boardURL.appendingPathComponent("assets", isDirectory: true)
        let filename = "\(UUID().uuidString).\(sourceURL.pathExtension)"
        let destinationURL = assetsURL.appendingPathComponent(filename)
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            return
        }

        let aspectRatio = pixelSize.width / max(pixelSize.height, 1)
        let maxDimension: CGFloat = 320
        let width = aspectRatio >= 1 ? maxDimension : maxDimension * aspectRatio
        let height = aspectRatio >= 1 ? maxDimension / aspectRatio : maxDimension

        let node = BoardNode(
            kind: .image,
            x: canvasPoint.x - width / 2,
            y: canvasPoint.y - height / 2,
            width: width,
            height: height,
            zIndex: nextZIndex(),
            assetRelativePath: "assets/\(filename)",
            aspectRatio: aspectRatio
        )
        modelContext.insert(node)
        try? modelContext.save()
        canvasViewModel.select(node.id)
    }

    private static func pixelSize(of url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat else { return nil }
        return CGSize(width: width, height: height)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: BoardNode.self, inMemory: true)
}
