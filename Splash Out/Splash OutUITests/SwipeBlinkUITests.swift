import XCTest

/// Drives real swipes on the Round for Tools/swipe-check.sh. The app's RowProbe records which rows leave and come
/// back; the script reads that file and decides pass or fail.
final class SwipeBlinkUITests: XCTestCase {
    private func topRow(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'roundRow'")).firstMatch
    }

    /// Half swipe on the top row, then tap Not paid (how it's usually done on the round).
    func testNotPaidFromHalfSwipe() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-RowProbe"]
        app.launch()
        XCTAssertTrue(topRow(app).waitForExistence(timeout: 30), "No Round row")
        for _ in 0..<3 {
            let row = topRow(app)
            row.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
                .press(forDuration: 0.05, thenDragTo: row.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5)))
            let notPaid = app.buttons["Not paid"]
            XCTAssertTrue(notPaid.waitForExistence(timeout: 3), "Swipe didn't open")
            notPaid.tap()
            Thread.sleep(forTimeInterval: 2.5)
        }
    }

    /// Full swipe on the top row that can leave straight away (Paid, nothing owed).
    func testFullSwipePaid() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-RowProbe"]
        app.launch()
        let rows = app.buttons.matching(identifier: "roundRow")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 30), "No Round row that can be swiped away")
        rows.firstMatch.swipeRight(velocity: .fast)
        Thread.sleep(forTimeInterval: 2.5)
    }
}
