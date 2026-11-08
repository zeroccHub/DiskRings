import Foundation

/// Picks the UI language from the system's preferred languages.
/// Any Chinese variant (zh-Hans, zh-CN, zh-SG, and also zh-Hant / zh-TW /
/// zh-HK / zh-MO, since only Simplified Chinese is shipped and it is far more
/// readable for those users than English) maps to "zh-Hans"; English variants
/// map to "en"; otherwise the first preferred language that the app has, else
/// "en".
public enum AppLanguage {
    public static func pick(preferred: [String], available: [String]) -> String {
        let avail = Set(available)
        for raw in preferred {
            let tag = raw.replacingOccurrences(of: "_", with: "-").lowercased()
            let base = tag.split(separator: "-").first.map(String.init) ?? tag
            if base == "zh", avail.contains("zh-Hans") { return "zh-Hans" }
            if base == "en" { return "en" }
            if let exact = available.first(where: { $0.lowercased() == tag || $0.lowercased() == base }), exact != "Base" { return exact }
        }
        return "en"
    }
}
