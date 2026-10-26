import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @EnvironmentObject private var store: WorkoutStore
    @State private var selected = 0
    var body: some View {
        TabView(selection: $selected) {
            NavigationStack { WorkoutHome() }.tabItem { Label("Workout", systemImage: "dumbbell.fill") }.tag(0)
            NavigationStack { HistoryView() }.tabItem { Label("History", systemImage: "clock.arrow.circlepath") }.tag(1)
            NavigationStack { SettingsView() }.tabItem { Label("Settings", systemImage: "gearshape") }.tag(2)
        }
        .onOpenURL { _ in selected = 0 }
        .alert("Repbook", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
        } message: { Text(store.error ?? "") }
    }
}

struct WorkoutHome: View {
    @EnvironmentObject private var store: WorkoutStore
    @State private var editor: Routine?
    var body: some View {
        Group {
            if store.data.active != nil { ActiveWorkoutView() }
            else {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Ready when you are.").font(.title2.bold())
                            Text("Choose a routine and make the next set count.").foregroundStyle(.secondary)
                        }.padding(.vertical, 12)
                    }
                    Section("Your routines") {
                        ForEach(store.data.routines) { routine in
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(routine.name).font(.headline)
                                        Text("\(routine.exercises.count) exercises").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button { editor = routine } label: { Image(systemName: "pencil") }.buttonStyle(.borderless).accessibilityLabel("Edit \(routine.name)")
                                    Button("Start") { store.start(routine) }.buttonStyle(.borderedProminent)
                                }
                            }.padding(.vertical, 8)
                        }
                        .onDelete { offsets in store.change { $0.routines.remove(atOffsets: offsets) } }
                    }
                }.navigationTitle("Repbook")
                .toolbar { Button { editor = Routine(name: "New routine") } label: { Image(systemName: "plus") }.accessibilityLabel("New routine") }
            }
        }
        .sheet(item: $editor) { RoutineEditor(draft: $0) }
    }
}

