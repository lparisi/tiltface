import CoreMotion
import Foundation
import WatchKit
import simd

/// One CoreMotion reader for the whole app. Faces pull a smoothed gravity vector every frame.
/// Gravity is in the watch's frame: x toward 3 o'clock, y toward 12 o'clock, z out of the screen, in g.
final class MotionHub {
    static let shared = MotionHub()

    /// Manual override in case tilt feels inverted on a given wrist / crown setup.
    var flipTilt = false

    let demo = DemoScript.current

    private let manager = CMMotionManager()
    private var clients = 0
    private var crownOnLeft = false
    private var smoothed = SIMD3<Double>(0, -0.5, -0.866)
    private var lastTime: Date?

    /// Watch held up to be read: what we use when there is no sensor (simulator) or the screen is dimmed.
    static let restingPose = SIMD3<Double>(0, -0.5, -0.866)

    func start() {
        clients += 1
        crownOnLeft = WKInterfaceDevice.current().crownOrientation == .left
        guard demo == nil, manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        manager.startDeviceMotionUpdates()
    }

    func stop() {
        clients = max(0, clients - 1)
        if clients == 0, manager.isDeviceMotionActive {
            manager.stopDeviceMotionUpdates()
        }
    }

    /// Smoothed gravity. Several callers in the same frame get the same value.
    func gravity(at date: Date = Date()) -> SIMD3<Double> {
        let target = rawGravity(at: date)
        let dt = lastTime.map { max(0, date.timeIntervalSince($0)) } ?? 1
        lastTime = date
        let a = 1 - exp(-dt / 0.07)
        smoothed += (target - smoothed) * a
        return smoothed
    }

    private func rawGravity(at date: Date) -> SIMD3<Double> {
        if let demo { return demo.gravity(at: date) }
        if let g = manager.deviceMotion?.gravity {
            // With the crown on the left the screen is rotated 180°, so flip x and y.
            let s: Double = (crownOnLeft != flipTilt) ? -1 : 1
            return SIMD3(g.x * s, g.y * s, g.z)
        }
        return Self.restingPose
    }
}

/// Scripted wrist motion for screen recordings, enabled with the launch argument `-demoFace physics|world`.
struct DemoScript {
    let face: FaceKind
    let start = Date()

    static let current: DemoScript? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-demoFace"), i + 1 < args.count,
              let face = FaceKind(rawValue: args[i + 1]) else { return nil }
        return DemoScript(face: face)
    }()

    func elapsed(_ date: Date = Date()) -> Double { date.timeIntervalSince(start) }

    func gravity(at date: Date) -> SIMD3<Double> {
        let t = elapsed(date)
        switch face {
        case .physics:
            // Upright while the pieces pour in, then the wrist rolls round in slow circles.
            if t < 3 { return simd_normalize(SIMD3(0, -1, -0.2)) }
            let a = (t - 3) * 0.8
            let m = 0.85 + 0.15 * sin(t * 0.7)
            return simd_normalize(SIMD3(sin(a) * m, -cos(a) * m, -0.35))
        case .world:
            // A slow figure-of-eight, like turning the wrist under a lamp.
            let x = 0.42 * sin(t * 0.75)
            let y = -0.45 + 0.32 * sin(t * 1.1 + 0.8)
            return simd_normalize(SIMD3(x, y, -0.85))
        }
    }
}

enum FaceKind: String, CaseIterable, Identifiable {
    case physics
    case world

    var id: String { rawValue }
}
