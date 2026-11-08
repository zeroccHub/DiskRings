import XCTest
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Wall-clock budgets are meaningful only without instrumentation. Under
/// `swift test --sanitize=thread` every memory access is ~5–15× slower, so the
/// budgets are scaled (not skipped) to still catch order-of-magnitude regressions.
enum TimingBudget {
    static let underThreadSanitizer: Bool = {
        guard let h = dlopen(nil, RTLD_NOW) else { return false }
        return dlsym(h, "__tsan_init") != nil
    }()
    /// Budgets are RELEASE targets (the app ships -O). Unoptimised debug test builds are
    /// measured 2–3× slower on the same code (rebuild 2.4 ms release vs 5–7 ms debug), so debug
    /// runs get ×2. Heavy runs (`-c release`) stay at ×1.
    static let debugFactor: Double = {
        #if DEBUG
        return 2
        #else
        return 1
        #endif
    }()
    static func scaled(_ seconds: Double) -> Double { (underThreadSanitizer ? seconds * 20 : seconds) * debugFactor }

    /// Percentile (nearest rank) of wall-clock samples.
    static func percentile(_ xs: [Double], _ p: Double) -> Double {
        precondition(!xs.isEmpty)
        let s = xs.sorted()
        return s[min(s.count - 1, max(0, Int((p * Double(s.count)).rounded(.up)) - 1))]
    }

    /// Flake-free budget check: a single preempted sample (scheduler/page-fault spike, seen as
    /// 17 ms vs a 2–3 ms median) must not fail the run, a real regression must. Asserts
    /// p95 < budget and max < 6 × budget (gross regressions / hangs). Prints p50/p95/max.
    static func check(_ xs: [Double], budget: Double, _ label: String, p: Double = 0.95,
                      file: StaticString = #filePath, line: UInt = #line) -> String {
        let b = scaled(budget), pv = percentile(xs, p), mx = xs.max()!
        let msg = String(format: "%@: n=%d p50=%.2fms p%.0f=%.2fms max=%.2fms (budget %.1fms)", label, xs.count,
                         percentile(xs, 0.5) * 1000, p * 100, pv * 1000, mx * 1000, b * 1000)
        if !(pv < b) { failTiming(msg + " — percentile over budget", file: file, line: line) }
        if !(mx < 6 * b) { failTiming(msg + " — max over 6× budget", file: file, line: line) }
        return msg
    }
}

private func failTiming(_ m: String, file: StaticString, line: UInt) { XCTFail(m, file: file, line: line) }
