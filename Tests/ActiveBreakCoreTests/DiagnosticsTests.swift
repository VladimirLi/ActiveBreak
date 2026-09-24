import Foundation
import Testing
@testable import ActiveBreakCore

@Test func timerDiagnosticContainsBoundedDecisionFields() throws {
    let inferred = Date(timeIntervalSince1970: 1_700_000_000.125)
    let recordID = UUID()
    let event = DiagnosticEvent(
        category: .timer,
        event: "sample",
        reason: "dead-time",
        stateBefore: .active,
        stateAfter: .idle,
        idleSeconds: 300.25,
        inferredEventAt: inferred,
        threshold: 1_500,
        deadTime: 300,
        validated: 42,
        provisional: 0,
        overtime: 0,
        effectKinds: ["history"],
        recordID: recordID,
        outcome: "closed"
    )

    let fields = try #require(
        JSONSerialization.jsonObject(with: JSONEncoder.activeBreak.encode(event))
            as? [String: Any]
    )
    #expect(Set(fields.keys) == [
        "category", "event", "reason", "stateBefore", "stateAfter",
        "idleSeconds", "inferredEventAt", "threshold", "deadTime",
        "validated", "provisional", "overtime", "effectKinds",
        "recordID", "outcome",
    ])
    #expect(fields["recordID"] as? String == recordID.uuidString)
    #expect(fields["inferredEventAt"] != nil)
    #expect(fields.keys.allSatisfy {
        !["key", "keystroke", "pointer", "coordinates", "appName", "windowTitle"].contains($0)
    })
}

