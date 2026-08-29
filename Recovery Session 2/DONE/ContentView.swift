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
            allNodes: nodes,
            onBackgroundDoubleClick: createTextNote,
            onBackgroundClick: { canvasViewModel.deselectAll() },
            onMarqueeSelect: handleMarqueeSelect,
            onShapeCreate: createShapeNode,
            onArrowCreate: createArrowNode,
            onDropFile: handleDrop,
            onCropCancel: { canvasViewModel.cancelCropping() },
            onCropSave: saveCrop
        ) {
            ForEach(nodes) { node in
                nodeView(for: node)
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
        .overlay(alignment: .topLeading) { arrowStylePanelOverlay }
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

    // Extracted out of the ForEach closure above (rather than an inline
    // if/else in a trailing closure) because the compiler could no longer
    // type-check that closure in reasonable time once the .arrow branch
    // (a completely different view type, ArrowNodeView, with its own
    // distinct set of parameters) was added alongside NodeView's — a bare
    // @ViewBuilder function with an explicit `some View` return doesn't hit
    // the same inference blow-up a large inferred-type ForEach closure does.
    @ViewBuilder
    private func nodeView(for node: BoardNode) -> some View {
        if node.kind == .arrow {
            ArrowNodeView(
                node: node,
                canvas: canvasViewModel,
                onInteract: { bringToFront(node) },
                onGroupDragEnd: { delta in commitGroupDrag(by: delta) },
                allNodes: nodes
            )
        } else {
            NodeView(node: node, canvas: canvasViewModel, onInteract: {
                bringToFront(node)
            }, onGroupDragEnd: { delta in
                commitGroupDrag(by: delta)
            })
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
    //
    // Arrow-aware (Phase 3, extending the original Vague 6 #1 fix): an
    // Arrow Node's own rendering never reads x/y directly, only
    // arrowStart/End/ControlX/Y — moving just the bounding box would leave
    // the arrow itself visually behind while its selection frame moved,
    // so every arrow point is shifted by the same delta too, then the
    // bounding box resynced from them (syncArrowBoundingBox) rather than
    // shifted independently, so the two can never drift apart.
    private func commitGroupDrag(by delta: CGSize) {
        let selectedIDs = canvasViewModel.selectedNodeIDs
        for node in nodes where selectedIDs.contains(node.id) {
            if node.kind == .arrow {
                node.arrowStartX += delta.width
                node.arrowStartY += delta.height
                node.arrowEndX += delta.width
                node.arrowEndY += delta.height
                node.arrowControlX += delta.width
                node.arrowControlY += delta.height
                node.syncArrowBoundingBox()
            } else {
                node.x += delta.width
                node.y += delta.height
            }
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

    // Arrow Tool (Phase 3 step 1/6, extended step 5/6): click-drag on the
    // canvas while the Arrow Tool is armed creates one Arrow Node from
    // start to end, then hands control back to the Selection Tool with the
    // new arrow selected — same one-shot pattern as the Shape Tool above.
    // `connection`, when non-nil (the drag's end point snapped hard onto
    // another arrow's own point), is wired up as the new arrow's
    // endConnection immediately — there's no separate "commit" step for
    // creation the way handle A/B dragging has, since the arrow doesn't
    // exist until this single call.
    private static let minArrowDragDistance: CGFloat = 4

    private func createArrowNode(start: CGPoint, end: CGPoint, connection: ArrowConnection?) {
        canvasViewModel.activeTool = .selection
        guard hypot(end.x - start.x, end.y - start.y) >= Self.minArrowDragDistance else { return }

        let control = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        let node = BoardNode(
            kind: .arrow,
            x: 0, y: 0, width: 0, height: 0,
            zIndex: nextZIndex(),
            arrowStartX: start.x,
            arrowStartY: start.y,
            arrowEndX: end.x,
            arrowEndY: end.y,
            arrowControlX: control.x,
            arrowControlY: control.y
        )
        node.endConnection = connection
        node.syncArrowBoundingBox()
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

    // Connection-cascade delete (Phase 3 step 5/6): deleting an arrow that
    // other, undeleted arrows are connected to would otherwise leave those
    // connections pointing at a targetArrowID that no longer exists —
    // ArrowConnectionResolver.resolvedPoint's own nodesByID[nodeID] lookup
    // would simply fail to find it and fall back to .zero, snapping the
    // connected point to the canvas origin. Before deleting, every
    // surviving arrow's start/endConnection that targets a node about to be
    // deleted is "frozen": its current resolved position (chased through
    // ArrowConnectionResolver first, in case of a multi-hop chain through
    // other arrows also being deleted in this same batch) is written to the
    // raw arrowStart/EndX/Y fields and the connection itself cleared, so the
    // point simply stops following anything and stays exactly where it
    // visually was — never jumps.
    private func deleteSelectedNodes() {
        let idsToDelete = canvasViewModel.selectedNodeIDs
        guard !idsToDelete.isEmpty else { return }
        canvasViewModel.deselectAll()

        let arrowsByID = Dictionary(uniqueKeysWithValues: nodes.filter { $0.kind == .arrow }.map { ($0.id, $0) })
        for node in nodes where node.kind == .arrow && !idsToDelete.contains(node.id) {
            var didFreezeAny = false
            if let connection = node.startConnection, idsToDelete.contains(connection.targetArrowID) {
                let frozen = ArrowConnectionResolver.resolvedPoint(role: connection.targetPoint, of: connection.targetArrowID, nodesByID: arrowsByID)
                node.arrowStartX = frozen.x
                node.arrowStartY = frozen.y
                node.startConnection = nil
                didFreezeAny = true
            }
            if let connection = node.endConnection, idsToDelete.contains(connection.targetArrowID) {
                let frozen = ArrowConnectionResolver.resolvedPoint(role: connection.targetPoint, of: connection.targetArrowID, nodesByID: arrowsByID)
                node.arrowEndX = frozen.x
                node.arrowEndY = frozen.y
                node.endConnection = nil
                didFreezeAny = true
            }
            if didFreezeAny {
                node.syncArrowBoundingBox()
            }
        }

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

        // sourceWidth/sourceHeight/contentScale (Session 2 Vague 3), not the
        // old aspectRatio: BoardNode.init no longer takes a bare ratio —
        // sourceWidth/sourceHeight are the image's real native pixel size
        // (fixed forever at import), and contentScale is the single factor
        // that maps them to on-screen points, initialized here so the
        // imported frame (maxDimension on the longer axis) matches exactly.
        let aspectRatio = pixelSize.width / max(pixelSize.height, 1)
        let maxDimension: CGFloat = 320
        let width = aspectRatio >= 1 ? maxDimension : maxDimension * aspectRatio
        let height = aspectRatio >= 1 ? maxDimension / aspectRatio : maxDimension
        let contentScale = width / max(pixelSize.width, 1)

        let node = BoardNode(
            kind: .image,
            x: canvasPoint.x - width / 2,
            y: canvasPoint.y - height / 2,
            width: width,
            height: height,
            zIndex: nextZIndex(),
            assetRelativePath: "assets/\(filename)",
            sourceWidth: pixelSize.width,
            sourceHeight: pixelSize.height,
            contentScale: contentScale
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

    // MARK: - Arrow Style Panel

    /// The Arrow Style Panel (Phase 3 step 3/6, GLOSSARY.md) shows whenever
    /// the current selection is non-empty and consists *entirely* of Arrow
    /// Nodes — mixed selections (an arrow plus a shape, say) show no panel
    /// at all, per spec, rather than guessing which node it should apply to.
    private var selectedArrowNodes: [BoardNode] {
        guard !canvasViewModel.selectedNodeIDs.isEmpty else { return [] }
        let selected = nodes.filter { canvasViewModel.selectedNodeIDs.contains($0.id) }
        guard selected.allSatisfy({ $0.kind == .arrow }) else { return [] }
        return selected
    }

    /// The bounding box (canvas space) the panel positions itself against —
    /// per-node x/y/width/height ordinarily, except for whichever single
    /// arrow is currently being live-dragged (canvas.liveArrowGeometry),
    /// where the live in-progress points are used instead so the panel
    /// tracks the drag frame-by-frame rather than jumping only once it ends.
    /// Only meaningful for a single-arrow selection — canvas.liveArrowGeometry
    /// is only ever set for the one arrow actually under a handle A/B, body,
    /// or Curve Handle drag, and multi-arrow group drags move every selected
    /// arrow's raw points identically anyway (commitGroupDrag), so the
    /// per-node fallback below already stays live-accurate for those too via
    /// canvas.groupDragDelta — see NodeView/ArrowNodeView's own displayStart/
    /// End for the same pattern.
    private func selectionBoundingBox(for arrows: [BoardNode]) -> CGRect? {
        guard !arrows.isEmpty else { return nil }
        var rects: [CGRect] = []
        for arrow in arrows {
            if let live = canvasViewModel.liveArrowGeometry, live.nodeID == arrow.id {
                let minX = min(live.start.x, live.end.x, live.control.x)
                let minY = min(live.start.y, live.end.y, live.control.y)
                let maxX = max(live.start.x, live.end.x, live.control.x)
                let maxY = max(live.start.y, live.end.y, live.control.y)
                rects.append(CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY))
            } else if canvasViewModel.isGroupDragActive {
                let delta = canvasViewModel.groupDragDelta
                rects.append(CGRect(x: arrow.x + delta.width, y: arrow.y + delta.height, width: arrow.width, height: arrow.height))
            } else {
                rects.append(CGRect(x: arrow.x, y: arrow.y, width: arrow.width, height: arrow.height))
            }
        }
        return rects.dropFirst().reduce(rects[0]) { $0.union($1) }
    }

    private static let arrowStylePanelMargin: CGFloat = 12
    private static let arrowStylePanelApproxHeight: CGFloat = 40
    private static let arrowStylePanelApproxWidth: CGFloat = 220

    @ViewBuilder
    private var arrowStylePanelOverlay: some View {
        let arrows = selectedArrowNodes
        if !arrows.isEmpty, let canvasRect = selectionBoundingBox(for: arrows) {
            let topLeftScreen = canvasViewModel.screenPoint(fromCanvas: CGPoint(x: canvasRect.minX, y: canvasRect.minY))
            let bottomRightScreen = canvasViewModel.screenPoint(fromCanvas: CGPoint(x: canvasRect.maxX, y: canvasRect.maxY))
            let screenRect = CGRect(
                x: topLeftScreen.x, y: topLeftScreen.y,
                width: bottomRightScreen.x - topLeftScreen.x, height: bottomRightScreen.y - topLeftScreen.y
            )
            let centerX = screenRect.midX
            // Prefers directly above the selection, flipping to directly
            // below when there isn't enough room above the viewport's own
            // top edge for the panel to fit without being clipped/covered by
            // the window's title bar.
            let fitsAbove = screenRect.minY - Self.arrowStylePanelApproxHeight - Self.arrowStylePanelMargin >= 0
            let y = fitsAbove
                ? screenRect.minY - Self.arrowStylePanelMargin - Self.arrowStylePanelApproxHeight / 2
                : screenRect.maxY + Self.arrowStylePanelMargin + Self.arrowStylePanelApproxHeight / 2

            ArrowStylePanel(arrows: arrows)
                .position(x: max(centerX, Self.arrowStylePanelApproxWidth / 2), y: max(y, Self.arrowStylePanelApproxHeight / 2))
                .allowsHitTesting(true)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: BoardNode.self, inMemory: true)
}
