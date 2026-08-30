import Foundation

/// Which language the interface speaks. The app ships German and English side
/// by side; "system" is the default and simply follows macOS, so a German Mac
/// gets German and everyone else English — the explicit choice exists for the
/// cases where that guess is wrong (a German user on an English system, or a
/// shared machine).
public enum AppLanguage: String, CaseIterable {
    case system
    case german = "de"
    case english = "en"
}

/// The two languages actually rendered. Kept apart from `AppLanguage` so that
/// "system" can never leak into the rendering path.
public enum Language: String, Equatable {
    case german
    case english
}

public extension AppLanguage {
    /// What to render, given the setting and what macOS reports.
    ///
    /// Only German is matched explicitly; everything else falls to English,
    /// which is the better guess for a language nobody translated.
    static func resolve(preferred: AppLanguage, systemCode: String?) -> Language {
        switch preferred {
        case .german: return .german
        case .english: return .english
        case .system:
            let code = (systemCode ?? "en").prefix(2).lowercased()
            return code == "de" ? .german : .english
        }
    }
}