struct ActiveWorkoutView: View {
    @EnvironmentObject private var store: WorkoutStore
    @State private var discard = false
    @State private var finish = false
    @State private var addingExercise = false
    var body: some View {
        if let session = store.data.active {
            List {
                Section {
                    HStack {
                        Label("Elapsed", systemImage: "timer")
                        Spacer()
                        Text(session.started, style: .timer).monospacedDigit()
                    }
                    if let end = session.restUntil {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            HStack {
                                Text(end > context.date ? "Rest" : "Ready for your next set")
                                Spacer()
                                if end > context.date { Text(timerInterval: context.date...end, countsDown: true).monospacedDigit() }
                                Button("Skip") { store.change { $0.active?.restUntil = nil } }.buttonStyle(.borderless)
                            }.foregroundStyle(.orange)
                        }
                    }
                    Text("\(session.completedSets) sets logged · \(session.volume.formatted(.number.precision(.fractionLength(0)))) \(store.data.unit) volume")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(Array(session.exercises.enumerated()), id: \.element.id) { ei, exercise in
                    Section {
                        HStack {
                            Text("Set").frame(width: 40)
                            Text(store.data.unit).frame(maxWidth: .infinity)
                            Text("Reps").frame(maxWidth: .infinity)
                            Text("Log").frame(width: 40)
                        }.font(.caption).foregroundStyle(.secondary)
                        ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { si, set in
                            HStack(spacing: 10) {
                                Text(set.warmup ? "W" : "\(exercise.sets.prefix(si + 1).filter { !$0.warmup }.count)")
                                    .font(.subheadline.bold()).foregroundStyle(set.warmup ? .secondary : .primary).frame(width: 32)
                                TextField("Weight", value: setBinding(ei, si, \.weight), format: .number)
                                    .keyboardType(.decimalPad).multilineTextAlignment(.center).textFieldStyle(.roundedBorder)
                                    .accessibilityLabel("\(store.name(exercise.exerciseID)) set \(si + 1) weight")
                                TextField("Reps", value: setBinding(ei, si, \.reps), format: .number)
                                    .keyboardType(.numberPad).multilineTextAlignment(.center).textFieldStyle(.roundedBorder)
                                    .accessibilityLabel("\(store.name(exercise.exerciseID)) set \(si + 1) reps")
                                Button { store.toggleSet(exercise: ei, set: si) } label: {
                                    Image(systemName: set.done ? "checkmark.circle.fill" : "circle").font(.title2)
                                        .foregroundStyle(set.done ? .green : .secondary)
                                }.buttonStyle(.borderless).accessibilityLabel(set.done ? "Unlog set \(si + 1)" : "Log set \(si + 1)")
                            }.listRowBackground(set.done ? Color.green.opacity(0.12) : Color(uiColor: .secondarySystemGroupedBackground))
                            .swipeActions { Button("Delete", role: .destructive) { store.change { $0.active?.exercises[ei].sets.remove(at: si) } } }
                        }
                        Button("Add set", systemImage: "plus") {
                            store.change { data in
                                var set = data.active!.exercises[ei].sets.last(where: { !$0.warmup }) ?? WorkoutSet()
                                set.id = UUID().uuidString; set.done = false; set.warmup = false
                                data.active!.exercises[ei].sets.append(set)
                            }
                        }
                    } header: { Text(store.name(exercise.exerciseID)) }
                }
                Section { Button("Add exercise", systemImage: "plus") { addingExercise = true } }
                Section { Button("Discard workout", role: .destructive) { discard = true } }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(session.name).navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Finish") { finish = true }.fontWeight(.bold) }
            .confirmationDialog("Finish and save this workout?", isPresented: $finish, titleVisibility: .visible) {
                Button("Save workout") { store.finish() }
            } message: { Text("Only logged sets will be saved.") }
            .confirmationDialog("Discard this workout?", isPresented: $discard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) { store.change { $0.active = nil } }
            }
            .sheet(isPresented: $addingExercise) {
                ExercisePicker { exercise in
                    store.change { $0.active?.exercises.append(SessionExercise(exerciseID: exercise.id, sets: [WorkoutSet()])) }
                    addingExercise = false
                }
            }
        }
    }
    private func setBinding<T>(_ ei: Int, _ si: Int, _ key: WritableKeyPath<WorkoutSet, T>) -> Binding<T> {
        Binding(get: { store.data.active!.exercises[ei].sets[si][keyPath: key] },
                set: { value in store.change { $0.active!.exercises[ei].sets[si][keyPath: key] = value } })
    }
}

struct RoutineEditor: View {
    @EnvironmentObject private var store: WorkoutStore
    @Environment(\.dismiss) private var dismiss
    @State var draft: Routine
    @State private var adding = false
    @State private var reordering = false
    var body: some View {
        NavigationStack {
            List {
                Section { TextField("Routine name", text: $draft.name) }
                Section {
                    ForEach($draft.exercises) { $item in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(store.name(item.exerciseID)).font(.headline)
                            if !reordering {
                                Stepper("Warmup sets: \(item.warmupCount)", value: $item.warmupCount, in: 0...2)
                                ForEach($item.sets) { $set in
                                    HStack {
                                        TextField(store.data.unit, value: $set.weight, format: .number).keyboardType(.decimalPad)
                                            .accessibilityLabel("Template weight")
                                        TextField("Reps", value: $set.reps, format: .number).keyboardType(.numberPad)
                                            .accessibilityLabel("Template reps")
                                        Button(role: .destructive) { item.sets.removeAll { $0.id == set.id } } label: { Image(systemName: "minus.circle") }
                                            .buttonStyle(.borderless).disabled(item.sets.count <= 1).accessibilityLabel("Remove set")
                                    }.textFieldStyle(.roundedBorder)
                                }
                                Button("Add set", systemImage: "plus") {
                                    var set = item.sets.last ?? WorkoutSet(); set.id = UUID().uuidString; item.sets.append(set)
                                }.buttonStyle(.borderless)
                            }
                        }.padding(.vertical, 6)
                    }
                    .onMove { draft.exercises.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { draft.exercises.remove(atOffsets: $0) }
                } header: { Text(reordering ? "Drag handles to reorder" : "Exercises") }
                if !reordering { Button("Add exercise", systemImage: "plus") { adding = true } }
            }
            .environment(\.editMode, .constant(reordering ? .active : .inactive))
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Edit routine").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { Button(reordering ? "Done" : "Reorder") { withAnimation { reordering.toggle() } } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let value = draft
                        store.change { data in
                            if let index = data.routines.firstIndex(where: { $0.id == value.id }) { data.routines[index] = value }
                            else { data.routines.append(value) }
                        }
                        if store.error == nil { dismiss() }
                    }.disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty || draft.exercises.isEmpty)
                }
            }
            .sheet(isPresented: $adding) {
                ExercisePicker(excluded: Set(draft.exercises.map(\.exerciseID))) { exercise in
                    draft.exercises.append(RoutineExercise(exerciseID: exercise.id)); adding = false
                }
            }
        }
    }
}

