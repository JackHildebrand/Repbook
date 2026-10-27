import SwiftUI
import UIKit

private struct ExerciseFrames: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}

struct RoutineEditor: View {
    @EnvironmentObject private var store: WorkoutStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State var draft: Routine
    @State private var adding = false
    @GestureState private var holding = false
    @State private var dragging: String?
    @State private var frames: [String: CGRect] = [:]
    @State private var keyboard = false
    var body: some View {
        NavigationStack {
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        TextField("Routine name", text: $draft.name).font(.largeTitle.weight(.semibold))
                        TextField("Routine notes", text: Binding(get: { draft.notes ?? "" }, set: { draft.notes = $0 }), axis: .vertical).font(.subheadline)
                        ForEach($draft.exercises) { $item in
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(alignment: .top) {
                                    Text(store.name(item.exerciseID)).font(.headline).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                        .contentShape(Rectangle())
                                        .gesture(reorderGesture(item.id, scroll))
                                        .accessibilityHint("Hold to reorder. The actions menu also has move controls.")
                                    Menu {
                                        Button("Move up", systemImage: "arrow.up") { move(item.id, by: -1) }
                                        Button("Move down", systemImage: "arrow.down") { move(item.id, by: 1) }
                                        Button("Remove exercise", systemImage: "trash", role: .destructive) { draft.exercises.removeAll { $0.id == item.id } }
                                    } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }.accessibilityLabel("Exercise actions")
                                }
                                if dragging == nil {
                                    Stepper("Warmup sets: \(item.warmupCount)", value: $item.warmupCount, in: 0...10).frame(minHeight: 44)
                                    HStack {
                                        Text("Rest").foregroundStyle(.secondary)
                                        Spacer()
                                        Picker("Rest duration", selection: Binding(get: { item.restSeconds ?? -1 }, set: { item.restSeconds = $0 < 0 ? nil : $0 })) {
                                            Text("Default").tag(-1)
                                            Text("Off").tag(0)
                                            ForEach([30, 45, 60, 90, 120, 150, 180, 240, 300], id: \.self) { Text("\($0) sec").tag($0) }
                                        }.labelsHidden()
                                    }
                                    TextField("Exercise notes", text: Binding(get: { item.notes ?? "" }, set: { item.notes = $0 }), axis: .vertical)
                                    HStack { Text("Weight (\(store.data.unit))"); Spacer(); Text("Reps"); Spacer(); Text("Type") }.font(.caption).foregroundStyle(.secondary)
                                    ForEach($item.sets) { $set in
                                        HStack {
                                            TextField("Weight", value: $set.weight, format: .number).keyboardType(.decimalPad).accessibilityLabel("Target weight")
                                            TextField("Reps", value: $set.reps, format: .number).keyboardType(.numberPad).accessibilityLabel("Target reps")
                                            Menu {
                                                Button("Working set") { set.warmup = false }
                                                Button("Warmup set") { set.warmup = true }
                                                Button("Move up") { moveSet(set.id, exercise: item.id, by: -1) }
                                                Button("Move down") { moveSet(set.id, exercise: item.id, by: 1) }
                                                Button("Remove set", role: .destructive) { item.sets.removeAll { $0.id == set.id } }.disabled(item.sets.count <= 1)
                                            } label: { Text(set.warmup ? "W" : "Set").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("Set type and actions")
                                        }.textFieldStyle(.roundedBorder)
                                    }
                                    Button("Add set", systemImage: "plus") {
                                        var set = item.sets.last ?? WorkoutSet(); set.id = UUID().uuidString; set.done = false
                                        item.sets.append(set)
                                    }.frame(minHeight: 44)
                                }
                            }.repbookCard().opacity(dragging == nil || dragging == item.id ? 1 : 0.65)
                                .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(dragging == item.id ? Color.blue : .clear, lineWidth: 2))
                                .background(GeometryReader { geo in Color.clear.preference(key: ExerciseFrames.self, value: [item.id: geo.frame(in: .global)]) })
                                .id(item.id)
                        }
                        if dragging == nil {
                            Button { adding = true } label: { Label("Add exercise", systemImage: "plus").frame(maxWidth: .infinity) }.buttonStyle(RepbookPrimaryStyle())
                        }
                    }.padding(20)
                }.scrollDisabled(dragging != nil).scrollDismissesKeyboard(.interactively)
                    .onPreferenceChange(ExerciseFrames.self) { frames = $0 }
                    .onChange(of: holding) { _, held in if !held { withAnimation(reduceMotion ? nil : .snappy) { dragging = nil } } }
            }
            .background(Color(uiColor: .systemBackground)).navigationTitle("Edit routine").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let value = draft
                        store.change {
                            if let i = $0.routines.firstIndex(where: { $0.id == value.id }) { $0.routines[i] = value }
                            else { $0.routines.append(value) }
                        }
                        if store.error == nil { dismiss() }
                    }.fontWeight(.semibold).disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.exercises.isEmpty)
                }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) } }
            }
            .sheet(isPresented: $adding) {
                ExercisePicker(excluded: Set(draft.exercises.map(\.exerciseID))) { exercise in
                    draft.exercises.append(RoutineExercise(exerciseID: exercise.id)); adding = false
                }
            }
        }
    }
    private func reorderGesture(_ id: String, _ scroll: ScrollViewProxy) -> some Gesture {
        LongPressGesture(minimumDuration: 0.35, maximumDistance: 10)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .updating($holding) { value, held, _ in
                if case .second(true, _) = value { held = true }
            }
            .onChanged { value in
                guard case .second(true, let drag) = value else { return }
                if dragging == nil {
                    store.feedback()
                    withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85)) { dragging = id }
                }
                guard let drag, let from = draft.exercises.firstIndex(where: { $0.id == id }),
                      let target = frames.first(where: { $0.key != id && $0.value.contains(drag.location) })?.key,
                      let to = draft.exercises.firstIndex(where: { $0.id == target }), let targetFrame = frames[target] else { return }
                guard (to > from && drag.location.y > targetFrame.midY) || (to < from && drag.location.y < targetFrame.midY) else { return }
                withAnimation(reduceMotion ? nil : .interactiveSpring(response: 0.25, dampingFraction: 0.9)) {
                    draft.exercises.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
                }
                store.feedback()
                scroll.scrollTo(target, anchor: to > from ? .bottom : .top)
            }
            .onEnded { _ in withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85)) { dragging = nil } }
    }
    private func move(_ id: String, by offset: Int) {
        guard let from = draft.exercises.firstIndex(where: { $0.id == id }), draft.exercises.indices.contains(from + offset) else { return }
        withAnimation(reduceMotion ? nil : .snappy) { draft.exercises.swapAt(from, from + offset) }
    }
    private func moveSet(_ id: String, exercise: String, by offset: Int) {
        guard let ei = draft.exercises.firstIndex(where: { $0.id == exercise }),
              let si = draft.exercises[ei].sets.firstIndex(where: { $0.id == id }), draft.exercises[ei].sets.indices.contains(si + offset) else { return }
        draft.exercises[ei].sets.swapAt(si, si + offset)
    }
}
