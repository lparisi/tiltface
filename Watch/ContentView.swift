import SwiftUI
import SpriteKit
import WatchKit

/// The "watch face": a full-screen SpriteKit physics scene with the time drawn on top.
struct ContentView: View {
    @AppStorage("spriteStyle") private var styleRaw: String = SpriteStyle.tennis.rawValue
    @AppStorage("flipTilt") private var flipTilt: Bool = false

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    @State private var scene: BallScene = {
        let scene = BallScene(size: CGSize(width: 198, height: 242))
        scene.scaleMode = .resizeFill
        scene.backgroundColor = .black
        return scene
    }()
    @State private var showingSettings = false

    private var style: SpriteStyle { SpriteStyle(rawValue: styleRaw) ?? .tennis }
    private var isLive: Bool { scenePhase == .active && !isLuminanceReduced }

    var body: some View {
        ZStack {
            SpriteView(scene: scene, isPaused: !isLive, preferredFramesPerSecond: 60)

            if isLuminanceReduced {
                Color.black.opacity(0.45)
            }

            FaceOverlay(accent: style.accent, dimmed: isLuminanceReduced)
                .allowsHitTesting(false)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture {
            scene.shake()
            WKInterfaceDevice.current().play(.click)
        }
        .onLongPressGesture(minimumDuration: 0.6) {
            showingSettings = true
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(styleRaw: $styleRaw, flipTilt: $flipTilt)
        }
        .onAppear {
            scene.flipTilt = flipTilt
            applyStyle()
            updateMotion()
        }
        .onChange(of: styleRaw) { applyStyle() }
        .onChange(of: flipTilt) { _, newValue in scene.flipTilt = newValue }
        .onChange(of: scenePhase) { updateMotion() }
        .onChange(of: isLuminanceReduced) { updateMotion() }
    }

    private func applyStyle() {
        scene.setStyle(style, texture: SpriteFactory.texture(for: style))
    }

    /// Only run the motion sensors while the face is actually visible and awake.
    private func updateMotion() {
        if isLive {
            scene.startMotion()
        } else {
            scene.stopMotion()
        }
    }
}
