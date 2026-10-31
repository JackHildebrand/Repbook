import SwiftUI

struct RepbookPrimaryStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).padding(.horizontal, 20).frame(minHeight: 60)
            .foregroundStyle(Color(uiColor: .systemBackground)).background(Color.primary, in: Capsule())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

struct SummaryTile: View {
    let title: String
    let value: String
    let icon: String
    var valueColor: Color = .primary
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon).foregroundStyle(.secondary).accessibilityHidden(true)
            Text(value).font(.system(.title, design: .rounded, weight: .bold)).monospacedDigit().foregroundStyle(valueColor)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).repbookCard()
    }
}

extension View {
    func repbookCard() -> some View {
        padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

struct FloatingWorkoutSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
        } else {
            #if compiler(>=6.2)
            if #available(iOS 26.0, *) {
                content.glassEffect(.regular, in: .capsule)
            } else {
                content.background(.regularMaterial, in: Capsule())
            }
            #else
            content.background(.regularMaterial, in: Capsule())
            #endif
        }
    }
}

struct ExerciseHeading: View {
    let name: String
    var body: some View {
        let parts = Exercise.displayParts(name)
        VStack(alignment: .leading, spacing: 6) {
            Text(parts.title).font(.title2.weight(.semibold))
            if let equipment = parts.equipment { Text(equipment).font(.subheadline).foregroundStyle(.secondary) }
        }
    }
}
