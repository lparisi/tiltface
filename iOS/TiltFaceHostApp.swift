import SwiftUI

/// iPhone host. It exists so the watch app can be installed through the paired iPhone
/// (Sideloadly / TestFlight install the iPhone app; watchOS then installs the embedded watch app).
@main
struct TiltFaceHostApp: App {
    var body: some Scene {
        WindowGroup {
            HostView()
        }
    }
}

private struct HostView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "applewatch")
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)
            Text("TiltFace")
                .font(.system(size: 34, weight: .bold, design: .rounded))
            Text("Open TiltFace on your Apple Watch.\nIf it isn't there yet: Watch app on this iPhone → My Watch → Available Apps → TiltFace → Install.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .preferredColorScheme(.dark)
    }
}
