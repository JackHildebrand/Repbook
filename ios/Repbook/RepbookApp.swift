import SwiftUI

@main
struct RepbookApp: App {
    @AppStorage("appearance") private var appearance = "system"
    @StateObject private var store = WorkoutStore.shared
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store).tint(.primary)
                .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
                .onChange(of: scenePhase) { _, phase in if phase == .active { store.scheduleActivityUpdate() } }
        }
    }
}
