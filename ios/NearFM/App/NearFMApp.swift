import SwiftUI

@main
struct NearFMApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background { model.player.checkpoint() }
                }
        }
    }
}
