import SwiftUI

struct WeeklyMuscleMap: View {
    let activity: WeeklyMuscleActivity
    @State private var showBreakdown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Muscles trained").font(.title3.weight(.semibold))
                    Text("Past 7 days · " + activity.start.formatted(.dateTime.month(.abbreviated).day()) + "–" + activity.end.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text("\(activity.trainedGroups.count) / \(Exercise.muscleGroups.count)")
                    .font(.subheadline.weight(.semibold)).monospacedDigit()
                    .accessibilityLabel("\(activity.trainedGroups.count) of \(Exercise.muscleGroups.count) muscle groups trained")
            }
            HStack(spacing: 20) {
                MuscleBodyDiagram(back: false, trained: Set(activity.trainedGroups))
                MuscleBodyDiagram(back: true, trained: Set(activity.trainedGroups))
            }.frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Muscle map. " + (activity.trainedGroups.isEmpty ? "No muscles trained in the past seven days." : "Trained: " + activity.trainedGroups.joined(separator: ", ")))
            HStack(spacing: 16) {
                legend("Trained", color: .blue)
                legend("No logged sets", color: Color(uiColor: .tertiaryLabel))
            }.font(.caption).foregroundStyle(.secondary)
            if activity.trainedGroups.isEmpty {
                Text("Your saved workouts will light up this map.").font(.subheadline).foregroundStyle(.secondary)
            }
            DisclosureGroup("Working set breakdown", isExpanded: $showBreakdown) {
                VStack(spacing: 0) {
                    ForEach(Exercise.muscleGroups, id: \.self) { group in
                        HStack {
                            Text(group)
                            Spacer()
                            Text("\(activity.sets[group, default: 0]) sets").monospacedDigit()
                                .foregroundStyle(activity.sets[group, default: 0] > 0 ? Color.blue : Color.secondary)
                        }.font(.subheadline).frame(minHeight: 36)
                    }
                }.padding(.top, 8)
            }.font(.subheadline.weight(.medium)).tint(.primary)
            Text("Primary muscles only · warmups excluded. This shows training history, not recovery.")
                .font(.caption).foregroundStyle(.secondary)
            if activity.sets["Unassigned", default: 0] > 0 {
                Text("\(activity.sets["Unassigned", default: 0]) sets have no muscle assignment and aren’t highlighted.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.repbookCard()
    }

    private func legend(_ title: String, color: Color) -> some View {
        HStack(spacing: 5) { Circle().fill(color).frame(width: 7, height: 7); Text(title) }
    }
}

private struct MuscleBodyDiagram: View {
    let back: Bool
    let trained: Set<String>
    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                let regions = back ? MuscleMapGeometry.back : MuscleMapGeometry.front
                ZStack {
                    MuscleContour(points: MuscleMapGeometry.outline)
                        .fill(Color(uiColor: .quaternaryLabel))
                    Ellipse().fill(Color(uiColor: .tertiaryLabel))
                        .frame(width: geometry.size.width * 0.17, height: geometry.size.height * 0.10)
                        .position(x: geometry.size.width * 0.5, y: geometry.size.height * 0.067)
                    ForEach(regions.indices, id: \.self) { index in
                        let region = regions[index]
                        MuscleContour(points: region.points)
                            .fill(trained.contains(region.muscle) ? Color.blue : Color(uiColor: .tertiaryLabel))
                            .overlay {
                                MuscleContour(points: region.points)
                                    .stroke(Color(uiColor: .secondarySystemGroupedBackground), lineWidth: 0.8)
                            }
                    }
                }
            }.aspectRatio(200.0 / 440.0, contentMode: .fit)
            Text(back ? "BACK" : "FRONT").font(.caption2.weight(.medium)).tracking(1.5).foregroundStyle(.secondary)
        }.frame(maxWidth: 160)
    }
}

/// Rounded closed contours scale without raster assets in both appearances.
private struct MuscleContour: Shape {
    let points: [CGPoint]
    func path(in rect: CGRect) -> Path {
        let scaled = points.map { CGPoint(x: rect.minX + $0.x / 200 * rect.width, y: rect.minY + $0.y / 440 * rect.height) }
        guard let first = scaled.first, let last = scaled.last else { return Path() }
        var path = Path()
        path.move(to: CGPoint(x: (first.x + last.x) / 2, y: (first.y + last.y) / 2))
        for index in scaled.indices {
            let next = scaled[(index + 1) % scaled.count]
            let point = scaled[index]
            path.addQuadCurve(to: CGPoint(x: (point.x + next.x) / 2, y: (point.y + next.y) / 2), control: point)
        }
        path.closeSubpath()
        return path
    }
}

