import SwiftUI

enum AppTheme {
    static let windowBackground = LinearGradient(
        colors: [
            Color(nsColor: .windowBackgroundColor),
            Color(nsColor: .controlBackgroundColor).opacity(0.92)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    static let hairline = Color.primary.opacity(0.08)
    static let subtleFill = Color.primary.opacity(0.045)
    static let selectedFill = Color.accentColor.opacity(0.12)
}
