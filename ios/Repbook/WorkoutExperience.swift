import SwiftUI

struct ActiveWorkoutView: View {
    @EnvironmentObject private var store: WorkoutStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded: String?
    @State private var adding = false
    @State private var settings = false
    @State private var editingSession = false
    @State private var discard = false
    @State private var numeric: NumericTarget?
    @State private var restExpanded = false
    var onMinimize: () -> Void = {}

    var body: some View {
        Group {
            if let session = store.data.active {
                ScrollViewReader { scroll in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text("\(session.completedSets) / \(session.exercises.flatMap(\.sets).count) sets").font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("\(session.volume.formatted(.number.precision(.fractionLength(0)))) \(store.data.unit)").foregroundStyle(.secondary)
                            }
                            ProgressView(value: Double(session.completedSets), total: Double(max(1, session.exercises.flatMap(\.sets).count)))
                            if session.nextSet == nil && session.restUntil != nil { RestTimerCard(expanded: $restExpanded) }
                            ForEach(Array(session.exercises.enumerated()), id: \.element.id) { ei, exercise in
                                VStack(spacing: 12) {
                                    exerciseCard(session, exercise, ei)
                                    if session.nextSet?.exercise == ei && session.restUntil != nil { RestTimerCard(expanded: $restExpanded) }
                                }.id(exercise.id)
                            }
                            Button { adding = true } label: {
                                Label("Add exercise", systemImage: "plus").frame(maxWidth: .infinity, minHeight: 56)
                            }.buttonStyle(.bordered).clipShape(Capsule())
                        }.padding(20)
                    }.background(Color(uiColor: .systemBackground))
                    .navigationTitle("Your workout").navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button(action: onMinimize) { Image(systemName: "chevron.down").frame(width: 44, height: 44) }.accessibilityLabel("Minimize workout")
                        }
                        ToolbarItem(placement: .principal) {
                            VStack(spacing: 2) {
                                Text(session.name).font(.caption).lineLimit(1)
                                Text(session.started, style: .timer).font(.subheadline.weight(.semibold)).monospacedDigit()
                            }
                        }
                    }
                    .safeAreaInset(edge: .top, spacing: 0) {
                        HStack {
                            Text("Your workout").font(.title2.weight(.semibold))
                            Spacer()
                            workoutControls
                        }.padding(.horizontal, 20).padding(.vertical, 8)
                            .background(Color(uiColor: .systemBackground))
                    }
                    .onAppear { focusCurrent(session, scroll) }
                    .onChange(of: store.currentSetNavigation) { _, _ in focusCurrent(session, scroll) }
                    .onChange(of: session.nextSet.map { session.exercises[$0.exercise].id }) { _, id in
                        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85)) { expanded = id }
                    }
                }
            }
        }
        .confirmationDialog("Discard this workout?", isPresented: $discard, titleVisibility: .visible) {
            Button("Discard workout", role: .destructive) { store.change { $0.active = nil }; onMinimize() }
        }
        .sheet(isPresented: $settings) { SettingsSheet() }
        .sheet(isPresented: $editingSession) { SessionSettingsSheet() }
        .sheet(isPresented: $adding) {
            ExercisePicker { exercise in
                store.change { $0.active?.exercises.append(SessionExercise(exerciseID: exercise.id, sets: [WorkoutSet()])) }
                adding = false
            }
        }
        .sheet(item: $numeric) { target in NumericEntrySheet(target: target) }
    }

    private var workoutControls: some View {
        Menu {
            Button("Finish workout", systemImage: "checkmark.circle") { store.finish() }
            Button("Edit current session", systemImage: "pencil") { editingSession = true }
            Button("Workout settings", systemImage: "gearshape") { settings = true }
            Button("Discard workout", systemImage: "trash", role: .destructive) { discard = true }
        } label: {
            Image(systemName: "ellipsis").font(.headline).frame(width: 52, height: 52)
                .background(Color(uiColor: .tertiarySystemFill), in: Circle())
                .contentShape(Circle())
        }
        .accessibilityLabel("Workout controls")
        .accessibilityIdentifier("workout-controls")
    }

    private func focusCurrent(_ session: Session, _ scroll: ScrollViewProxy) {
        guard let next = session.nextSet else { return }
        expanded = session.exercises[next.exercise].id
        DispatchQueue.main.async { scroll.scrollTo(session.exercises[next.exercise].id, anchor: .top) }
        store.showLiveActivity()
    }

    private func exerciseCard(_ session: Session, _ exercise: SessionExercise, _ ei: Int) -> some View {
        let isExpanded = expanded == exercise.id
        let next = session.nextSet
        let currentIndex = next?.exercise == ei ? next?.set : nil
        return VStack(alignment: .leading, spacing: 16) {
            Button {
                if !isExpanded, next?.exercise != ei,
                   let set = exercise.sets.first(where: { !$0.done }) {
                    store.change { $0.active?.focusedSetID = set.id }
                }
                withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85)) { expanded = isExpanded ? nil : exercise.id }
            } label: {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("EXERCISE \(ei + 1) OF \(session.exercises.count)").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        ExerciseHeading(name: store.name(exercise.exerciseID)).foregroundStyle(.primary).multilineTextAlignment(.leading)
                        Text("\(exercise.sets.filter(\.done).count) / \(exercise.sets.count) sets").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down").foregroundStyle(.secondary).frame(minWidth: 44, minHeight: 44)
                }
            }.buttonStyle(.plain)
            if isExpanded {
                if let notes = exercise.notes, !notes.isEmpty { Text(notes).font(.subheadline).foregroundStyle(.secondary) }
                ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { si, set in
                    if si == currentIndex && !set.done {
                        currentSet(session, exercise, ei, si, set)
                    } else {
                        HStack {
                            Text(set.warmup ? "W" : "\(exercise.sets.prefix(si + 1).filter { !$0.warmup }.count)")
                                .font(.subheadline.weight(.semibold)).frame(width: 28).foregroundStyle(set.warmup ? .secondary : .primary)
                            Button { numeric = NumericTarget(sessionID: session.id, setID: set.id, kind: .weight) } label: {
                                Text("\(set.weight.formatted()) \(store.data.unit)").frame(minHeight: 44)
                            }.buttonStyle(.plain).accessibilityLabel("Edit weight")
                            Text("×").foregroundStyle(.secondary)
                            Button { numeric = NumericTarget(sessionID: session.id, setID: set.id, kind: .reps) } label: {
                                Text("\(set.reps) reps").frame(minHeight: 44)
                            }.buttonStyle(.plain).accessibilityLabel("Edit reps")
                            Spacer(minLength: 0)
                            if set.done && set.volumePR == true { Image(systemName: "medal.fill").foregroundStyle(.green).accessibilityLabel("Volume PR") }
                            Menu {
                                if set.done {
                                    Button("Unlog set", systemImage: "arrow.uturn.backward") { store.toggleSet(exercise: ei, set: si) }
                                } else {
                                    Button("Make current set", systemImage: "scope") { store.change { $0.active?.focusedSetID = set.id } }
                                    Button("Log set", systemImage: "checkmark") { log(session.id, set.id) }
                                }
                                Button("Delete set", systemImage: "trash", role: .destructive) {
                                    store.change { $0.active?.exercises[ei].sets.removeAll { $0.id == set.id } }
                                }
                            } label: {
                                Image(systemName: set.done ? "checkmark.circle.fill" : "ellipsis.circle")
                                    .foregroundStyle(set.done ? .green : .secondary).frame(width: 44, height: 44)
                            }.accessibilityLabel("Set actions")
                        }.font(.subheadline)
                    }
                }
                Button("Add set", systemImage: "plus") {
                    store.change { data in
                        var set = data.active!.exercises[ei].sets.last(where: { !$0.warmup }) ?? WorkoutSet()
                        set.id = UUID().uuidString; set.done = false; set.warmup = false; set.weightPR = nil; set.volumePR = nil
                        data.active!.exercises[ei].sets.append(set)
                    }
                }.frame(minHeight: 44)
            }
        }.repbookCard()
    }

    private func currentSet(_ session: Session, _ exercise: SessionExercise, _ ei: Int, _ si: Int, _ set: WorkoutSet) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(set.warmup ? "WARMUP" : "CURRENT SET", systemImage: "smallcircle.filled.circle").font(.caption.weight(.semibold)).foregroundStyle(.blue)
            if let previous = previousSet(exercise.exerciseID, index: exercise.sets.prefix(si).filter { !$0.warmup }.count) {
                HStack {
                    Text("PREVIOUS").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(previous.weight.formatted()) \(store.data.unit) × \(previous.reps) reps").font(.subheadline)
                }
                Divider()
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { numberControl(session, set, .weight); numberControl(session, set, .reps) }
                VStack(spacing: 12) { numberControl(session, set, .weight); numberControl(session, set, .reps) }
            }
            Button { log(session.id, set.id) } label: {
                Label("Log set", systemImage: "checkmark").frame(maxWidth: .infinity)
            }.buttonStyle(RepbookPrimaryStyle())

        }.padding(.vertical, 8)
    }

    private func previousSet(_ exerciseID: String, index: Int) -> WorkoutSet? {
        let sets = store.data.workouts.sorted { $0.started > $1.started }
            .compactMap { $0.exercises.first { $0.exerciseID == exerciseID } }.first?.sets.filter { $0.done && !$0.warmup } ?? []
        return sets.indices.contains(index) ? sets[index] : sets.first
    }

    private func numberControl(_ session: Session, _ set: WorkoutSet, _ kind: NumericTarget.Kind) -> some View {
        VStack(spacing: 8) {
            Text(kind == .weight ? "WEIGHT (\(store.data.unit.uppercased()))" : "REPS").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Button { numeric = NumericTarget(sessionID: session.id, setID: set.id, kind: kind) } label: {
                Text(kind == .weight ? set.weight.formatted() : "\(set.reps)")
                    .font(.system(size: 42, weight: .semibold, design: .rounded)).monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: 60).contentTransition(.identity)
            }.buttonStyle(.plain).accessibilityLabel(kind == .weight ? "Edit weight" : "Edit reps")
            HStack {
                adjustButton(session, set, kind, -1)
                Spacer(minLength: 8)
                adjustButton(session, set, kind, 1)
            }
        }.padding(.vertical, 12).frame(minWidth: 130, maxWidth: .infinity)
    }

    private func adjustButton(_ session: Session, _ set: WorkoutSet, _ kind: NumericTarget.Kind, _ direction: Int) -> some View {
        Button {
            guard let active = store.data.active, active.id == session.id,
                  let ei = active.exercises.firstIndex(where: { $0.sets.contains { $0.id == set.id } }),
                  let si = active.exercises[ei].sets.firstIndex(where: { $0.id == set.id }) else { return }
            store.change {
                if kind == .weight {
                    let step = UserDefaults.standard.double(forKey: "weightIncrement")
                    $0.active!.exercises[ei].sets[si].weight = max(0, active.exercises[ei].sets[si].weight + Double(direction) * (step > 0 ? step : ($0.unit == "kg" ? 2.5 : 5)))
                } else {
                    let step = max(1, UserDefaults.standard.integer(forKey: "repIncrement"))
                    $0.active!.exercises[ei].sets[si].reps = min(999, max(1, active.exercises[ei].sets[si].reps + direction * step))
                }
            }
        } label: { Image(systemName: direction < 0 ? "minus" : "plus").font(.headline).frame(width: 48, height: 44) }
            .buttonStyle(.plain).background(Color(uiColor: .tertiarySystemFill), in: Circle()).accessibilityLabel("\(direction < 0 ? "Decrease" : "Increase") \(kind == .weight ? "weight" : "reps")")
    }

    private func log(_ sessionID: String, _ setID: String) {
        // Capture both IDs before dispatch so repeated taps on the same button are idempotent.
        guard let session = store.data.active, session.id == sessionID,
              let ei = session.exercises.firstIndex(where: { $0.sets.contains { $0.id == setID && !$0.done } }),
              let si = session.exercises[ei].sets.firstIndex(where: { $0.id == setID && !$0.done }) else { return }
        withAnimation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.9)) { store.toggleSet(exercise: ei, set: si) }
    }
}

