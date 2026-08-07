import SwiftUI
import CoreLocation

struct RouteView: View {
    let stops: [Customer]
    let startLocation: CLLocationCoordinate2D?

    @State private var orderedStops: [Customer] = []
    @State private var customerToLog: Customer?

    var body: some View {
        List {
            ForEach(Array(orderedStops.enumerated()), id: \.element.persistentModelID) { index, customer in
                RouteStopRow(
                    index: index + 1,
                    customer: customer,
                    onLogClean: { customerToLog = customer }
                )
            }
            .onMove { indices, newOffset in
                orderedStops.move(fromOffsets: indices, toOffset: newOffset)
            }
        }
        .navigationTitle("Today's Route")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                EditButton()
            }
        }
        .onAppear {
            orderedStops = RouteOrdering.order(stops, startingFrom: startLocation)
        }
        .sheet(item: $customerToLog) { customer in
            AddCleanLogView(customer: customer)
        }
    }
}

private struct RouteStopRow: View {
    let index: Int
    let customer: Customer
    let onLogClean: () -> Void

    private var mapsURL: URL? {
        var components = URLComponents(string: "https://maps.apple.com/")
        if let coordinate = customer.coordinate {
            components?.queryItems = [
                URLQueryItem(name: "daddr", value: "\(coordinate.latitude),\(coordinate.longitude)"),
                URLQueryItem(name: "dirflg", value: "d"),
            ]
        } else {
            components?.queryItems = [
                URLQueryItem(name: "daddr", value: customer.address),
                URLQueryItem(name: "dirflg", value: "d"),
            ]
        }
        return components?.url
    }

    var body: some View {
        HStack(spacing: 12) {
            Text("\(index)")
                .font(.headline)
                .frame(width: 28, height: 28)
                .background(Color.accentColor.opacity(0.15))
                .foregroundStyle(Color.accentColor)
                .clipShape(Circle())

            VStack(alignment: .leading) {
                Text(customer.name)
                    .font(.headline)
                Text(customer.address)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let mapsURL {
                Link(destination: mapsURL) {
                    Image(systemName: "map")
                }
                .buttonStyle(.bordered)
            }

            WhatsAppButton(customer: customer)
                .labelStyle(.iconOnly)
                .buttonStyle(.bordered)

            Button(action: onLogClean) {
                Image(systemName: "checkmark.circle")
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }
}
