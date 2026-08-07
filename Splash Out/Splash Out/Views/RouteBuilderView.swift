import SwiftUI
import SwiftData

private enum CrewSize: String, CaseIterable, Identifiable {
    case one = "1 person"
    case two = "2 people"

    var id: String { rawValue }

    var target: Decimal {
        switch self {
        case .one: 250
        case .two: 450
        }
    }
}

struct RouteBuilderView: View {
    @Query private var customers: [Customer]
    @StateObject private var locationManager = LocationManager()

    @State private var crewSize: CrewSize = .one
    @State private var selected: Set<ObjectIdentifier> = []
    @State private var isBuildingRoute = false
    @State private var orderedStops: [Customer] = []

    private var sortedCustomers: [Customer] {
        customers.sorted { ($0.nextDueDate ?? .distantPast) < ($1.nextDueDate ?? .distantPast) }
    }

    private var selectedCustomers: [Customer] {
        sortedCustomers.filter { selected.contains(ObjectIdentifier($0)) }
    }

    private var selectedTotal: Decimal {
        selectedCustomers.reduce(0) { $0 + $1.price }
    }

    private var progressColor: Color {
        let ratio = crewSize.target == 0 ? 0 : NSDecimalNumber(decimal: selectedTotal / crewSize.target).doubleValue
        if ratio > 1.1 { return .red }
        if ratio >= 0.85 { return .green }
        return .orange
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Crew size", selection: $crewSize) {
                    ForEach(CrewSize.allCases) { size in
                        Text(size.rawValue).tag(size)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                HStack {
                    Text(selectedTotal, format: .currency(code: "GBP"))
                        .font(.title2.bold())
                        .foregroundStyle(progressColor)
                    Text("of \(crewSize.target, format: .currency(code: "GBP")) target")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(selectedCustomers.count) selected")
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)

                List {
                    ForEach(sortedCustomers) { customer in
                        Button {
                            toggle(customer)
                        } label: {
                            CustomerSelectionRow(
                                customer: customer,
                                isSelected: selected.contains(ObjectIdentifier(customer))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Today's Route")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Plan Route") {
                        locationManager.requestLocation()
                        isBuildingRoute = true
                    }
                    .disabled(selectedCustomers.isEmpty)
                }
            }
            .navigationDestination(isPresented: $isBuildingRoute) {
                RouteView(stops: selectedCustomers, startLocation: locationManager.currentLocation)
            }
        }
    }

    private func toggle(_ customer: Customer) {
        let id = ObjectIdentifier(customer)
        if selected.contains(id) {
            selected.remove(id)
        } else {
            selected.insert(id)
        }
    }
}

private struct CustomerSelectionRow: View {
    let customer: Customer
    let isSelected: Bool

    var body: some View {
        HStack {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .font(.title3)

            VStack(alignment: .leading) {
                HStack {
                    Text(customer.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if customer.isDue {
                        Text("Due")
                            .font(.caption.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.orange.opacity(0.2))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }
                }
                Text(customer.address)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(customer.price, format: .currency(code: "GBP"))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    RouteBuilderView()
        .modelContainer(for: Customer.self, inMemory: true)
}
