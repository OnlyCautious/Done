//
//  TextNoteContentView.swift
//  DONE
//

import SwiftUI
import SwiftData

struct TextNoteContentView: View {
    @Bindable var node: BoardNode
    var isEditing: Bool
    var onCommit: () -> Void

    @Environment(\.modelContext) private var modelContext
    @FocusState private var isFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    // Buffered locally while editing, same reasoning as Text Note: writing
    // straight to node.text would register one undo action per keystroke.
    @State private var draftText: String = ""
    @State private var hasRegisteredUndoThisSession = false

    // A flat yellow reads as a washed-out gray-brown against a near-black
    // canvas background at light-mode opacity, so dark mode gets a bit more
    // saturation to keep the "sticky note" look recognizable in both.
    private var noteBackground: Color {
        Color.yellow.opacity(colorScheme == .dark ? 0.35 : 0.25)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8)
                .fill(noteBackground)

            if isEditing {
                TextEditor(text: $draftText)
                    .scrollContentBackground(.hidden)
                    .font(.system(size: 14))
                    .padding(8)
                    .focused($isFocused)
                    .onExitCommand(perform: onCommit)
            } else {
                Text(node.text.isEmpty ? "Double-click to edit" : node.text)
                    .font(.system(size: 14))
                    .foregroundStyle(node.text.isEmpty ? .secondary : .primary)
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

    // Every keystroke saves immediately so text is never lost (clicking
    // elsewhere never wipes it), while still registering only the *first*
    // mutation of an edit session with the undo manager — otherwise every
    // keystroke would be its own undo step.
    //
    // disableUndoRegistration()/enableUndoRegistration() suppress
    // registration for the subsequent keystrokes, rather than nil-ing
    // modelContext.undoManager itself and restoring it right after (Session 2
    // Vague 1 #1): detaching that binding right after the first keystroke had
    // already opened a real undo registration for this node corrupted
    // SwiftData's internal snapshot bookkeeping, crashing the app on a
    // subsequent keystroke or shortly after (Session 2 Vague 1 #2).
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
