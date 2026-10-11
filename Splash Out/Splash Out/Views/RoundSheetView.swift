import SwiftUI
import SwiftData

/// What goes in the "Clean N / P" cells of the round sheet.
/// Like the original spreadsheet, column N is the Nth time round the round. Each customer's visits run left to right
/// in order; someone who joined late (or whose early passes weren't recorded) starts further along, in the column their
/// neighbours' cleans of the same date are in.
enum RoundSheet {
    enum Kind { case paid, unpaid, part, skipped, notDue }

    struct Cell: Equatable {
        var date: String
        var pay: String
        var kind: Kind
        var when: Date
    }

    struct Layout {
        /// How many columns to the right each customer's first visit sits.
        var offsets: [UUID: Int] = [:]
        var columns = 0
    }

    private static func amount(_ value: Decimal) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
    }

    private static func cell(for visit: Visit) -> Cell {
        switch visit.kind {
        case .skipped:
            return Cell(date: "—", pay: "—", kind: .skipped, when: visit.date)
        case .notDue:
            return Cell(date: "—", pay: "—", kind: .notDue, when: visit.date)
        case .cleaned:
            let date = RoundCalendar.short(visit.date)
            if visit.paid >= visit.charged { return Cell(date: date, pay: amount(visit.paid), kind: .paid, when: visit.date) }
            if visit.paid > 0 { return Cell(date: date, pay: amount(visit.paid), kind: .part, when: visit.date) }
            return Cell(date: date, pay: "owes", kind: .unpaid, when: visit.date)
        }
    }

    private static func days(_ date: Date) -> Double { date.timeIntervalSince1970 / 86_400 }

    @MainActor
    static func layout(for customers: [Customer]) -> Layout {
        let sorted: [UUID: [Visit]] = Dictionary(uniqueKeysWithValues: customers.map { ($0.id, $0.allVisits.sorted { $0.date < $1.date }) })
        let most = sorted.values.map(\.count).max() ?? 0
        var layout = Layout()
        guard most > 0 else { return layout }

        // Customers with the most visits start in the first column and are the reference.
        var placed: [Customer] = customers.filter { sorted[$0.id]?.count == most }
        for customer in placed { layout.offsets[customer.id] = 0 }

        for customer in customers where layout.offsets[customer.id] == nil {
            let visits = sorted[customer.id] ?? []
            guard !visits.isEmpty else { continue }

            // What date each column is, according to the nearest customers already placed.
            let neighbours = placed.sorted { abs($0.sequence - customer.sequence) < abs($1.sequence - customer.sequence) }.prefix(6)
            var reference: [Int: [Double]] = [:]
            for neighbour in neighbours {
                for (index, visit) in (sorted[neighbour.id] ?? []).enumerated() {
                    reference[(layout.offsets[neighbour.id] ?? 0) + index, default: []].append(days(visit.date))
                }
            }
            func median(_ values: [Double]) -> Double { let v = values.sorted(); return v[v.count / 2] }

            var best = 0
            var bestCost = Double.infinity
            for offset in 0...max(0, most - visits.count + 1) {
                var cost = 0.0, used = 0
                for (index, visit) in visits.enumerated() {
                    if let values = reference[offset + index] { cost += abs(days(visit.date) - median(values)); used += 1 }
                }
                let score = used == 0 ? 1e9 : cost / Double(used)
                if score < bestCost - 0.001 { bestCost = score; best = offset }
            }
            layout.offsets[customer.id] = best
            placed.append(customer)
        }

        layout.columns = customers.map { (layout.offsets[$0.id] ?? 0) + (sorted[$0.id]?.count ?? 0) }.max() ?? 0
        return layout
    }

    /// One cell (or nil for "nothing in that column") per column.
    @MainActor
    static func cells(for customer: Customer, layout: Layout, columns: Int) -> [Cell?] {
        var slots = [Cell?](repeating: nil, count: columns)
        let offset = layout.offsets[customer.id] ?? 0
        for (index, visit) in customer.allVisits.sorted(by: { $0.date < $1.date }).enumerated() where offset + index < columns {
            slots[offset + index] = cell(for: visit)
        }
        return slots
    }
}

