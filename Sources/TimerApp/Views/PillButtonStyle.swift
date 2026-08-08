import SwiftUI

/// Quiet capsule button for the running and finished popover states (v6):
/// 11 pt medium label, 7×14 padding, slightly darker fill while pressed.
struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .padding(.vertical, 7)
            .padding(.horizontal, 14)
            .background(
                Capsule().fill(Color.primary.opacity(configuration.isPressed ? 0.14 : 0.07))
            )
            .contentShape(Capsule())
    }
}
