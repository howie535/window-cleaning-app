import SwiftUI

/// Holds the most recent undoable action for ten seconds (Docs/SPEC.md section 3).
@Observable
@MainActor
final class UndoCenter {
    struct Entry: Identifiable {
        let id = UUID()
        let message: String
        let undo: () -> Void
    }

    private(set) var entry: Entry?
    private var expiry: Task<Void, Never>?

    func offer(_ message: String, undo: @escaping () -> Void) {
        let entry = Entry(message: message, undo: undo)
        self.entry = entry
        expiry?.cancel()
        expiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, self?.entry?.id == entry.id else { return }
            self?.entry = nil
        }
    }

    func performUndo() {
        guard let entry else { return }
        entry.undo()
        dismiss()
    }

    func dismiss() {
        expiry?.cancel()
        entry = nil
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
