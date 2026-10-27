import SwiftUI
import UIKit

struct HistoryView: View {
    @EnvironmentObject private var store: WorkoutStore
    @State private var month = Calendar.current.startOfDay(for: .now)
    @State private var selectedDay: Date?
    @State private var query = ""
    private var visible: [Session] {
        store.data.workouts.filter { session in
            (query.isEmpty || session.name.localizedCaseInsensitiveContains(query)) &&
            (selectedDay == nil || Calendar.current.isDate(session.started, inSameDayAs: selectedDay!))
        }.sorted { $0.started > $1.started }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                calendar.repbookCard()
                HStack {
                    Text(selectedDay == nil ? "Recent workouts" : selectedDay!.formatted(.dateTime.month(.abbreviated).day())).font(.title3.weight(.semibold))
                    Spacer()
                    if selectedDay != nil { Button("Show all") { selectedDay = nil }.frame(minHeight: 44) }
                }
                if visible.isEmpty {
                    ContentUnavailableView("No workouts here yet", systemImage: "calendar", description: Text("Your saved sessions will appear here."))
                }
                ForEach(visible) { session in
                    NavigationLink { SessionDetailView(sessionID: session.id) } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack { Text(session.name).font(.title3.weight(.semibold)); Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }
                            Text("\(session.started.formatted(.dateTime.month(.abbreviated).day())) · \(duration(session)) · \(session.exercises.count) exercises")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Text("\(session.completedSets) sets · \(session.volume.formatted(.number.precision(.fractionLength(0)))) \(store.data.unit)").font(.subheadline)
                            let records = session.exercises.flatMap(\.sets).filter { $0.done && $0.volumePR == true }.count
                            if records > 0 { Label("\(records) volume PR\(records == 1 ? "" : "s")", systemImage: "medal.fill").font(.caption).foregroundStyle(.green) }
                        }.repbookCard()
                    }.buttonStyle(.plain)
                }
            }.padding(20)
        }.background(Color(uiColor: .systemBackground)).navigationTitle("History")
            .searchable(text: $query, prompt: "Find a workout")
    }
    private func duration(_ session: Session) -> String {
        guard let end = session.ended else { return "Duration unavailable" }
        let minutes = Int(end.timeIntervalSince(session.started) / 60)
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
    private var calendar: some View {
        VStack(spacing: 12) {
            HStack {
                Text(month.formatted(.dateTime.month(.wide).year())).font(.title3.weight(.semibold))
                Spacer()
                Button { changeMonth(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.accessibilityLabel("Previous month")
                Button { changeMonth(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.accessibilityLabel("Next month")
            }
            HStack(spacing: 0) {
                ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, day in
                    Text(day).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 2) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    if let day {
                        Button { selectedDay = selectedDay.map { Calendar.current.isDate($0, inSameDayAs: day) } == true ? nil : day } label: {
                            VStack(spacing: 3) {
                                Text(day.formatted(.dateTime.day())).font(.subheadline.weight(Calendar.current.isDateInToday(day) ? .bold : .regular))
                                Circle().fill(store.data.workouts.contains { Calendar.current.isDate($0.started, inSameDayAs: day) } ? Color.green : .clear).frame(width: 4, height: 4)
                            }.frame(maxWidth: .infinity, minHeight: 44)
                                .background(selectedDay.map { Calendar.current.isDate($0, inSameDayAs: day) } == true ? Color.blue.opacity(0.18) : (store.data.workouts.contains { Calendar.current.isDate($0.started, inSameDayAs: day) } ? Color.green.opacity(0.12) : .clear), in: Circle())
                        }.buttonStyle(.plain).accessibilityLabel(day.formatted(date: .complete, time: .omitted))
                    } else { Color.clear.frame(height: 44).accessibilityHidden(true) }
                }
            }
        }
    }
    private var days: [Date?] {
        let cal = Calendar.current
        guard let first = cal.dateInterval(of: .month, for: month)?.start,
              let range = cal.range(of: .day, in: .month, for: month) else { return [] }
        let offset = (cal.component(.weekday, from: first) + 5) % 7
        return Array(repeating: nil, count: offset) + range.map { cal.date(byAdding: .day, value: $0 - 1, to: first) }
    }
    private func changeMonth(_ delta: Int) {
        if let first = Calendar.current.dateInterval(of: .month, for: month)?.start,
           let date = Calendar.current.date(byAdding: .month, value: delta, to: first) { month = date; selectedDay = nil }
    }
}

struct SessionDetailView: View {
    @EnvironmentObject private var store: WorkoutStore
    @Environment(\.dismiss) private var dismiss
    var sessionID: String
    @State private var editing = false
    @State private var deleting = false
    @State private var routine: Routine?
    private var session: Session? { store.data.workouts.first { $0.id == sessionID } }
    var body: some View {
        Group {
            if let session {
                List {
                    Section {
                        Text(session.started.formatted(date: .complete, time: .shortened)).font(.subheadline).foregroundStyle(.secondary)
                        HStack {
                            SummaryTile(title: "Sets", value: "\(session.completedSets)", icon: "checkmark")
                            SummaryTile(title: store.data.unit + " volume", value: session.volume.formatted(.number.precision(.fractionLength(0))), icon: "dumbbell")
                        }
                        if let end = session.ended { Label("\(Int(end.timeIntervalSince(session.started) / 60)) minutes", systemImage: "timer") }
                        if let notes = session.notes, !notes.isEmpty { Text(notes) }
                    }
                    ForEach(session.exercises) { exercise in
                        Section(store.name(exercise.exerciseID)) {
                            if let notes = exercise.notes, !notes.isEmpty { Text(notes).font(.subheadline).foregroundStyle(.secondary) }
                            ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                                HStack {
                                    Text(set.warmup ? "W" : "\(exercise.sets.prefix(index + 1).filter { !$0.warmup }.count)").foregroundStyle(.secondary).frame(width: 28)
                                    Text("\(set.weight.formatted()) \(store.data.unit) × \(set.reps)").monospacedDigit()
                                    Spacer()
                                    if set.volumePR == true { Label("Volume PR", systemImage: "medal.fill").font(.caption).foregroundStyle(.green) }
                                }.frame(minHeight: 44)
                            }
                        }
                    }
                    Section {
                        Button("Edit workout", systemImage: "pencil") { editing = true }
                        Button("Save as routine", systemImage: "square.stack") {
                            routine = Routine(name: session.name, exercises: session.exercises.compactMap { exercise in
                                let sets = exercise.sets.filter { !$0.warmup }.map { set -> WorkoutSet in
                                    var copy = set; copy.id = UUID().uuidString; copy.done = false; copy.volumePR = nil; copy.weightPR = nil; return copy
                                }
                                guard !sets.isEmpty else { return nil }
                                return RoutineExercise(exerciseID: exercise.exerciseID, warmupCount: exercise.sets.filter(\.warmup).count,
                                                       restSeconds: exercise.restSeconds, notes: exercise.notes, sets: sets)
                            })
                        }
                        Button("Delete workout", systemImage: "trash", role: .destructive) { deleting = true }
                    }
                }.navigationTitle(session.name)
            } else { ContentUnavailableView("Workout unavailable", systemImage: "dumbbell") }
        }
        .sheet(isPresented: $editing) { if let session { HistoricalSessionEditor(draft: session) } }
        .sheet(item: $routine) { RoutineEditor(draft: $0) }
        .confirmationDialog("Delete this workout permanently?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete workout", role: .destructive) { store.change { $0.workouts.removeAll { $0.id == sessionID }; $0.recalculateVolumeRecords() }; dismiss() }
        }
    }
}

