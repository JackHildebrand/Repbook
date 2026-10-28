import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct RootView: View {
    @EnvironmentObject private var store: WorkoutStore
    @State private var selected = 0
    @State private var workout = false
    @State private var summary = false
        var body: some View {
        TabView(selection: $selected) {
            NavigationStack { WorkoutHome(onStart: openWorkout) }.tint(.primary).safeAreaInset(edge: .bottom) { miniBar }
                .tabItem { Label("Home", systemImage: "house.fill") }.tag(0)
            NavigationStack { RoutinesView(onStart: openWorkout) }.tint(.primary).safeAreaInset(edge: .bottom) { miniBar }
                .tabItem { Label("Routines", systemImage: "square.stack.fill") }.tag(1)
            NavigationStack { ProgressionView() }.tint(.primary).safeAreaInset(edge: .bottom) { miniBar }
                .tabItem { Label("Progress", systemImage: "chart.xyaxis.line") }.tag(2)
            NavigationStack { HistoryView() }.tint(.primary).safeAreaInset(edge: .bottom) { miniBar }
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }.tag(3)
        }
        .tint(.blue)
        .onChange(of: selected) { _, _ in
            if UserDefaults.standard.object(forKey: "haptics") as? Bool ?? true { UISelectionFeedbackGenerator().selectionChanged() }
        }
        .onOpenURL { _ in openWorkout() }
        .fullScreenCover(isPresented: $workout, onDismiss: { if store.completedSession != nil { summary = true } }) {
            NavigationStack { ActiveWorkoutView(onMinimize: { workout = false }) }
                .environmentObject(store)
        }
        .sheet(isPresented: $summary) {
            if let session = store.completedSession { WorkoutSummary(session: session) }
        }
        .onChange(of: store.data.active?.id) { _, id in if id == nil { workout = false } }
        .onChange(of: store.completedSession?.id) { _, id in if id == nil { summary = false; selected = 0 } }
        .alert("Repbook", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
        } message: { Text(store.error ?? "") }
    }
    private func openWorkout() {
        guard store.data.active != nil else { selected = 0; return }
        store.currentSetNavigation = UUID(); workout = true
    }
    @ViewBuilder private var miniBar: some View {
        if let session = store.data.active {
            MiniWorkoutBar(session: session, action: openWorkout).padding(.horizontal, 20).padding(.vertical, 8)
        }
    }
}

struct MiniWorkoutBar: View {
    @EnvironmentObject private var store: WorkoutStore
    let session: Session
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "dumbbell.fill").foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.name).font(.headline).lineLimit(1)
                    if let next = session.nextSet {
                        Text("\(store.name(session.exercises[next.exercise].exerciseID)) · Set \(next.set + 1)")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    } else { Text("All sets logged").font(.caption).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 0)
                Text(session.started, style: .timer).font(.subheadline.weight(.semibold)).monospacedDigit()
                Image(systemName: "chevron.up").font(.caption)
            }.padding(16).frame(minHeight: 64).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .modifier(FloatingWorkoutSurface())
            .overlay(Capsule().strokeBorder(.primary.opacity(0.06)))
            .accessibilityLabel("Resume \(session.name) at current set")
    }
}

