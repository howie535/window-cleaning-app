import SwiftUI
import UIKit

/// Holds the most recent undoable action (Docs/SPEC.md section 3). The banner shows it for ten seconds (longer with
/// VoiceOver on); after that it can still be undone for two minutes by shaking the phone, which asks first and names it.
@Observable
@MainActor
final class UndoCenter {
    struct Entry: Identifiable {
        let id = UUID()
        let message: String
        let undo: () -> Void
        let time = Date()
    }

    /// What the banner is showing.
    private(set) var entry: Entry?
    /// The last action, still undoable by a shake after the banner has gone.
    private var last: Entry?
    private var expiry: Task<Void, Never>?

    /// How long a shake can still undo the last action.
    static let shakeWindow: TimeInterval = 120

    func offer(_ message: String, undo: @escaping () -> Void) {
        let entry = Entry(message: message, undo: undo)
        self.entry = entry
        last = entry
        expiry?.cancel()
        let seconds = UIAccessibility.isVoiceOverRunning ? 30.0 : 10.0
        expiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, self?.entry?.id == entry.id else { return }
            self?.entry = nil
        }
    }

    /// The action a shake would undo, if it's recent enough.
    var shakeable: Entry? {
        guard let last, Date().timeIntervalSince(last.time) < Self.shakeWindow else { return nil }
        return last
    }

    func performUndo() {
        guard let target = entry ?? shakeable else { return }
        target.undo()
        dismiss()
        last = nil
    }

    func dismiss() {
        expiry?.cancel()
        entry = nil
    }
}

extension Notification.Name {
    static let sudsyDidShake = Notification.Name("sudsyDidShake")
}

/// Passes the iPhone's shake gesture on to SwiftUI (used for shake to undo).
extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake { NotificationCenter.default.post(name: .sudsyDidShake, object: nil) }
        super.motionEnded(motion, with: event)
    }
}

struct UndoBanner: View {
    let undoCenter: UndoCenter

    var body: some View {
        if let entry = undoCenter.entry {
            HStack(spacing: 12) {
                Text(entry.message)
                    .font(.subheadline)
                    .lineLimit(2)
                Spacer(minLength: 8)
                Button("Undo") { undoCenter.performUndo() }
                    .accessibilityLabel("Undo \(entry.message)")
                    .font(.headline)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