struct RestTimerCard: View {
    @EnvironmentObject private var store: WorkoutStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var expanded: Bool
    var body: some View {
        if let end = store.data.active?.restUntil {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(spacing: 16) {
                    Button { withAnimation(reduceMotion ? nil : .snappy) { expanded.toggle() } } label: {
                        HStack {
                            Image(systemName: end > context.date ? "timer" : "checkmark.circle.fill").foregroundStyle(end > context.date ? Color.primary : Color.green)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(end <= context.date ? "Rest complete" : (expanded ? "RESTING" : "Rest timer")).font(expanded ? .caption : .headline).foregroundStyle(end <= context.date ? Color.green : Color.primary)
                                if !expanded {
                                    Text(timerInterval: min(context.date, end)...end, countsDown: true).font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: expanded ? "chevron.up" : "plus").frame(width: 44, height: 44)
                        }.frame(minHeight: 44)
                    }.buttonStyle(.plain)
                    if expanded {
                        Text(timerInterval: min(context.date, end)...end, countsDown: true)
                            .font(.system(size: 36, weight: .semibold, design: .rounded)).monospacedDigit().frame(maxWidth: .infinity)
                        HStack(spacing: 8) {
                            Button("−15 sec") { store.adjustRest(-15) }.frame(maxWidth: .infinity, minHeight: 48).background(Color(uiColor: .tertiarySystemFill), in: Capsule())
                            Button("Skip") { store.change { $0.active?.restUntil = nil }; store.cancelLegacyRestNotifications() }
                                .frame(maxWidth: .infinity).buttonStyle(RepbookPrimaryStyle())
                            Button("+15 sec") { store.adjustRest(15) }.frame(maxWidth: .infinity, minHeight: 48).background(Color(uiColor: .tertiarySystemFill), in: Capsule())
                        }.font(.subheadline.weight(.semibold)).buttonStyle(.plain)
                    }
                }
            }.repbookCard()
        }
    }
}