struct RoutinesView: View {
    var onStart: () -> Void
    @EnvironmentObject private var store: WorkoutStore
    @State private var editor: Routine?
    @State private var query = ""
    @State private var pendingStart: Routine?
    @State private var pendingDelete: Routine?
    @State private var scheduling = false
    var body: some View {
        List {
            if store.data.routines.isEmpty {
                ContentUnavailableView("Make it your routine", systemImage: "square.stack", description: Text("Save your exercises and start faster next time."))
            }
            ForEach(store.data.routines.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { routine in
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(routine.name).font(.title2.bold())
                            Text("\(routine.exercises.count) exercises · \(routine.exercises.reduce(0) { $0 + $1.sets.count }) working sets")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Menu {
                            Button("Edit", systemImage: "pencil") { editor = routine }
                            Button("Duplicate", systemImage: "plus.square.on.square") {
                                var copy = routine; copy.id = UUID().uuidString; copy.name += " copy"
                                editor = copy
                            }
                            Button("Schedule", systemImage: "calendar") { scheduling = true }
                            Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = routine }
                        } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                            .accessibilityLabel("Actions for \(routine.name)")
                    }
                    let weekdays = [2, 3, 4, 5, 6, 7, 1].filter { store.data.weekdayRoutines?[String($0)] == routine.id }
                    if !weekdays.isEmpty {
                        Text(weekdays.map { Calendar.current.shortWeekdaySymbols[$0 - 1] }.joined(separator: ", "))
                            .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    }
                    Text(routine.exercises.prefix(3).map { store.name($0.exerciseID) }.joined(separator: " · "))
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                    Button {
                        if store.data.active != nil { pendingStart = routine }
                        else { store.start(routine); onStart() }
                    } label: { Label("Start workout", systemImage: "play.fill").frame(maxWidth: .infinity) }
                        .buttonStyle(RepbookPrimaryStyle())
                }.padding(.vertical, 12)
            }
        }.navigationTitle("Routines").searchable(text: $query, prompt: "Find a routine")
        .toolbar { Button { editor = Routine(name: "New routine") } label: { Image(systemName: "plus") }.accessibilityLabel("New routine") }
        .sheet(item: $editor) { RoutineEditor(draft: $0) }
        .sheet(isPresented: $scheduling) { ScheduleSheet() }
        .confirmationDialog("Delete this routine?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
            Button("Delete routine", role: .destructive) {
                guard let id = pendingDelete?.id else { return }
                store.change {
                    $0.routines.removeAll { $0.id == id }
                    $0.weekdayRoutines = $0.weekdayRoutines?.filter { $0.value != id }
                }
                pendingDelete = nil
            }
        }
        .confirmationDialog("A workout is already in progress", isPresented: Binding(get: { pendingStart != nil }, set: { if !$0 { pendingStart = nil } })) {
            Button("Resume workout") { pendingStart = nil; onStart() }
            Button("Cancel", role: .cancel) { pendingStart = nil }
        }
    }
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct SettingsView: View {
    @EnvironmentObject private var store: WorkoutStore
    @State private var importing = false
    @State private var exporting = false
    @State private var pending: Data?
    @State private var confirmImport = false
    @State private var document = BackupDocument(data: Data())
    @State private var scheduling = false
    @State private var csvImporting = false
    @State private var csvResult: HevyImportResult?
    @State private var csvConfirm = false
    @State private var csvMessage: String?
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("haptics") private var haptics = true
    @AppStorage("restLiveActivityAlerts") private var restLiveActivityAlerts = true
    @AppStorage("weightIncrement") private var weightIncrement = 0.0
    @AppStorage("repIncrement") private var repIncrement = 1
    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Appearance", selection: $appearance) {
                    Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark")
                }
            }
            Section("Preferences") {
                NavigationLink("Workout & sets") { workoutPreferences }
                NavigationLink("Notifications & feedback") { feedbackPreferences }
                Button("Weekly schedule") { scheduling = true }
            }
            Section("Data") { NavigationLink("Import, export & backups") { dataPreferences } }
            Section("Widgets & Live Activities") {
                Text("Start a workout to show a Live Activity. Use its controls to adjust weight, reps, and log the current set.").font(.subheadline)
                Text("Hold a Scheduled workout widget and choose Edit Widget to set its weekly routine names. The barbell Lock Screen widget uses the same setup.").font(.caption).foregroundStyle(.secondary)
            }
            Section("About") {
                LabeledContent("Version", value: "0.9.0 (10)")
                Text("Workouts are stored on this device. Export a backup before removing the app.").font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle("Settings")
        .sheet(isPresented: $scheduling) { ScheduleSheet() }
        .fileImporter(isPresented: $csvImporting, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
            do {
                let url = try result.get(); let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                csvResult = try HevyCSVImporter.merge(String(contentsOf: url, encoding: .utf8), into: store.data)
                csvConfirm = true
            } catch { store.error = error.localizedDescription }
        }
        .confirmationDialog("Import Hevy workouts?", isPresented: $csvConfirm, titleVisibility: .visible) {
            Button("Import \(csvResult?.imported ?? 0) workouts") {
                guard let result = csvResult else { return }
                // Re-merge is unnecessary here: do not overwrite a set logged since the preview.
                let existing = Set(store.data.workouts.map(\.id))
                let new = result.data.workouts.filter { !existing.contains($0.id) }
                store.change { data in
                    let ids = Set(data.exercises.map(\.id))
                    data.exercises.append(contentsOf: result.data.exercises.filter { !ids.contains($0.id) })
                    data.workouts.append(contentsOf: new)
                    data.recalculateVolumeRecords()
                }
                csvMessage = "Imported \(new.count) workouts; skipped \(result.skipped) duplicates. CSV times use this device’s time zone."
                csvResult = nil
            }
            Button("Cancel", role: .cancel) { csvResult = nil }
        } message: { Text("Adds history without replacing your routines or active workout. Times use this device’s time zone.") }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get(); let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let bytes = try Data(contentsOf: url)
                _ = try BackupImporter.decode(bytes); pending = bytes; confirmImport = true
            } catch { store.error = error.localizedDescription }
        }
        .confirmationDialog("Replace your current data with this backup?", isPresented: $confirmImport, titleVisibility: .visible) {
            Button("Replace data", role: .destructive) {
                guard let pending else { return }
                do { try store.importBackup(pending) } catch { store.error = error.localizedDescription }
                self.pending = nil
            }
            Button("Cancel", role: .cancel) { pending = nil }
        }
        .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "repbook-native-backup") { result in
            if case .failure(let error) = result { store.error = error.localizedDescription }
        }
    }
    private var workoutPreferences: some View {
        Form {
            Section("Workout") {
                Picker("Weight unit", selection: Binding(get: { store.data.unit }, set: { unit in store.change { $0.convertUnit(to: unit) } })) {
                    Text("Pounds").tag("lbs"); Text("Kilograms").tag("kg")
                }
                Stepper("Rest timer: \(store.data.restSeconds) seconds", value: Binding(get: { store.data.restSeconds }, set: { seconds in store.change { $0.restSeconds = seconds } }), in: 0...600, step: 15)
            }
            Section("Set increments") {
                Picker("Weight", selection: $weightIncrement) {
                    Text("Automatic for unit").tag(0.0)
                    ForEach([0.5, 1, 1.25, 2.5, 5, 10], id: \.self) { Text("\($0.formatted()) \(store.data.unit)").tag($0) }
                }
                Stepper("Reps: \(repIncrement)", value: $repIncrement, in: 1...10)
            }
        }.navigationTitle("Workout & sets").navigationBarTitleDisplayMode(.inline)
    }
    private var feedbackPreferences: some View {
        Form {
            Toggle("Haptics", isOn: $haptics)
            Section {
                Toggle("Live Activity rest alerts", isOn: $restLiveActivityAlerts)
            } footer: {
                Text("Rest completion alerts come from your workout Live Activity. iOS controls Dynamic Island presentation and background delivery.")
            }
        }.navigationTitle("Feedback").navigationBarTitleDisplayMode(.inline)
    }
    private var dataPreferences: some View {
        Form {
            Section("Import") {
                Button("Import Hevy CSV") { csvImporting = true }
                if let csvMessage { Text(csvMessage).font(.caption).foregroundStyle(.secondary) }
                Button("Restore Repbook backup") { importing = true }
                Text("Hevy import adds history and skips matching sessions. Restoring a backup replaces the current data after confirmation.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Export") {
                Button("Export backup") {
                    do { document = BackupDocument(data: try store.exportBackup()); exporting = true }
                    catch { store.error = error.localizedDescription }
                }
            }
        }.navigationTitle("Your data").navigationBarTitleDisplayMode(.inline)
    }

}

struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            SettingsView()
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
