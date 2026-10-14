import SwiftUI
import SwiftData
import MapKit

/// Puts a house (or its whole group) into another group: nearest groups first. Groups next to each other in the
/// round just join up; one further away means moving the house(s) in the round to sit after that group.
struct GroupPickerView: View {
    let customer: Customer

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var customers: [Customer]
    @State private var wholeGroup = false
    @State private var confirmMove: GroupEditing.Cluster?

    var body: some View {
        let clusters = GroupEditing.clusters(customers)
        let mine = clusters.first { $0.members.contains { $0 === customer } }

        NavigationStack {
            List {
                if let mine {
                    Section {
                        LabeledContent("Now in", value: "\(mine.name) · \(mine.members.count) house\(mine.members.count == 1 ? "" : "s")")
                        if mine.members.count > 1 {
                            Picker("Move", selection: $wholeGroup) {
                                Text("Just this house").tag(false)
                                Text("The whole group").tag(true)
                            }
                            .pickerStyle(.segmented)
                            if !wholeGroup {
                                Button("Take this house out on its own") {
                                    GroupEditing.standAlone(customer, all: customers)
                                    save()
                                }
                            }
                        }
                    } footer: {
                        Text("Houses in a group are kept on the same day.")
                    }

                    Section("Join a group, nearest first") {
                        ForEach(GroupEditing.candidates(for: mine, in: clusters).prefix(25)) { target in
                            Button {
                                if abs(target.id - mine.id) == 1 { join(target, from: mine) } else { confirmMove = target }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(target.name).foregroundStyle(.primary)
                                        Text(target.members.map(\.name).prefix(3).joined(separator: ", ") + (target.members.count > 3 ? "…" : ""))
                                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                    Text(where_(target, from: mine)).font(.caption).foregroundStyle(.secondary)
                                }
                                .contentShape(Rectangle())
                            }
                            .tint(.primary)
                        }
                    }
                }
            }
            .navigationTitle(customer.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .alert("Move in the round?", isPresented: Binding(get: { confirmMove != nil }, set: { if !$0 { confirmMove = nil } }), presenting: confirmMove) { target in
                Button("Move") { if let mine { join(target, from: mine) } }
                Button("Cancel", role: .cancel) {}
            } message: { target in
                Text("\(wholeGroup ? "The whole group moves" : "\(customer.name) moves") in the round to just after \(target.last.name), and joins \(target.name).")
            }
        }
    }

    /// "Next in the round", "0.4 miles", or "12 groups away".
    private func where_(_ target: GroupEditing.Cluster, from mine: GroupEditing.Cluster) -> String {
        if target.id == mine.id - 1 { return "Before, in the round" }
        if target.id == mine.id + 1 { return "Next, in the round" }
        if let metres = GroupEditing.distance(mine, target) {
            let miles = metres / 1609.34
            return miles < 0.1 ? "Very close" : "\(miles.formatted(.number.precision(.fractionLength(1)))) miles"
        }
        return "\(abs(target.id - mine.id)) groups away"
    }

    private func join(_ target: GroupEditing.Cluster, from mine: GroupEditing.Cluster) {
        GroupEditing.join(wholeGroup ? mine.members : [customer], into: target, all: customers)
        save()
    }

    private func save() {
        try? modelContext.save()
        dismiss()
    }
}

/// A small map of where the customer is; tap for directions in Maps.
struct CustomerMapView: View {
    let customer: Customer
    @State private var looking = false

    var body: some View {
        Group {
            if let coordinate = customer.coordinate {
                Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 350, longitudinalMeters: 350))) {
                    Marker(customer.name, coordinate: coordinate)
                }
                .mapStyle(.standard(pointsOfInterest: .excludingAll))
                .allowsHitTesting(false)
                .frame(height: 170)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .bottomTrailing) {
                    Label("Directions", systemImage: "arrow.triangle.turn.up.right.circle.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(.regularMaterial, in: Capsule())
                        .padding(8)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if let url = URL(string: "http://maps.apple.com/?daddr=\(coordinate.latitude),\(coordinate.longitude)") {
                        UIApplication.shared.open(url)
                    }
                }
            } else {
                Label(looking ? "Finding on the map..." : "Not found on the map. Check the address.", systemImage: "map")
                    .foregroundStyle(.secondary)
                    .task {
                        looking = true
                        await MapPositions.find(customer)
                        looking = false
                    }
            }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
    }
}
