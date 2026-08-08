import SwiftUI

/// Shared app-color palette for the activity views. A rank index (0 = most
/// used) picks the color; everything past the palette shares the last, muted
/// entry. Day views rank per day, the week view ranks over the whole week
/// (WeekRanking) so an app keeps one color across all seven rows.
enum ActivityPalette {
    static let colors: [Color] = [
        Color(red: 0.50, green: 0.47, blue: 0.87),
        Color(red: 0.36, green: 0.79, blue: 0.65),
        Color(red: 0.94, green: 0.60, blue: 0.48),
        Color(red: 0.83, green: 0.33, blue: 0.49),
        Color(red: 0.22, green: 0.54, blue: 0.87),
        Color(red: 0.59, green: 0.77, blue: 0.35),
        Color(red: 0.94, green: 0.62, blue: 0.15),
        Color(red: 0.53, green: 0.53, blue: 0.50),
    ]

    static func color(rank: Int) -> Color {
        colors[min(max(rank, 0), colors.count - 1)]
    }
}
