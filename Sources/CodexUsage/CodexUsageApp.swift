import SwiftUI

struct CodexUsageApp: App {
    @StateObject private var model = UsageModel()

    var body: some Scene {
        Window("Codex Usage", id: "main") {
            UsageView(model: model)
                .onAppear { model.start() }
                .onDisappear { model.stop() }
        }
        .defaultSize(width: 380, height: 600)
        .windowResizability(.contentMinSize)
    }
}