struct NumericTarget: Identifiable {
    enum Kind { case weight, reps }
    var sessionID: String
    var setID: String
    var kind: Kind
    var id: String { setID + (kind == .weight ? "weight" : "reps") }
}

struct NumericEntrySheet: View {
    @EnvironmentObject private var store: WorkoutStore
    @Environment(\.dismiss) private var dismiss
    let target: NumericTarget
    @State private var value = ""
    @FocusState private var focused: Bool
    private var valid: Double? {
        guard let number = Double(value.replacingOccurrences(of: ",", with: ".")), number.isFinite, number >= 0 else { return nil }
        if target.kind == .reps && (number < 1 || number > 999 || number.rounded() != number) { return nil }
        return number
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                TextField(target.kind == .weight ? "Weight" : "Reps", text: $value)
                    .font(.system(size: 56, weight: .semibold, design: .rounded)).multilineTextAlignment(.center)
                    .keyboardType(target.kind == .weight ? .decimalPad : .numberPad).focused($focused)
                if !value.isEmpty && valid == nil {
                    Label(target.kind == .weight ? "Enter a valid, nonnegative weight." : "Enter a whole number from 1 to 999.", systemImage: "exclamationmark.circle")
                        .font(.subheadline).foregroundStyle(.red)
                }
                Button("Save") {
                    guard let valid, let session = store.data.active, session.id == target.sessionID,
                          let ei = session.exercises.firstIndex(where: { $0.sets.contains { $0.id == target.setID } }),
                          let si = session.exercises[ei].sets.firstIndex(where: { $0.id == target.setID }) else { dismiss(); return }
                    store.change {
                        if target.kind == .weight { $0.active!.exercises[ei].sets[si].weight = valid }
                        else { $0.active!.exercises[ei].sets[si].reps = Int(valid) }
                    }
                    dismiss()
                }.buttonStyle(RepbookPrimaryStyle()).disabled(valid == nil)
            }.padding(20).navigationTitle(target.kind == .weight ? "Weight (\(store.data.unit))" : "Reps").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                .onAppear {
                    let set = store.data.active?.exercises.flatMap(\.sets).first { $0.id == target.setID }
                    value = target.kind == .weight ? (set?.weight.formatted(.number.grouping(.never)) ?? "0") : "\(set?.reps ?? 8)"
                    focused = true
                }
        }.presentationDetents([.medium]).presentationDragIndicator(.visible)
    }
}

