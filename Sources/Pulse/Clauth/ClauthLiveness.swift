import Foundation

/// Graded daemon freshness. The daemon rewrites `status.json` every ~1s, so
/// the file's age is a direct liveness signal — keyed to that fixed cadence,
/// never to `refresh_interval_ms` (the ~90s usage refetch): a dead daemon
/// must read dead in seconds, not minutes. Port of ccsbar `LivenessLadder`.
enum ClauthLiveness {
    enum Freshness: Equatable, Sendable {
        /// Ticking normally (< 5s).
        case live
        /// A momentary stall, such as a switch's Keychain rewrite (5–15s).
        case syncing
        /// It stopped ticking (≥ 15s).
        case dead
    }

    static func freshness(ageSeconds: Double) -> Freshness {
        if ageSeconds < 5 { return .live }
        if ageSeconds < 15 { return .syncing }
        return .dead
    }

    /// The YOUNGER of `generated_at`'s age and the file mtime's age is the
    /// evidence of life: a fresh mtime beside an unparseable or skewed
    /// `generated_at` (or the reverse) still means the daemon is writing.
    /// Both unknown reads as dead.
    static func freshness(generatedAtAge: Double?, statusMtimeAge: Double?) -> Freshness {
        let ages = [generatedAtAge, statusMtimeAge].compactMap { $0 }
        guard let youngest = ages.min() else { return .dead }
        return freshness(ageSeconds: youngest)
    }
}
