import Foundation
import TimerCore

/// Both languages live next to each other at the call site. No key files and
/// no lookup that can silently miss: a missing translation is a compile error,
/// and the German text stays readable where it is used — which matters in a
/// codebase whose comments explain the German wording.
///
/// The resolved language is a process-wide value because it changes at most
/// once per session, from one place in the settings.
enum L10n {
    private(set) static var current: Language = .english

    /// Reads the setting plus what macOS reports. Called at launch and again
    /// whenever the setting changes.
    static func refresh(preferences: Preferences) {
        current = AppLanguage.resolve(
            preferred: preferences.language,
            systemCode: Locale.preferredLanguages.first
        )
    }

    /// Locale for date and number formatting, so month and weekday names
    /// follow the interface rather than the system.
    static var locale: Locale {
        Locale(identifier: current == .german ? "de_DE" : "en_US")
    }
}

/// The one translation primitive: German first, English second.
func tr(_ de: String, _ en: String) -> String {
    L10n.current == .german ? de : en
}
