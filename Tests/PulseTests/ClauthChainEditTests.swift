import XCTest
@testable import Pulse

final class ClauthChainEditTests: XCTestCase {
    func testPresetsAndParsersMirrorTheSocketBands() {
        XCTAssertEqual(ClauthChainEdit.thresholdPresets, [50, 80, 90, 95, 100])
        XCTAssertEqual(ClauthChainEdit.parseFiveHourThreshold(" 85 "), 85)
        XCTAssertNil(ClauthChainEdit.parseFiveHourThreshold("101"))
        XCTAssertNil(ClauthChainEdit.parseFiveHourThreshold("9.5"))
        XCTAssertEqual(ClauthChainEdit.weeklyPresets, [90, 95, 98, 100])
        XCTAssertEqual(ClauthChainEdit.parseWeeklyLine("97.5"), 97.5)
        XCTAssertNil(ClauthChainEdit.parseWeeklyLine("49"))
        XCTAssertEqual(ClauthChainEdit.parseMemberWeekly("0"), 0)
        XCTAssertNil(ClauthChainEdit.parseMemberWeekly("nan"))
        XCTAssertEqual(ClauthChainEdit.percentLabel(98), "98%")
        XCTAssertEqual(ClauthChainEdit.percentLabel(97.5), "97.5%")
    }

    func testChainOrderedPutsMembersFirstInWalkOrder() throws {
        let status = try ClauthFixture.status()
        let codex = status.profiles.filter { $0.harness == .codex }
        XCTAssertEqual(ClauthChainEdit.chainOrdered(codex, chain: status.codexFallbackChain).map(\.name),
                       ["fx-codex-dev0", "fx-codex-xfx", "fx-codex-cl", "fx-code-bk"])
    }

    func testRemovalConsequenceIsPerHarness() throws {
        let status = try ClauthFixture.status()
        XCTAssertEqual(ClauthChainEdit.removalConsequence(of: "fx-main", in: status), .armedMember, "fx-cl is still armed")
        XCTAssertNil(ClauthChainEdit.removalConsequence(of: "fx-backup", in: status), "not a member")
        let lone = try ClauthFixture.status { object in
            ClauthFixture.editProfile(&object, "fx-cl") { profile in
                var fallback = profile["fallback"] as? [String: Any] ?? [:]
                fallback["armed"] = false
                profile["fallback"] = fallback
            }
        }
        XCTAssertEqual(ClauthChainEdit.removalConsequence(of: "fx-main", in: lone), .disablesAutoSwitch, "the codex chain's armed members do not count")
    }

    func testDeletePromptNamesEveryConsequence() {
        XCTAssertEqual(ClauthChainEdit.deletePrompt("x", active: false, inChain: false), "Delete x and its stored credentials? This can’t be undone.")
        XCTAssertEqual(ClauthChainEdit.deletePrompt("x", active: true, inChain: true),
                       "Delete x and its stored credentials? It is the active account — the live login is cleared too. It leaves the fallback chain. This can’t be undone.")
    }

    func testNameValidationMirrorsClauth() {
        XCTAssertEqual(ClauthNameValidation.error("", existing: []), "Enter a name.")
        XCTAssertEqual(ClauthNameValidation.error("Daemon", existing: []), "Daemon is a clauth command name — pick another.")
        XCTAssertNotNil(ClauthNameValidation.error(".hidden", existing: []))
        XCTAssertNotNil(ClauthNameValidation.error("a b", existing: []))
        XCTAssertNotNil(ClauthNameValidation.error("名字", existing: []), "ASCII only, as clauth's is_ascii_alphanumeric")
        XCTAssertEqual(ClauthNameValidation.error("FX-MAIN", existing: ["fx-main"]), "FX-MAIN already exists — re-authenticate that account instead.")
        XCTAssertNil(ClauthNameValidation.error("work@home+1", existing: ["fx-main"]))
    }

    func testSetupTokenValidation() {
        XCTAssertNil(ClauthSetupToken.validationError(""))
        XCTAssertEqual(ClauthSetupToken.validationError("abc"), "Doesn’t look like a claude setup-token mint (expected sk-ant-…).")
        XCTAssertEqual(ClauthSetupToken.validationError("sk-ant-" + String(repeating: "x", count: 40) + " y"), "The paste contains whitespace — looks partial or padded.")
        XCTAssertEqual(ClauthSetupToken.validationError("sk-ant-short"), "Too short to be a real mint.")
        let mint = "sk-ant-" + String(repeating: "x", count: 60)
        XCTAssertEqual(ClauthSetupToken.trimmed("  \(mint)\n"), mint)
        XCTAssertNil(ClauthSetupToken.trimmed("nope"))
    }
}