/// The round as one big sheet, like the paper-style spreadsheet: a tab per round, a row per customer in round order,
/// a coloured block per area, then Clean 1 / P1, Clean 2 / P2 ... across the page.
struct RoundSheetView: View {
    @Query(sort: \Customer.sequence) private var customers: [Customer]
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var selectedRound: String?
    @State private var showCancelled = false
    @State private var headerPosition = ScrollPosition(edge: .leading)
    @State private var rowsPosition = ScrollPosition(edge: .leading)

    private let rowHeight: CGFloat = 36
    private let headerHeight: CGFloat = 30
    private let dateWidth: CGFloat = 62
    private let payWidth: CGFloat = 44
    private let bandWidth: CGFloat = 26

    private var wide: Bool { sizeClass == .regular }
    private var numberWidth: CGFloat { wide ? 34 : 0 }
    private var nameWidth: CGFloat { wide ? 150 : 112 }
    private var addressWidth: CGFloat { wide ? 175 : 0 }
    private var priceWidth: CGFloat { 48 }
    private var eoWidth: CGFloat { wide ? 34 : 0 }
    private var leftWidth: CGFloat { bandWidth + numberWidth + nameWidth + addressWidth + priceWidth + eoWidth }

    // The spreadsheet's colours.
    private let bandA = Color(red: 0.69, green: 0.78, blue: 0.91)
    private let bandB = Color(red: 0.85, green: 0.89, blue: 0.95)
    private let headerBlue = Color(red: 0.36, green: 0.62, blue: 0.86)
    private let priceYellow = Color(red: 1.0, green: 0.75, blue: 0.0)
    private let areaColours: [Color] = [
        Color(red: 0.36, green: 0.62, blue: 0.86), Color(red: 0.93, green: 0.52, blue: 0.24), Color(red: 1.0, green: 0.78, blue: 0.0),
        Color(red: 0.26, green: 0.42, blue: 0.77), Color(red: 0.44, green: 0.68, blue: 0.28), Color(red: 0.62, green: 0.40, blue: 0.70),
    ]

    private struct Row: Identifiable {
        var customer: Customer
        var index: Int
        var cells: [RoundSheet.Cell?]
        var id: UUID { customer.id }
    }

    private struct Group: Identifiable {
        var area: String
        var colour: Color
        var rows: [Row]
        var id: UUID { rows[0].id }
    }

    private func roundName(_ customer: Customer) -> String { customer.round.isEmpty ? "No round" : customer.round }

    private var rounds: [String] {
        var first: [String: Int] = [:]
        for customer in customers { first[roundName(customer), default: .max] = min(first[roundName(customer)] ?? .max, customer.sequence) }
        return first.sorted { $0.value < $1.value }.map(\.key)
    }

    private var currentRound: String? { selectedRound.flatMap { rounds.contains($0) ? $0 : nil } ?? rounds.first }

    private var rows: [Row] {
        guard let round = currentRound else { return [] }
        let shown = customers.filter { roundName($0) == round && (showCancelled || $0.status != .cancelled) }
        let layout = RoundSheet.layout(for: shown)
        let columns = max(8, layout.columns + 1)
        return shown.enumerated().map { Row(customer: $1, index: $0, cells: RoundSheet.cells(for: $1, layout: layout, columns: columns)) }
    }

    private func groups(of rows: [Row]) -> [Group] {
        var result: [Group] = []
        var colourFor: [String: Color] = [:]
        for row in rows {
            let area = row.customer.area
            if colourFor[area] == nil { colourFor[area] = areaColours[colourFor.count % areaColours.count] }
            if let last = result.last, last.area == area {
                result[result.count - 1].rows.append(row)
            } else {
                result.append(Group(area: area, colour: colourFor[area]!, rows: [row]))
            }
        }
        return result
    }

