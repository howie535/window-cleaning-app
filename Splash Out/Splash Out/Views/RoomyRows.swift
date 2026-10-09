import SwiftUI

extension View {
    /// Taller list rows on iPad (regular width), for working from a ladder or the van with wet or gloved hands.
    func roomyRows() -> some View { modifier(RoomyRows()) }
}

private struct RoomyRows: ViewModifier {
    @Environment(\.horizontalSizeClass) private var sizeClass

    func body(content: Content) -> some View {
        content.environment(\.defaultMinListRowHeight, sizeClass == .regular ? 68 : 44)
    }
}
