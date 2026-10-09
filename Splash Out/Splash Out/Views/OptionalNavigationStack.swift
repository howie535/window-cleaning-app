import SwiftUI

/// Wraps content in its own NavigationStack, unless it's already inside one (e.g. pushed from the More tab).
struct OptionalNavigationStack<Content: View>: View {
    let embedded: Bool
    @ViewBuilder var content: () -> Content

    var body: some View {
        if embedded {
            content()
        } else {
            NavigationStack { content() }
        }
    }
}