struct WorkoutSummary: View {
    @EnvironmentObject private var store: WorkoutStore
    let session: Session
    @State private var note = ""
    @State private var details = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 52)).foregroundStyle(.green).accessibilityHidden(true)
                    Text("Workout complete").font(.largeTitle.weight(.semibold))
                    Text(session.name).font(.title2.weight(.semibold))
                    HStack(spacing: 12) {
                        SummaryTile(title: "Minutes", value: "\(Int((session.ended ?? .now).timeIntervalSince(session.started) / 60))", icon: "timer")
                        SummaryTile(title: "Sets", value: "\(session.completedSets)", icon: "checkmark")
                    }
                    Text("\(session.exercises.count) exercises · \(session.volume.formatted(.number.precision(.fractionLength(0)))) \(store.data.unit) lifted").foregroundStyle(.secondary)
                    ForEach(session.exercises.filter { $0.sets.contains { $0.volumePR == true } }) { exercise in
                        Label("\(store.name(exercise.exerciseID)) · Volume PR", systemImage: "medal.fill").font(.headline).foregroundStyle(.green).repbookCard()
                    }
                    TextField("Add a workout note", text: $note, axis: .vertical).lineLimit(3...6).padding(16)
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                    Button("View full session") { details = true }.frame(minHeight: 44)
                    Button("Done") {
                        store.change { data in
                            if let i = data.workouts.firstIndex(where: { $0.id == session.id }) { data.workouts[i].notes = note }
                        }
                        store.completedSession = nil
                    }.frame(maxWidth: .infinity).buttonStyle(RepbookPrimaryStyle())
                }.padding(20)
            }.background(Color(uiColor: .systemBackground)).navigationBarTitleDisplayMode(.inline)
                .navigationDestination(isPresented: $details) { SessionDetailView(sessionID: session.id) }
                .onAppear { note = session.notes ?? "" }
        }.interactiveDismissDisabled()
    }
}

