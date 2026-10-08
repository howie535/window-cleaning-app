import SwiftUI
import SwiftData

struct RouteBuilderView: View {
    @Query private var customers: [Customer]
    @StateObject private var locationManager = LocationManager()

    @State private var selected: Set<ObjectIdentifier> = []
    @State private var priceOverrides: [ObjectIdentifier: String] = [:]
    @State private var isBuildingRoute = false

    private var sortedCustomers: [Customer] {
        customers
            .filter { $0.status == .active || $0.status == .leaving }
            .sorted { $0.sequence < $1.sequence }
    }

    private var selectedCustomers: [Customer] {
        sortedCustomers.filter { selected.contains(ObjectIdentifier($0)) }
    }

    private var selectedTotal: Decimal {
        selectedCustomers.reduce(0) { $0 + effectivePrice(for: $1) }
    }

    private var stopPrices: [ObjectIdentifier: Decimal] {
        Dictionary(uniqueKeysWithValues: selectedCustomers.map { (ObjectIdentifier($0), effectivePrice(for: $0)) })
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Text(selectedTotal, format: .currency(code: "GBP"))
                        .font(.title2.bold())
                    Spacer()
                    Text("\(selectedCustomers.count) selected")
                        .foregroundStyle(.secondary)
                }
                .padding()

                List {
                    ForEach(sortedCustomers) { customer in
                        CustomerSelectionRow(
                            customer: customer,
                            isSelected: selected.contains(ObjectIdentifier(customer)),
                            priceText: priceBinding(for: customer),
                            onToggle: { toggle(customer) }
                        )
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
                RouteView(stops: selectedCustomers, stopPrices: stopPrices, startLocation: locationManager.currentLocation)
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

    private func effectivePrice(for customer: Customer) -> Decimal {
        let id = ObjectIdentifier(customer)
        if let text = priceOverrides[id], let value = Decimal(string: text) {
            return value
        }
        return customer.price
    }

    private func priceBinding(for customer: Customer) -> Binding<String> {
        let id = ObjectIdentifier(customer)
        return Binding(
            get: { priceOverrides[id] ?? NSDecimalNumber(decimal: customer.price).stringValue },
            set: { priceOverrides[id] = $0 }
        )
    }
}

private struct CustomerSelectionRow: View {
    let customer: Customer
    let isSelected: Bool
    let priceText: Binding<String>
    let onToggle: () -> Void

    var body: some View {
        HStack {
            Button(action: onToggle) {
                HStack {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        .font(.title3)

                    VStack(alignment: .leading) {
                        HStack {
                            Text(customer.name)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            if !customer.area.isEmpty {
                                Text(customer.area)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(customer.address)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            if isSelected {
                TextField("Price", text: priceText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 70)
            } else {
                Text(customer.price, format: .currency(code: "GBP"))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    RouteBuilderView()
        .modelContainer(for: Customer.self, inMemory: true)
}
