import SwiftUI

@main
struct TiltFaceApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

/// Two faces, one above the other: swipe or turn the Digital Crown to switch.
struct RootView: View {
    @AppStorage("face") private var faceRaw: String = FaceKind.physics.rawValue

    var body: some View {
        TabView(selection: $faceRaw) {
            PhysicsFaceView(isSelected: faceRaw == FaceKind.physics.rawValue)
                .tag(FaceKind.physics.rawValue)
            WorldFaceView(isSelected: faceRaw == FaceKind.world.rawValue)
                .tag(FaceKind.world.rawValue)
        }
        .tabViewStyle(.verticalPage)
        .ignoresSafeArea()
        .onAppear {
            if let demo = MotionHub.shared.demo { faceRaw = demo.face.rawValue }
        }
    }
}
