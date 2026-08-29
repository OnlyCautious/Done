//
//  DONEApp.swift
//  DONE
//

import SwiftUI
import SwiftData

@main
struct DONEApp: App {
    private let boardStore = BoardStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.boardURL, boardStore.boardURL)
        }
        .modelContainer(boardStore.modelContainer)
    }
}
