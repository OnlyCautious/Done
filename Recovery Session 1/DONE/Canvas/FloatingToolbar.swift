//
//  FloatingToolbar.swift
//  DONE
//

import SwiftUI

/// Floating Toolbar (Phase 2): a horizontal bar anchored at the bottom of the
/// canvas, giving access to creation tools. Structure only for now, per the
/// spec — one button (Shape Tool); visual polish (final icon, spacing,
/// materials) comes in a dedicated design pass later.
struct FloatingToolbar: View {
    var canvas: CanvasViewModel

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(ShapeType.allCases, id: \.self) { shapeType in
                    Button(shapeType.label) {
                        canvas.activeTool = .shape(shapeType)
                    }
                }
            } label: {
                Image(systemName: "square.on.circle")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isShapeToolActive ? Color.accentColor : Color.primary)
                    .frame(width: 28, height: 28)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        .padding(.bottom, 16)
    }

    private var isShapeToolActive: Bool {
        if case .shape = canvas.activeTool { return true }
        return false
    }
}

private extension ShapeType {
    var label: String {
        switch self {
        case .rectangle: "Rectangle"
        case .ellipse: "Ellipse"
        }
    }
}
