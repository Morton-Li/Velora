import SwiftUI

struct LinearProgressBar: View {
    let value: Double
    var tint: Color = .accentColor
    var height: CGFloat = 5

    private var clampedValue: Double {
        min(max(value, 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))

                Capsule()
                    .fill(tint)
                    .frame(width: proxy.size.width * clampedValue)
                    .animation(.smooth(duration: 0.32), value: clampedValue)
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progress")
        .accessibilityValue(DownloadFormatters.percent(clampedValue))
    }
}