struct HistoricalSessionEditor: View {
    @EnvironmentObject private var store: WorkoutStore
    @Environment(\.dismiss) private var dismiss
    @State var draft: Session
    var body: some View {
        NavigationStack {
            Form {
                Section("Session") {
                    TextField("Workout name", text: $draft.name)
                    DatePicker("Started", selection: $draft.started)
                    if draft.ended != nil {
                        DatePicker("Ended", selection: Binding(get: { draft.ended ?? draft.started }, set: { draft.ended = $0 }), in: draft.started...)
                    }
                    TextField("Notes", text: Binding(get: { draft.notes ?? "" }, set: { draft.notes = $0 }), axis: .vertical)
                }
                ForEach($draft.exercises) { $exercise in
                    Section(store.name(exercise.exerciseID)) {
                        ForEach($exercise.sets) { $set in
                            HStack {
                                Text(set.warmup ? "W" : "Set").foregroundStyle(.secondary)
                                TextField("Weight", value: $set.weight, format: .number).keyboardType(.decimalPad)
                                TextField("Reps", value: $set.reps, format: .number).keyboardType(.numberPad)
                            }
                        }
                    }
                }
            }.navigationTitle("Edit workout").navigationBarTitleDisplayMode(.inline).scrollDismissesKeyboard(.interactively)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            let value = draft
                            store.change { if let i = $0.workouts.firstIndex(where: { $0.id == value.id }) { $0.workouts[i] = value; $0.recalculateVolumeRecords() } }
                            if store.error == nil { dismiss() }
                        }.disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (draft.ended.map { $0 < draft.started } ?? false))
                    }
                    ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) } }
                }
        }
    }
}
