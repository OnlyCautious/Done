//
//  CropActionBar.swift
//  DONE
//

import SwiftUI

/// Bottom action bar shown for the whole duration of a Crop Tool session
/// (BUGS.md Vague 10 #4), replacing the Floating Toolbar in the same spot so
/// the two never overlap. Cancel discards the draft crop; Save commits it.
/// A "Rotate left" button appears in the Milanote reference this was modeled
/// on — explicitly out of scope for this pass, not implemented.
struct CropActionBar: View {
    var onCancel: () -> Void
    var onSave: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
            Button("Save", action: onSave)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        .padding(.bottom, 16)
    }
}