struct ExercisePicker: View {
    @EnvironmentObject private var store: WorkoutStore
    @Environment(\.dismiss) private var dismiss
    var excluded: Set<String> = []
    var onSelect: (Exercise) -> Void
    @State private var query = ""
    var body: some View {
        NavigationStack {
            List {
                ForEach(store.data.exercises.filter { !excluded.contains($0.id) && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)) }) { exercise in
                    Button(exercise.name) { onSelect(exercise) }
                }
                if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button("Create \(query)", systemImage: "plus") {
                        let exercise = Exercise(name: query.trimmingCharacters(in: .whitespaces))
                        store.change { $0.exercises.append(exercise) }
                        if store.error == nil { onSelect(exercise) }
                    }
                }
            }.searchable(text: $query).navigationTitle("Add exercise")
                .toolbar { Button("Cancel") { dismiss() } }
        }
    }
}

struct HistoryView: View {
    @EnvironmentObject private var store: WorkoutStore
    var body: some View {
        List {
            if store.data.workouts.isEmpty {
                ContentUnavailableView("Your first workout starts here", systemImage: "dumbbell", description: Text("Finished workouts will appear here."))
            }
            ForEach(store.data.workouts.sorted { $0.started > $1.started }) { session in
                NavigationLink {
                    List {
                        Section {
                            Text(session.started.formatted(date: .abbreviated, time: .shortened))
                            Text("\(session.completedSets) sets · \(session.volume.formatted()) \(store.data.unit)")
                        }
                        ForEach(session.exercises) { exercise in
                            Section(store.name(exercise.exerciseID)) {
                                ForEach(exercise.sets) { set in
                                    HStack {
                                        Text(set.warmup ? "Warmup" : "Set").foregroundStyle(.secondary)
                                        Spacer()
                                        Text("\(set.weight.formatted()) \(store.data.unit) × \(set.reps)")
                                    }
                                }
                            }
                        }
                    }.navigationTitle(session.name)
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(session.name).font(.headline)
                        Text(session.started.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                        Text("\(session.completedSets) sets · \(session.volume.formatted()) \(store.data.unit)").font(.caption)
                    }.padding(.vertical, 6)
                }
            }
        }.navigationTitle("History")
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
    var body: some View {
        Form {
            Section("Workout") {
                Picker("Weight unit", selection: Binding(get: { store.data.unit }, set: { unit in store.change { $0.convertUnit(to: unit) } })) {
                    Text("Pounds").tag("lbs"); Text("Kilograms").tag("kg")
                }
                Stepper("Rest timer: \(store.data.restSeconds) seconds", value: Binding(get: { store.data.restSeconds }, set: { value in store.change { $0.restSeconds = value } }), in: 0...600, step: 15)
            }
            Section("Your data") {
                Button("Import Repbook backup") { importing = true }
                Button("Export backup") {
                    do { document = BackupDocument(data: try store.exportBackup()); exporting = true }
                    catch { store.error = error.localizedDescription }
                }
                Text("To move your web workouts here, export JSON from the web app, then import that file. Import replaces the data in this app.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Lock Screen & Home Screen") {
                Text("Start a workout to show a Live Activity. Use its buttons to adjust weight or reps and log the current set.")
                Text("Add the Repbook widget from your Home Screen to open your routines quickly.").font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle("Settings")
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
}
