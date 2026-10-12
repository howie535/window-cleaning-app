import SwiftUI

struct WhatsNewView: View {
    var body: some View {
        List {
            ForEach(ChangeLog.releases) { release in
                Section {
                    ForEach(release.changes, id: \.self) { change in
                        Text(change)
                    }
                } header: {
                    Text("Version \(release.version) · \(release.date)")
                }
            }
        }
        .navigationTitle("What's new")
    }
}