    var body: some View {
        let rows = rows
        let columns = rows.first?.cells.count ?? 8

        VStack(spacing: 0) {
            controls(columns: columns)
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        sheet(rows: rows, columns: columns)
                    } header: {
                        headerRow(columns: columns)
                    }
                }
            }
        }
        .fontDesign(.serif)
        .navigationTitle("Round Sheet")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Controls

    @ViewBuilder
    private func controls(columns: Int) -> some View {
        VStack(spacing: 8) {
            if rounds.count > 1 {
                Picker("Round", selection: Binding(get: { currentRound ?? "" }, set: { selectedRound = $0 })) {
                    ForEach(rounds, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            HStack {
                Toggle("Show cancelled", isOn: $showCancelled)
                    .font(.subheadline)
                    .fixedSize()
                Spacer()
                Button {
                    rowsPosition.scrollTo(x: CGFloat(columns) * (dateWidth + payWidth))
                } label: {
                    Label("Go to latest", systemImage: "arrow.right.to.line")
                        .font(.subheadline)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: Header

    private func headCell(_ text: String, width: CGFloat, sub: String? = nil) -> some View {
        VStack(spacing: 0) {
            Text(text).font(.system(size: 13, weight: .bold))
            if let sub { Text(sub).font(.system(size: 9)).opacity(0.85) }
        }
            .foregroundStyle(.white)
            .frame(width: width, height: headerHeight)
            .background(headerBlue)
            .overlay(Rectangle().stroke(Color.white.opacity(0.6), lineWidth: 0.5))
    }

    private func headerRow(columns: Int) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                headCell("", width: bandWidth)
                if wide { headCell("#", width: numberWidth) }
                headCell("Name", width: nameWidth)
                if wide { headCell("Address", width: addressWidth) }
                headCell("Price", width: priceWidth)
                if wide { headCell("EO", width: eoWidth) }
            }
            .frame(width: leftWidth)

            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(1...columns, id: \.self) { n in
                        headCell("Clean \(n)", width: dateWidth)
                        headCell("P\(n)", width: payWidth)
                    }
                }
            }
            .scrollDisabled(true)
            .scrollIndicators(.hidden)
            .scrollPosition($headerPosition)
        }
        .background(headerBlue)
    }

    // MARK: Body

    private func sheet(rows: [Row], columns: Int) -> some View {
        let groups = groups(of: rows)
        let priced = rows.filter { $0.customer.status == .active || $0.customer.status == .leaving || $0.customer.status == .notStarted }
        let total = priced.reduce(Decimal(0)) { $0 + $1.customer.price }
        let average = priced.isEmpty ? Decimal(0) : total / Decimal(priced.count)

        return HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 0) {
                ForEach(groups) { group in
                    HStack(spacing: 0) {
                        areaBand(group)
                        VStack(spacing: 0) {
                            ForEach(group.rows) { leftRow($0) }
                        }
                    }
                }
                totalRow("Total", total)
                totalRow("Average", average)
            }
            .frame(width: leftWidth)

            ScrollView(.horizontal) {
                VStack(spacing: 0) {
                    ForEach(rows) { rightRow($0, columns: columns) }
                    Color.clear.frame(height: rowHeight * 2)
                }
            }
            .scrollPosition($rowsPosition)
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.x } action: { _, x in
                headerPosition.scrollTo(x: x)
            }
        }
    }

    private func areaBand(_ group: Group) -> some View {
        let height = CGFloat(group.rows.count) * rowHeight
        return Text(group.area)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.black)
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .frame(width: max(height - 6, 10), height: bandWidth)
            .rotationEffect(.degrees(-90))
            .frame(width: bandWidth, height: height)
            .background(group.colour)
            .overlay(Rectangle().stroke(Color.white.opacity(0.6), lineWidth: 0.5))
    }

    private func fill(_ index: Int) -> Color { index.isMultiple(of: 2) ? bandA : bandB }

    private func nameColour(_ customer: Customer) -> Color {
        switch customer.status {
        case .active: .black
        case .leaving: Color(red: 0.75, green: 0.35, blue: 0.0)
        default: .gray
        }
    }

    private func leftRow(_ row: Row) -> some View {
        let customer = row.customer
        return NavigationLink {
            CustomerDetailView(customer: customer)
        } label: {
            HStack(spacing: 0) {
                if wide { text("\(customer.sequence)", width: numberWidth, size: 11, colour: .black.opacity(0.6)).background(fill(row.index)) }
                text(customer.name, width: nameWidth, size: 13, colour: nameColour(customer), lines: 2).background(fill(row.index))
                if wide { text(customer.address, width: addressWidth, size: 12, colour: nameColour(customer), lines: 2).background(fill(row.index)) }
                text("£\(customer.price.formatted(.number.precision(.fractionLength(0...2))))", width: priceWidth, size: 13, colour: .black).background(priceYellow)
                if wide { text(customer.everyOther ? "EO" : "", width: eoWidth, size: 12, colour: .black).background(fill(row.index)) }
            }
        }
        .buttonStyle(.plain)
    }

    private func text(_ value: String, width: CGFloat, size: CGFloat, colour: Color, lines: Int = 1) -> some View {
        Text(value)
            .font(.system(size: size))
            .foregroundStyle(colour)
            .lineLimit(lines)
            .minimumScaleFactor(0.75)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 3)
            .frame(width: width, height: rowHeight)
            .overlay(Rectangle().stroke(Color.white.opacity(0.6), lineWidth: 0.5))
    }

    private func totalRow(_ label: String, _ value: Decimal) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: bandWidth + numberWidth, height: rowHeight)
            Text(label).font(.system(size: 13)).foregroundStyle(.primary).frame(width: nameWidth, height: rowHeight)
                .overlay(Rectangle().stroke(Color.primary.opacity(0.6), lineWidth: 0.75))
            Text(value.formatted(.currency(code: "GBP")))
                .font(.system(size: 13)).foregroundStyle(.primary)
                .frame(width: addressWidth > 0 ? addressWidth : priceWidth + 20, height: rowHeight, alignment: .trailing)
                .padding(.trailing, 6)
                .overlay(Rectangle().stroke(Color.primary.opacity(0.6), lineWidth: 0.75))
        }
    }

    private func rightRow(_ row: Row, columns: Int) -> some View {
        NavigationLink {
            CustomerDetailView(customer: row.customer)
        } label: {
            HStack(spacing: 0) {
                ForEach(0..<columns, id: \.self) { slot in
                    let cell: RoundSheet.Cell? = slot < row.cells.count ? row.cells[slot] : nil
                    cellText(cell?.date ?? "", width: dateWidth, cell: cell, isPay: false).background(fill(row.index))
                    cellText(cell?.pay ?? "", width: payWidth, cell: cell, isPay: true)
                        .background(cell?.kind == .unpaid ? Color(red: 1.0, green: 0.82, blue: 0.6) : fill(row.index))
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func cellText(_ value: String, width: CGFloat, cell: RoundSheet.Cell?, isPay: Bool) -> some View {
        let colour: Color = switch cell?.kind {
        case .skipped: Color(red: 0.7, green: 0.2, blue: 0.2)
        case .notDue: .gray
        case .unpaid: isPay ? Color(red: 0.75, green: 0.35, blue: 0.0) : .black
        case .part: isPay ? Color(red: 0.75, green: 0.35, blue: 0.0) : .black
        default: .black
        }
        return Text(value)
            .font(.system(size: 13, weight: cell?.kind == .part && isPay ? .bold : .regular))
            .foregroundStyle(colour)
            .frame(width: width, height: rowHeight)
            .overlay(Rectangle().stroke(Color.white.opacity(0.6), lineWidth: 0.5))
    }
}
