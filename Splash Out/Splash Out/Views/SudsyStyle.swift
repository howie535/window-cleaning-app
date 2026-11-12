import SwiftUI

/// Sudsy's colours. The brand blue is the app's AccentColor (sampled from the icon; a deeper shade in light mode so
/// text and buttons stay readable on white). Colour always says what something is: green paid, orange not paid,
/// red owed or skipped.
extension Color {
    // Color.sudsyBackground (a faint brand-blue tint behind grouped screens, instead of plain grey) comes from the
    // SudsyBackground colour set in the asset catalog.
    static let paid = Color.green
    static let notPaid = Color.orange
    static let owed = Color.red
}

/// A white symbol on a small coloured rounded square, as in the iPhone's own Settings app.
struct IconBadge: View {
    let systemName: String
    let color: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 29, height: 29)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// A list row label with a coloured icon square.
struct BadgeLabel: View {
    let title: String
    let systemName: String
    let color: Color
    /// A count shown on the right, e.g. how many need attention. Hidden when nil or 0.
    var count: Int? = nil

    var body: some View {
        HStack {
            Label { Text(title) } icon: { IconBadge(systemName: systemName, color: color) }
            if let count, count > 0 {
                Spacer()
                Text("\(count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(color, in: Capsule())
                    .accessibilityLabel("\(count) to look at")
            }
        }
    }
}

extension View {
    /// The tinted background on a grouped list or scroll view.
    func sudsyBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(Color.sudsyBackground)
    }
}

// MARK: Explanations

/// How Sudsy explains things (modelled on Apple's own apps and its UX writing team's advice):
/// - One short line on screen says what something does. Nothing on screen is longer than about a line.
/// - Everything else sits behind an ⓘ, as short points: one idea each, plain words, no repeats.
/// - Warnings someone needs before tapping stay on screen; only background goes behind the ⓘ.

/// An ⓘ that opens a small card of short points.
struct InfoButton: View {
    var title: String? = nil
    let points: [String]
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: {
            Image(systemName: "info.circle")
                .font(.body)
                .padding(4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(title.map { "About \($0)" } ?? "More about this")
        .popover(isPresented: $showing) {
            InfoCard(title: title, points: points)
                .presentationCompactAdaptation(.popover)
        }
    }
}

/// The card an InfoButton opens.
struct InfoCard: View {
    var title: String? = nil
    let points: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title { Text(title).font(.headline) }
            ForEach(points, id: \.self) { point in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle().fill(Color.accentColor).frame(width: 5, height: 5).alignmentGuide(.firstTextBaseline) { $0[.bottom] + 1 }
                    Text(point).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding()
        .frame(width: 300, alignment: .leading)
    }
}

/// A section footer: one short line, with the detail behind an ⓘ.
struct InfoFooter: View {
    let text: String
    var title: String? = nil
    var points: [String] = []

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            Text(text)
            if !points.isEmpty { InfoButton(title: title, points: points) }
        }
    }
}

/// Opens Sudsy's page in the Settings app, where Contacts and Calendar access are switched on.
@MainActor func openAppSettings() {
    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
}
