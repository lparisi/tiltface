import SwiftUI

/// Date + time in a large rounded font, drawn over the physics scene.
struct FaceOverlay: View {
    let accent: Color
    let dimmed: Bool

    var body: some View {
        TimelineView(.everyMinute) { context in
            VStack(spacing: -6) {
                Text(context.date, format: .dateTime.weekday(.abbreviated).day())
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .textCase(.uppercase)
                    .foregroundStyle(accent)

                Text(context.date.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute()))
                    .font(.system(size: 58, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .shadow(color: .black.opacity(0.75), radius: 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 26)
        }
        .opacity(dimmed ? 0.6 : 1)
    }
}
