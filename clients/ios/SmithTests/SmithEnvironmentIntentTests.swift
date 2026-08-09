import XCTest
@testable import Smith

final class SmithEnvironmentIntentTests: XCTestCase {
    func testWakeCommand() {
        XCTAssertEqual(SmithEnvironmentIntentParser.parse("Smith, wake up"), .wake)
    }

    func testConversationIsExplicitWorkspace() {
        XCTAssertEqual(
            SmithEnvironmentIntentParser.parse("Smith, pull up chat"),
            .open(.voice)
        )
    }

    func testClosingConversationReturnsToCommandCentreIntent() {
        XCTAssertEqual(
            SmithEnvironmentIntentParser.parse("Smith, close conversation"),
            .closeConversation
        )
    }

    func testOtherWorkspaceCommands() {
        XCTAssertEqual(SmithEnvironmentIntentParser.parse("Smith, open maps"), .open(.maps))
        XCTAssertEqual(SmithEnvironmentIntentParser.parse("Smith, show devices"), .open(.devices))
        XCTAssertEqual(SmithEnvironmentIntentParser.parse("Smith, open protocols"), .open(.protocols))
    }

    func testReturnToIdle() {
        XCTAssertEqual(SmithEnvironmentIntentParser.parse("Smith, close workspace"), .returnToIdle)
    }

    func testOrdinaryConversationDoesNotMoveInterface() {
        XCTAssertNil(SmithEnvironmentIntentParser.parse("The weather looks good today"))
    }
}
