import SwiftUI
import SpriteKit
import WatchKit

/// Face 1: a full-screen SpriteKit physics scene with the time drawn on top.
struct PhysicsFaceView: View {
    let isSelected: Bool

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
    @State private var motionOn = false
    @State private var demoStyle: SpriteStyle?

    private var style: SpriteStyle { demoStyle ?? SpriteStyle(rawValue: styleRaw) ?? .tennis }
    private var isLive: Bool { isSelected && scenePhase == .active && !isLuminanceReduced }

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
            MotionHub.shared.flipTilt = flipTilt
            if MotionHub.shared.demo?.face == .physics { demoStyle = .tennis }
            applyStyle()
            updateMotion()
        }
        .onDisappear { setMotion(false) }
        .onChange(of: styleRaw) { applyStyle() }
        .onChange(of: demoStyle) { applyStyle() }
        .onChange(of: flipTilt) { _, newValue in MotionHub.shared.flipTilt = newValue }
        .onChange(of: isLive) { updateMotion() }
        .task { await runDemo() }
    }

    private func applyStyle() {
        scene.setStyle(style, texture: SpriteFactory.texture(for: style))
    }

    /// Only run the motion sensors while the face is actually visible and awake.
    private func updateMotion() { setMotion(isLive) }

    private func setMotion(_ on: Bool) {
        guard on != motionOn else { return }
        motionOn = on
        if on { MotionHub.shared.start() } else { MotionHub.shared.stop() }
    }

    /// Recording script: shakes and sprite changes at fixed times (`-demoFace physics`).
    private func runDemo() async {
        guard let demo = MotionHub.shared.demo, demo.face == .physics else { return }
        let steps: [(Double, () -> Void)] = [
            (5.5, { scene.shake() }),
            (7.0, { demoStyle = .gold }),
            (11.0, { scene.shake() }),
            (12.5, { demoStyle = .diamond }),
            (16.0, { scene.shake() }),
            (17.5, { demoStyle = .basketball }),
            (21.0, { scene.shake() }),
        ]
        for (time, action) in steps {
            let wait = time - demo.elapsed()
            if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
            if Task.isCancelled { return }
            action()
        }
    }
}
