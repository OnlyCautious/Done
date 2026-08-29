//
//  ShapeNodeContentView.swift
//  DONE
//

import SwiftUI
import SwiftData

/// Renders a Shape Node's fill/stroke and its embedded text — same double-
/// click-to-edit, autosave-as-you-type behavior as Text Note (Phase 2 #4).
struct ShapeNodeContentView: View {
    @Bindable var node: BoardNode
    var isEditing: Bool
    var onCommit: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isFocused: Bool

    // Buffered locally while editing, same reasoning as Text Note: writing
    // straight to node.text would register one undo action per keystroke.
    @State private var draftText: String = ""
    @State private var hasRegisteredUndoThisSession = false

    // Semantic, theme-adaptive defaults — there's no Color Palette Tool yet to
    // set a custom color per shape, so these aren't persisted; adding
    // fill/stroke fields to BoardNode later (when that tool exists) is a
    // trivial additive change.
    private var fillColor: Color {
        Color.accentColor.opacity(colorScheme == .dark ? 0.28 : 0.15)
    }
    private var strokeColor: Color { Color.accentColor }

    var body: some View {
        ZStack {
            shape
                .fill(fillColor)
                .overlay(shape.stroke(strokeColor, lineWidth: 2))

            if isEditing {
                TextEditor(text: $draftText)
                    .scrollContentBackground(.hidden)
                    .font(.system(size: 14))
                    .multilineTextAlignment(.center)
                    .padding(10)
                    .focused($isFocused)
                    .onExitCommand(perform: onCommit)
            } else if !node.text.isEmpty {
                Text(node.text)
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .padding(10)
            }
        }
        .onChange(of: isEditing) { _, editing in
            if editing {
                draftText = node.text
                hasRegisteredUndoThisSession = false
                isFocused = true
            }
        }
        .onChange(of: isFocused) { _, focused in
            if !focused && isEditing { onCommit() }
        }
        .onChange(of: draftText) { _, newValue in
            guard isEditing else { return }
            autosave(newValue)
        }
    }

    // AnyShape (type-erased): RoundedRectangle and Ellipse are different
    // concrete Shape types, so a switch can't return "some Shape" directly.
    private var shape: AnyShape {
        switch node.shapeType ?? .rectangle {
        case .rectangle:
            AnyShape(RoundedRectangle(cornerRadius: 6))
        case .ellipse:
            AnyShape(Ellipse())
        }
    }

    // Same pattern as TextNoteContentView.autosave(_:) — including the same
    // disableUndoRegistration()/enableUndoRegistration() fix (Session 2
    // Vague 1 #1/#2): every keystroke saves immediately so text is never
    // lost, but only the first mutation of the session registers with the
    // undo manager, so undoing the whole edit is still one step rather than
    // one per character. Nil-ing modelContext.undoManager itself (the
    // earlier approach) corrupted SwiftData's snapshot bookkeeping for this
    // node and crashed the app.
    private func autosave(_ newValue: String) {
        if hasRegisteredUndoThisSession {
            modelContext.undoManager?.disableUndoRegistration()
            node.text = newValue
            modelContext.undoManager?.enableUndoRegistration()
        } else {
            node.text = newValue
            hasRegisteredUndoThisSession = true
        }
        try? modelContext.save()
    }
}