/// Schematic muscle regions, deliberately separate from exercise data.
private enum MuscleMapGeometry {
    static let outline: [CGPoint] = [CGPoint(x: 91, y: 50), CGPoint(x: 89, y: 63), CGPoint(x: 70, y: 69), CGPoint(x: 57, y: 77), CGPoint(x: 50, y: 99), CGPoint(x: 45, y: 126), CGPoint(x: 38, y: 150), CGPoint(x: 33, y: 178), CGPoint(x: 28, y: 203), CGPoint(x: 24, y: 215), CGPoint(x: 26, y: 232), CGPoint(x: 32, y: 238), CGPoint(x: 37, y: 231), CGPoint(x: 40, y: 218), CGPoint(x: 40, y: 204), CGPoint(x: 48, y: 182), CGPoint(x: 55, y: 165), CGPoint(x: 60, y: 144), CGPoint(x: 65, y: 128), CGPoint(x: 69, y: 149), CGPoint(x: 73, y: 171), CGPoint(x: 70, y: 193), CGPoint(x: 64, y: 214), CGPoint(x: 64, y: 244), CGPoint(x: 69, y: 274), CGPoint(x: 71, y: 292), CGPoint(x: 69, y: 318), CGPoint(x: 74, y: 346), CGPoint(x: 78, y: 379), CGPoint(x: 78, y: 405), CGPoint(x: 71, y: 420), CGPoint(x: 72, y: 427), CGPoint(x: 91, y: 427), CGPoint(x: 95, y: 419), CGPoint(x: 92, y: 402), CGPoint(x: 94, y: 371), CGPoint(x: 97, y: 340), CGPoint(x: 95, y: 311), CGPoint(x: 96, y: 285), CGPoint(x: 98, y: 261), CGPoint(x: 100, y: 239), CGPoint(x: 102, y: 261), CGPoint(x: 104, y: 285), CGPoint(x: 105, y: 311), CGPoint(x: 103, y: 340), CGPoint(x: 106, y: 371), CGPoint(x: 108, y: 402), CGPoint(x: 105, y: 419), CGPoint(x: 109, y: 427), CGPoint(x: 128, y: 427), CGPoint(x: 129, y: 420), CGPoint(x: 122, y: 405), CGPoint(x: 122, y: 379), CGPoint(x: 126, y: 346), CGPoint(x: 131, y: 318), CGPoint(x: 129, y: 292), CGPoint(x: 131, y: 274), CGPoint(x: 136, y: 244), CGPoint(x: 136, y: 214), CGPoint(x: 130, y: 193), CGPoint(x: 127, y: 171), CGPoint(x: 131, y: 149), CGPoint(x: 135, y: 128), CGPoint(x: 140, y: 144), CGPoint(x: 145, y: 165), CGPoint(x: 152, y: 182), CGPoint(x: 160, y: 204), CGPoint(x: 160, y: 218), CGPoint(x: 163, y: 231), CGPoint(x: 168, y: 238), CGPoint(x: 174, y: 232), CGPoint(x: 176, y: 215), CGPoint(x: 172, y: 203), CGPoint(x: 167, y: 178), CGPoint(x: 162, y: 150), CGPoint(x: 155, y: 126), CGPoint(x: 150, y: 99), CGPoint(x: 143, y: 77), CGPoint(x: 130, y: 69), CGPoint(x: 111, y: 63), CGPoint(x: 109, y: 50)]
    static let front: [(muscle: String, points: [CGPoint])] = [
        ("Chest", [CGPoint(x: 98, y: 78), CGPoint(x: 83, y: 74), CGPoint(x: 69, y: 78), CGPoint(x: 65, y: 96), CGPoint(x: 70, y: 112), CGPoint(x: 88, y: 115), CGPoint(x: 98, y: 105)]),
        ("Chest", [CGPoint(x: 102, y: 78), CGPoint(x: 117, y: 74), CGPoint(x: 131, y: 78), CGPoint(x: 135, y: 96), CGPoint(x: 130, y: 112), CGPoint(x: 112, y: 115), CGPoint(x: 102, y: 105)]),
        ("Shoulders", [CGPoint(x: 66, y: 74), CGPoint(x: 55, y: 81), CGPoint(x: 50, y: 99), CGPoint(x: 53, y: 112), CGPoint(x: 63, y: 102), CGPoint(x: 68, y: 91)]),
        ("Shoulders", [CGPoint(x: 134, y: 74), CGPoint(x: 145, y: 81), CGPoint(x: 150, y: 99), CGPoint(x: 147, y: 112), CGPoint(x: 137, y: 102), CGPoint(x: 132, y: 91)]),
        ("Biceps", [CGPoint(x: 57, y: 111), CGPoint(x: 48, y: 128), CGPoint(x: 44, y: 150), CGPoint(x: 48, y: 160), CGPoint(x: 56, y: 146), CGPoint(x: 62, y: 126)]),
        ("Biceps", [CGPoint(x: 143, y: 111), CGPoint(x: 152, y: 128), CGPoint(x: 156, y: 150), CGPoint(x: 152, y: 160), CGPoint(x: 144, y: 146), CGPoint(x: 138, y: 126)]),
        ("Core", [CGPoint(x: 96, y: 119), CGPoint(x: 84, y: 118), CGPoint(x: 81, y: 139), CGPoint(x: 84, y: 164), CGPoint(x: 96, y: 174)]),
        ("Core", [CGPoint(x: 104, y: 119), CGPoint(x: 116, y: 118), CGPoint(x: 119, y: 139), CGPoint(x: 116, y: 164), CGPoint(x: 104, y: 174)]),
        ("Core", [CGPoint(x: 76, y: 121), CGPoint(x: 70, y: 118), CGPoint(x: 73, y: 147), CGPoint(x: 78, y: 171), CGPoint(x: 82, y: 179), CGPoint(x: 80, y: 154)]),
        ("Core", [CGPoint(x: 124, y: 121), CGPoint(x: 130, y: 118), CGPoint(x: 127, y: 147), CGPoint(x: 122, y: 171), CGPoint(x: 118, y: 179), CGPoint(x: 120, y: 154)]),
        ("Quads", [CGPoint(x: 74, y: 205), CGPoint(x: 66, y: 220), CGPoint(x: 68, y: 246), CGPoint(x: 75, y: 273), CGPoint(x: 83, y: 281), CGPoint(x: 89, y: 269), CGPoint(x: 88, y: 244), CGPoint(x: 83, y: 222)]),
        ("Quads", [CGPoint(x: 126, y: 205), CGPoint(x: 134, y: 220), CGPoint(x: 132, y: 246), CGPoint(x: 125, y: 273), CGPoint(x: 117, y: 281), CGPoint(x: 111, y: 269), CGPoint(x: 112, y: 244), CGPoint(x: 117, y: 222)]),
        ("Adductors", [CGPoint(x: 90, y: 205), CGPoint(x: 83, y: 198), CGPoint(x: 84, y: 216), CGPoint(x: 91, y: 243), CGPoint(x: 96, y: 254), CGPoint(x: 97, y: 232)]),
        ("Adductors", [CGPoint(x: 110, y: 205), CGPoint(x: 117, y: 198), CGPoint(x: 116, y: 216), CGPoint(x: 109, y: 243), CGPoint(x: 104, y: 254), CGPoint(x: 103, y: 232)]),
        ("Calves", [CGPoint(x: 77, y: 302), CGPoint(x: 73, y: 320), CGPoint(x: 79, y: 348), CGPoint(x: 85, y: 372), CGPoint(x: 89, y: 349), CGPoint(x: 90, y: 326), CGPoint(x: 85, y: 305)]),
        ("Calves", [CGPoint(x: 123, y: 302), CGPoint(x: 127, y: 320), CGPoint(x: 121, y: 348), CGPoint(x: 115, y: 372), CGPoint(x: 111, y: 349), CGPoint(x: 110, y: 326), CGPoint(x: 115, y: 305)]),
    ]
    static let back: [(muscle: String, points: [CGPoint])] = [
        ("Back", [CGPoint(x: 94, y: 63), CGPoint(x: 88, y: 66), CGPoint(x: 79, y: 69), CGPoint(x: 69, y: 77), CGPoint(x: 77, y: 90), CGPoint(x: 95, y: 103)]),
        ("Back", [CGPoint(x: 106, y: 63), CGPoint(x: 112, y: 66), CGPoint(x: 121, y: 69), CGPoint(x: 131, y: 77), CGPoint(x: 123, y: 90), CGPoint(x: 105, y: 103)]),
        ("Back", [CGPoint(x: 96, y: 109), CGPoint(x: 82, y: 94), CGPoint(x: 69, y: 101), CGPoint(x: 68, y: 123), CGPoint(x: 76, y: 145), CGPoint(x: 85, y: 164), CGPoint(x: 95, y: 170)]),
        ("Back", [CGPoint(x: 104, y: 109), CGPoint(x: 118, y: 94), CGPoint(x: 131, y: 101), CGPoint(x: 132, y: 123), CGPoint(x: 124, y: 145), CGPoint(x: 115, y: 164), CGPoint(x: 105, y: 170)]),
        ("Shoulders", [CGPoint(x: 66, y: 75), CGPoint(x: 55, y: 83), CGPoint(x: 51, y: 101), CGPoint(x: 54, y: 113), CGPoint(x: 63, y: 108), CGPoint(x: 73, y: 92)]),
        ("Shoulders", [CGPoint(x: 134, y: 75), CGPoint(x: 145, y: 83), CGPoint(x: 149, y: 101), CGPoint(x: 146, y: 113), CGPoint(x: 137, y: 108), CGPoint(x: 127, y: 92)]),
        ("Triceps", [CGPoint(x: 57, y: 114), CGPoint(x: 49, y: 128), CGPoint(x: 44, y: 152), CGPoint(x: 48, y: 164), CGPoint(x: 57, y: 148), CGPoint(x: 63, y: 127)]),
        ("Triceps", [CGPoint(x: 143, y: 114), CGPoint(x: 151, y: 128), CGPoint(x: 156, y: 152), CGPoint(x: 152, y: 164), CGPoint(x: 143, y: 148), CGPoint(x: 137, y: 127)]),
        ("Glutes", [CGPoint(x: 97, y: 183), CGPoint(x: 82, y: 179), CGPoint(x: 70, y: 191), CGPoint(x: 65, y: 211), CGPoint(x: 74, y: 228), CGPoint(x: 93, y: 227), CGPoint(x: 98, y: 215)]),
        ("Glutes", [CGPoint(x: 103, y: 183), CGPoint(x: 118, y: 179), CGPoint(x: 130, y: 191), CGPoint(x: 135, y: 211), CGPoint(x: 126, y: 228), CGPoint(x: 107, y: 227), CGPoint(x: 102, y: 215)]),
        ("Abductors", [CGPoint(x: 72, y: 178), CGPoint(x: 66, y: 191), CGPoint(x: 64, y: 208), CGPoint(x: 68, y: 215), CGPoint(x: 75, y: 197), CGPoint(x: 79, y: 186)]),
        ("Abductors", [CGPoint(x: 128, y: 178), CGPoint(x: 134, y: 191), CGPoint(x: 136, y: 208), CGPoint(x: 132, y: 215), CGPoint(x: 125, y: 197), CGPoint(x: 121, y: 186)]),
        ("Hamstrings", [CGPoint(x: 72, y: 233), CGPoint(x: 68, y: 245), CGPoint(x: 75, y: 271), CGPoint(x: 82, y: 288), CGPoint(x: 89, y: 275), CGPoint(x: 92, y: 247), CGPoint(x: 90, y: 234)]),
        ("Hamstrings", [CGPoint(x: 128, y: 233), CGPoint(x: 132, y: 245), CGPoint(x: 125, y: 271), CGPoint(x: 118, y: 288), CGPoint(x: 111, y: 275), CGPoint(x: 108, y: 247), CGPoint(x: 110, y: 234)]),
        ("Calves", [CGPoint(x: 79, y: 302), CGPoint(x: 73, y: 320), CGPoint(x: 78, y: 345), CGPoint(x: 86, y: 367), CGPoint(x: 91, y: 343), CGPoint(x: 89, y: 316), CGPoint(x: 86, y: 303)]),
        ("Calves", [CGPoint(x: 121, y: 302), CGPoint(x: 127, y: 320), CGPoint(x: 122, y: 345), CGPoint(x: 114, y: 367), CGPoint(x: 109, y: 343), CGPoint(x: 111, y: 316), CGPoint(x: 114, y: 303)]),
    ]
}
