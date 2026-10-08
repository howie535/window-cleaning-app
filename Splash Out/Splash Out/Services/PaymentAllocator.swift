import Foundation

/// A lump-sum payment pays the oldest visits first (Docs/SPEC.md section 3).
/// Pure arithmetic, no storage, so it can be tested on its own.
enum PaymentAllocator {
    struct Result: Equatable {
        /// How much goes to each visit, in the same order as the `owed` input.
        var allocations: [Decimal]
        /// Money that couldn't be placed because it was more than the total owed.
        var leftover: Decimal
    }

    /// - Parameter owed: what is still owed on each visit, oldest first. Zero or negative entries get nothing.
    static func allocate(_ amount: Decimal, owed: [Decimal]) -> Result {
        var remaining = max(amount, 0)
        var allocations: [Decimal] = []
        for due in owed {
            let share = min(max(due, 0), remaining)
            allocations.append(share)
            remaining -= share
        }
        return Result(allocations: allocations, leftover: remaining)
    }
}
