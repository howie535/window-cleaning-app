import SwiftUI
import Charts

/// One look for every chart in the app:
/// - rounded blue bars with the same soft fade (orange only for a week short of its target);
/// - a solid dark line for a trend, and a dashed grey line for a reference (target or average);
/// - the same thin gridlines and labels.
enum ChartStyle {
    static let barWidth = MarkDimension.ratio(0.7)
    static let cornerRadius: CGFloat = 5

    static func barFill(short: Bool = false) -> LinearGradient {
        let colour = short ? Color.orange : Color.accentColor
        return LinearGradient(colors: [colour.opacity(0.45), colour.opacity(0.9)], startPoint: .bottom, endPoint: .top)
    }

    static let trendColour = Color.primary.opacity(0.75)
    static let trendStroke = StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
    static let referenceColour = Color.secondary
    static let referenceStroke = StrokeStyle(lineWidth: 1.5, dash: [5, 4])

    enum Values { case money, count, percent }

    /// A week's target: a short dashed line across that week's bar.
    static func targetMark(week: Date, target: Double) -> some ChartContent {
        RuleMark(xStart: .value("From", week), xEnd: .value("To", Calendar.current.date(byAdding: .day, value: 6, to: week) ?? week),
                 y: .value("Target", target))
            .lineStyle(referenceStroke)
            .foregroundStyle(referenceColour)
    }
}

extension View {
    /// The shared axes: values on the right with thin gridlines, dates along the bottom.
    func chartAxes(_ values: ChartStyle.Values, months: Bool = false, dateLabels: Int = 5) -> some View {
        self
            .chartYAxis {
                AxisMarks(position: .trailing) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            switch values {
                            case .money: Text("£" + Int(number.rounded()).formatted())
                            case .percent: Text("\(Int(number.rounded()))%")
                            case .count: Text(number.formatted(.number.precision(.fractionLength(0...1))))
                            }
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: dateLabels)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                    AxisValueLabel(format: months ? .dateTime.month(.abbreviated) : .dateTime.day().month(.abbreviated))
                }
            }
    }
}
