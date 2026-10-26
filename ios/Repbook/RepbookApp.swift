import SwiftUI

@main
struct RepbookApp: App {
    @StateObject private var store = WorkoutStore.shared
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store).preferredColorScheme(.dark).tint(.blue)
                .onChange(of: scenePhase) { _, phase in if phase == .active { store.scheduleActivityUpdate() } }
        }
    }
}
