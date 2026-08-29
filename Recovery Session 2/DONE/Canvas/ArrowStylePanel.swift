//
//  ArrowStylePanel.swift
//  DONE
//

import SwiftUI
import SwiftData

/// Arrow Style Panel (Phase 3 step 3/6, GLOSSARY.md): a small floating
/// panel, shown whenever the selection consists entirely of one or more
/// Arrow Nodes, for controlling stroke style (solid/dashed) and width.
/// ContentView computes its position (above the selection's bounding box,
/// flipping below if too close to the canvas viewport's top edge) and
/// passes in exactly the arrow nodes it applies to.
struct ArrowStylePanel: View {
    /// The selected Arrow Nodes this panel edits — always non-empty and
    /// entirely .arrow-kind; ContentView only instantiates this view when
    /// that holds.
    var arrows: [BoardNode]

    @Environment(\.modelContext) private var modelContext

    // Continuous-drag undo grouping (same convention as TextNoteContentView/
    // ShapeNodeContentView's autosave and NodeView's Crop-Resize): only the
    // first width change of a single slider drag registers with the undo
    // manager, so undoing the whole drag is one step rather than one per
    // pixel — see widthBinding below.
    @State private var hasRegisteredWidthUndoThisSession = false

    private static let widthRange: ClosedRange<Double> = 1...12

    /// nil when the selected arrows don't all share the same style/width —
    /// shown as an indeterminate/neutral state (neither style button
    /// highlighted; "—" instead of a specific width) rather than picking one
    /// arbitrarily, per spec.
    private var commonStyle: ArrowStrokeStyle? {
        let styles = Set(arrows.map { $0.arrowStrokeStyle ?? .solid })
        return styles.count == 1 ? styles.first : nil
    }

    private var commonWidth: Double? {
        let widths = Set(arrows.map(\.arrowStrokeWidth))
        return widths.count == 1 ? widths.first : nil
    }

    /// A Slider always needs one concrete Double to position its thumb at —
    /// there's no native "indeterminate" thumb position — so a mixed
    /// selection falls back to the average width as a neutral starting
    /// point rather than an arbitrary single arrow's value. The visible
    /// label still reads "—" in that case (see body) so the average isn't
    /// mistaken for an actual shared value.
    private var averageWidth: Double {
        guard !arrows.isEmpty else { return 2 }
        return arrows.map(\.arrowStrokeWidth).reduce(0, +) / Double(arrows.count)
    }

    var body: some View {
        HStack(spacing: 12) {
            styleControl
            Divider().frame(height: 16)
            widthControl
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
    }

    private var styleControl: some View {
        HStack(spacing: 4) {
            styleButton(.solid, label: "Plein")
            styleButton(.dashed, label: "Pointillé")
        }
    }

    private func styleButton(_ style: ArrowStrokeStyle, label: String) -> some View {
        let isActive = commonStyle == style
        return Button(label) {
            for arrow in arrows { arrow.arrowStrokeStyle = style }
            try? modelContext.save()
        }
        .buttonStyle(.plain)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(isActive ? Color.white : Color.primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isActive ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 6))
    }

    private var widthControl: some View {
        HStack(spacing: 6) {
            Slider(value: widthBinding, in: Self.widthRange, onEditingChanged: { isEditing in
                if !isEditing { hasRegisteredWidthUndoThisSession = false }
            })
            .frame(width: 90)
            Text(commonWidth.map { "\(Int($0))pt" } ?? "—")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 28, alignment: .leading)
        }
    }

    /// Writes straight to every selected arrow on each slider tick — same
    /// live-update-with-grouped-undo pattern as Crop-Resize (NodeView) and
    /// the text/shape autosave paths: after the first tick of a drag opens
    /// a real undo registration, every subsequent tick in that same drag
    /// suppresses registration (disableUndoRegistration/enableUndoRegistration,
    /// never nil-ing modelContext.undoManager itself — see BUGS.md Session 2
    /// Vague 1 #1 for why that distinction matters) so the whole drag still
    /// undoes in one step. onEditingChanged above resets the flag when the
    /// drag ends, so the *next* drag starts its own fresh undo entry.
    private var widthBinding: Binding<Double> {
        Binding(
            get: { commonWidth ?? averageWidth },
            set: { newValue in
                if hasRegisteredWidthUndoThisSession {
                    modelContext.undoManager?.disableUndoRegistration()
                    for arrow in arrows { arrow.arrowStrokeWidth = newValue }
                    modelContext.undoManager?.enableUndoRegistration()
                } else {
                    for arrow in arrows { arrow.arrowStrokeWidth = newValue }
                    hasRegisteredWidthUndoThisSession = true
                }
                try? modelContext.save()
            }
        )
    }
}
