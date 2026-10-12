import Foundation

/// What the round needs to look like to make the weekly target in the chosen round length.
/// The work rate (houses per workday) is taken as given: it's the one thing that can't easily change.
/// Worked out twice: as planned (every usual working day worked) and as actually worked (days lost to
/// weather and holidays included). The Stats cards show the planned figures.
struct Ideal {
    struct Scenario {
        var daysPerWeek: Decimal
        /// Houses a week the crew gets through.
        var capacity: Decimal
        /// Houses a week the round supplies at the target round length.
        var supply: Decimal
        /// The lower of the two: the houses there actually are to charge for.
        var housesPerWeek: Decimal { min(capacity, supply) }
        var limitedByCustomers: Bool { supply < capacity }
        /// Average price needed to make the weekly target.
        var perHouse: Decimal
        /// Cleans a round (every-other at half) the crew can get round in the target round length.
        var cleansNeeded: Decimal
        /// The same as people, keeping today's mix of every-other customers.
        var peopleNeeded: Int
        /// How long the current round takes at this rate.
        var roundWeeksNow: Decimal
        /// Weekly income at today's average price.
        var incomeNow: Decimal
    }

    let weeks: Int
    let weeklyTarget: Decimal
    let usualDays: Int
    let rate: RoundStats.WorkRate?
    let people: Int
    let cleansPerRound: Decimal
    let periodLabel: String
    /// Round value needed (list prices): weekly target x weeks, grossed up for skips.
    let roundValue: Decimal?
    let planned: Scenario?
    let actual: Scenario?

    /// - Parameters:
    ///   - people: customers on the round (active or leaving).
    ///   - cleansPerRound: the same customers with every-other ones counted as half.
    init(weeklyTarget: Decimal, usualDays: Int, weeks: Int, rate: RoundStats.WorkRate?, people: Int,
         cleansPerRound: Decimal, periodLabel: String) {
        self.weeks = weeks
        self.weeklyTarget = weeklyTarget
        self.usualDays = usualDays
        self.rate = rate
        self.people = people
        self.cleansPerRound = cleansPerRound
        self.periodLabel = periodLabel
        guard weeklyTarget > 0, usualDays > 0, let rate, rate.housesPerDay > 0 else {
            roundValue = nil; planned = nil; actual = nil
            return
        }
        let keep = Decimal(max(0.5, 1 - rate.skipRate))
        roundValue = weeklyTarget * Decimal(weeks) / keep

        func scenario(days: Decimal) -> Scenario? {
            let capacity = rate.housesPerDay * days
            guard capacity > 0 else { return nil }
            let supply = cleansPerRound * keep / Decimal(weeks)
            let used = min(capacity, supply)
            let cleans = capacity * Decimal(weeks) / keep
            let ratio = cleansPerRound > 0 ? Decimal(people) / cleansPerRound : 1
            return Scenario(
                daysPerWeek: days, capacity: capacity, supply: supply,
                perHouse: used > 0 ? weeklyTarget / used : 0,
                cleansNeeded: cleans,
                peopleNeeded: Int(NSDecimalNumber(decimal: cleans * ratio).doubleValue.rounded()),
                roundWeeksNow: cleansPerRound * keep / capacity,
                incomeNow: used * rate.perHouse)
        }
        planned = scenario(days: Decimal(usualDays))
        actual = scenario(days: rate.daysPerWeek)
    }

    var keep: Decimal { Decimal(max(0.5, 1 - (rate?.skipRate ?? 0))) }
}
