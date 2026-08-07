import SwiftUI
import SwiftData

struct CustomerListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Customer.name) private var customers: [Customer]

    @State private var isShowingAddCustomer = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(customers) { customer in
                    NavigationLink(value: customer) {
                        CustomerRow(customer: customer)
                    }
                }
                .onDelete(perform: deleteCustomers)
            }
            .navigationTitle("Customers")
            .navigationDestination(for: Customer.self) { customer in
                CustomerDetailView(customer: customer)
            }
            .overlay {
                if customers.isEmpty {
                    ContentUnavailableView {
                        Label("No Customers Yet", systemImage: "person.crop.circle.badge.plus")
                    } description: {
                        Text("Add your first customer to get started.")
                    } actions: {
                        Button("Add Customer") {
                            isShowingAddCustomer = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isShowingAddCustomer = true
                    } label: {
                        Label("Add Customer", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $isShowingAddCustomer) {
                AddEditCustomerView(customer: nil)
            }
        }
    }

    private func deleteCustomers(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(customers[index])
        }
    }
}

private struct CustomerRow: View {
    let customer: Customer

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(customer.name)
                    .font(.headline)
                Text(customer.address)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if customer.isDue {
                Text("Due")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.orange.opacity(0.2))
                    .foregroundStyle(.orange)
                    .clipShape(Capsule())
            }
        }
    }
}

#Preview {
    CustomerListView()
        .modelContainer(for: Customer.self, inMemory: true)
}
