import SwiftUI

struct ExercisePicker: View {
    @EnvironmentObject private var store: WorkoutStore
    @Environment(\.dismiss) private var dismiss
    var excluded: Set<String> = []
    var onSelect: (Exercise) -> Void
    @State private var query = ""
    @State private var group = "All muscles"
    @State private var details: Exercise?
    private var matches: [Exercise] {
        store.data.exercises.filter {
            !excluded.contains($0.id) && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)) && (group == "All muscles" || $0.primaryMuscle == group)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    private var recent: [Exercise] {
        var ids: [String] = []
        for workout in store.data.workouts.sorted(by: { $0.started > $1.started }) {
            for exercise in workout.exercises where !ids.contains(exercise.exerciseID) { ids.append(exercise.exerciseID) }
        }
        return ids.prefix(5).compactMap { id in matches.first { $0.id == id } }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Muscle group", selection: $group) {
                        Text("All muscles").tag("All muscles")
                        ForEach(Exercise.muscleGroups + ["Unassigned"], id: \.self) { Text($0).tag($0) }
                    }.tint(.blue)
                }
                if query.isEmpty && !recent.isEmpty { Section("Recent") { ForEach(recent) { exerciseRow($0) } } }
                Section("Exercise catalog") { ForEach(matches) { exerciseRow($0) } }
                if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !store.data.exercises.contains(where: { $0.name.compare(query.trimmingCharacters(in: .whitespacesAndNewlines), options: .caseInsensitive) == .orderedSame }) {
                    Button("Create \(query)", systemImage: "plus") {
                        let exercise = Exercise(name: query.trimmingCharacters(in: .whitespacesAndNewlines), muscleGroup: group == "All muscles" || group == "Unassigned" ? nil : group)
                        store.change { $0.exercises.append(exercise) }
                        if store.error == nil { onSelect(exercise) }
                    }
                }
            }.searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search exercises")
                .navigationTitle("Add exercise").toolbar { Button("Cancel") { dismiss() } }
                .sheet(item: $details) { ExerciseInfoSheet(exercise: $0) }
        }.presentationDetents([.large]).presentationDragIndicator(.visible)
    }
    private func exerciseRow(_ exercise: Exercise) -> some View {
        HStack {
            Button { onSelect(exercise) } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(exercise.name).font(.headline).foregroundStyle(.primary)
                    Text(exercise.primaryMuscle).font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, minHeight: 52, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
                .contextMenu { Button("Exercise details", systemImage: "info.circle") { details = exercise } }
            Button { details = exercise } label: { Image(systemName: "info.circle").frame(width: 44, height: 44) }.buttonStyle(.borderless).accessibilityLabel("Details for \(exercise.name)")
        }
    }
}

struct ExerciseInfoSheet: View {
    @EnvironmentObject private var store: WorkoutStore
    @Environment(\.dismiss) private var dismiss
    let exercise: Exercise
    var body: some View {
        NavigationStack {
            Form {
                Section { Text(exercise.name).font(.title2.weight(.semibold)) }
                Section {
                    Picker("Primary muscle", selection: Binding(get: { store.data.exercises.first { $0.id == exercise.id }?.primaryMuscle ?? "Unassigned" }, set: { group in
                        store.change { if let i = $0.exercises.firstIndex(where: { $0.id == exercise.id }) { $0.exercises[i].muscleGroup = group } }
                    })) {
                        ForEach(Exercise.muscleGroups + ["Unassigned"], id: \.self) { Text($0).tag($0) }
                    }
                } footer: { Text("Used to group working sets in your weekly volume chart.") }
                NavigationLink("View progression") { ExerciseProgressDetail(exercise: exercise) }
            }.navigationTitle("Exercise details").navigationBarTitleDisplayMode(.inline).toolbar { Button("Done") { dismiss() } }
        }
    }
}