struct SessionSettingsSheet: View {
    @EnvironmentObject private var store: WorkoutStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                if let session = store.data.active {
                    Section("Workout") {
                        TextField("Workout name", text: Binding(get: { store.data.active?.name ?? session.name }, set: { name in
                            if !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { store.change { $0.active?.name = name } }
                        }))
                        TextField("Session note", text: Binding(get: { store.data.active?.notes ?? "" }, set: { note in store.change { $0.active?.notes = note } }), axis: .vertical)
                    }
                    ForEach(session.exercises) { exercise in
                        Section(store.name(exercise.exerciseID)) {
                            TextField("Exercise note", text: Binding(get: { store.data.active?.exercises.first { $0.id == exercise.id }?.notes ?? "" }, set: { note in
                                store.change { if let i = $0.active?.exercises.firstIndex(where: { $0.id == exercise.id }) { $0.active?.exercises[i].notes = note } }
                            }), axis: .vertical)
                            Picker("Rest duration", selection: Binding(get: { store.data.active?.exercises.first { $0.id == exercise.id }?.restSeconds ?? -1 }, set: { seconds in
                                store.change { if let i = $0.active?.exercises.firstIndex(where: { $0.id == exercise.id }) { $0.active?.exercises[i].restSeconds = seconds < 0 ? nil : seconds } }
                            })) {
                                Text("Default").tag(-1); Text("Off").tag(0)
                                ForEach([30, 45, 60, 90, 120, 150, 180, 240, 300], id: \.self) { Text("\($0) sec").tag($0) }
                            }
                        }
                    }
                }
            }.navigationTitle("Current session").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("Done") { dismiss() } }.scrollDismissesKeyboard(.interactively)
        }
    }
}
