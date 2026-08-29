//
//  BoardStore.swift
//  DONE
//

import Foundation
import SwiftData
import SwiftUI

/// Owns the on-disk board document package: a `.doneboard` folder containing
/// the SwiftData store (node positions/content) and an `assets/` subfolder
/// holding copies of dropped images, referenced by relative path. Phase 1 only
/// ever manages a single board at a fixed, deterministic location, so "load
/// the last opened board on launch" is satisfied trivially — there's nothing
/// else it could load. Save/Open-elsewhere for multiple boards is future work.
@MainActor
final class BoardStore {
    let boardURL: URL
    let assetsURL: URL
    let modelContainer: ModelContainer

    init() {
        let boardURL = Self.defaultBoardURL()
        let assetsURL = boardURL.appendingPathComponent("assets", isDirectory: true)
        try? FileManager.default.createDirectory(at: assetsURL, withIntermediateDirectories: true)

        let storeURL = boardURL.appendingPathComponent("data.store")
        let configuration = ModelConfiguration(url: storeURL)
        do {
            modelContainer = try ModelContainer(for: BoardNode.self, configurations: configuration)
        } catch {
            fatalError("Failed to open board store at \(storeURL): \(error)")
        }

        self.boardURL = boardURL
        self.assetsURL = assetsURL
    }

    private static func defaultBoardURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let boardsFolder = appSupport.appendingPathComponent("Boards", isDirectory: true)
        try? FileManager.default.createDirectory(at: boardsFolder, withIntermediateDirectories: true)
        return boardsFolder.appendingPathComponent("My Board.doneboard", isDirectory: true)
    }
}

private struct BoardURLKey: EnvironmentKey {
    static let defaultValue: URL = FileManager.default.temporaryDirectory
}

extension EnvironmentValues {
    /// The current board's document package folder, so node content views can
    /// resolve asset-relative paths without reaching for BoardStore.
    var boardURL: URL {
        get { self[BoardURLKey.self] }
        set { self[BoardURLKey.self] = newValue }
    }
}
