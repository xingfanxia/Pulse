import Foundation

/// The chain editor's vocabulary — ccsbar's `ChainEdit`, so presets, legal
/// bands and the removal-confirm copy have one source of truth. The
/// "wrap-off" jargon is absent from user-facing strings: the setting reads
/// as an outcome ("stay on the last account" / "switch everything off").
enum ClauthChainEdit {
    /// The 5h utilization at which auto-switch LEAVES an account.
    static let thresholdPresets = [50, 80, 90, 95, 100]
    static let fiveHourRange = 0...100

    static func parseFiveHourThreshold(_ raw: String) -> Int? {
        guard let value = Int(raw.trimmingCharacters(in: .whitespaces)), fiveHourRange.contains(value) else { return nil }
        return value
    }

    static let weeklyPresets: [Double] = [90, 95, 98, 100]
    static let defaultWeeklyLine: Double = 98
    static let weeklyRange: ClosedRange<Double> = 50...100

    static func parseWeeklyLine(_ raw: String) -> Double? {
        guard let value = Double(raw.trimmingCharacters(in: .whitespaces)), value.isFinite, weeklyRange.contains(value) else { return nil }
        return value
    }

    static let memberWeeklyRange: ClosedRange<Double> = 0...100

    static func parseMemberWeekly(_ raw: String) -> Double? {
        guard let value = Double(raw.trimmingCharacters(in: .whitespaces)), value.isFinite, memberWeeklyRange.contains(value) else { return nil }
        return value
    }

    /// "90%" — no trailing `.0` on whole percents.
    static func percentLabel(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(value))%" : "\(value)%"
    }

    /// Chain members first in chain order, then non-members as published.
    static func chainOrdered(_ profiles: [ClauthStatus.Profile], chain: [String]) -> [ClauthStatus.Profile] {
        let members = profiles
            .filter { $0.fallback != nil }
            .sorted { (chain.firstIndex(of: $0.name) ?? .max) < (chain.firstIndex(of: $1.name) ?? .max) }
        return members + profiles.filter { $0.fallback == nil }
    }

    enum RemovalConsequence: Equatable, Sendable {
        /// The last armed member of its harness — auto-switch stops entirely.
        case disablesAutoSwitch
        /// Armed, but other armed members remain.
        case armedMember

        var prompt: String {
            switch self {
            case .disablesAutoSwitch: String.localized("This disables auto-switch — remove anyway?")
            case .armedMember: String.localized("This account is armed for auto-switch — remove anyway?")
            }
        }
    }

    /// Whether removing `name` needs a confirm, and what to say. Armed is
    /// per harness, so only same-harness armed members count as "others".
    static func removalConsequence(of name: String, in status: ClauthStatus) -> RemovalConsequence? {
        guard let profile = status.profile(named: name), profile.fallback?.armed == true else { return nil }
        let otherArmed = status.profiles.contains {
            $0.name != name && $0.harness == profile.harness && ($0.fallback?.armed ?? false)
        }
        return otherArmed ? .armedMember : .disablesAutoSwitch
    }

    /// The delete-confirm copy: every consequence the click commits to.
    static func deletePrompt(_ name: String, active: Bool, inChain: Bool) -> String {
        var prompt = String.localized("Delete \(name) and its stored credentials?")
        if active { prompt += " " + String.localized("It is the active account — the live login is cleared too.") }
        if inChain { prompt += " " + String.localized("It leaves the fallback chain.") }
        prompt += " " + String.localized("This can’t be undone.")
        return prompt
    }
}

/// Client-side echo of clauth's `validate_profile_name`, so the pane rejects
/// exactly the names the CLI would — and a case-insensitive collision, which
/// matters: `clauth login <existing>` re-authenticates that profile rather
/// than refusing (no TTY confirm fires for a non-TTY spawn).
enum ClauthNameValidation {
    static let reservedNames: Set<String> = [
        "daemon", "status", "doctor", "which", "start", "login", "delete", "disable", "enable",
        "fallback", "proxy", "resume", "run", "mcp", "feed", "sessions", "info", "completions", "help",
        "__complete", "mcp-await-job",
    ]

    static func error(_ name: String, existing: [String]) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return String.localized("Enter a name.") }
        if reservedNames.contains(trimmed.lowercased()) {
            return String.localized("\(trimmed) is a clauth command name — pick another.")
        }
        let charsetOK = trimmed.allSatisfy { character in
            if let ascii = character.asciiValue,
               (48...57).contains(ascii) || (65...90).contains(ascii) || (97...122).contains(ascii) {
                return true
            }
            return ["-", "_", ".", "@", "+"].contains(character)
        }
        if !charsetOK || trimmed.hasPrefix(".") {
            return String.localized("Use only letters, digits, '-', '_', '.', '@' or '+', and don’t start with '.'.")
        }
        if existing.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return String.localized("\(trimmed) already exists — re-authenticate that account instead.")
        }
        return nil
    }
}

/// The `claude setup-token` mint a paste has to look like, checked before
/// the CLI re-validates authoritatively. The copy never echoes the value.
enum ClauthSetupToken {
    static func validationError(_ raw: String) -> String? {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if token.isEmpty { return nil }
        if !token.hasPrefix("sk-ant-") { return String.localized("Doesn’t look like a claude setup-token mint (expected sk-ant-…).") }
        if token.contains(where: { $0.isWhitespace }) { return String.localized("The paste contains whitespace — looks partial or padded.") }
        if token.count < 40 { return String.localized("Too short to be a real mint.") }
        return nil
    }

    static func trimmed(_ raw: String) -> String? {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, validationError(raw) == nil else { return nil }
        return token
    }
}
