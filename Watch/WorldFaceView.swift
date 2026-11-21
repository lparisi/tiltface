import SwiftUI
import SpriteKit
import simd

/// Face 2: a domed globe of stamped rose gold under blue lacquer, lit by the room as the wrist turns.
/// The dial is a SpriteKit shader (WorldDial.fsh); hands, cap and second time zone are SwiftUI, shaded with the same lights.
struct WorldFaceView: View {
    let isSelected: Bool

    @AppStorage("homeZone") private var homeZone: String = HomeZone.defaultID
    @AppStorage("flipTilt") private var flipTilt: Bool = false

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    @State private var scene: WorldDialScene = {
        let scene = WorldDialScene(size: CGSize(width: 208, height: 248))
        scene.scaleMode = .resizeFill
        return scene
    }()
    @State private var showingSettings = false
    @State private var motionOn = false

    private var isLive: Bool { isSelected && scenePhase == .active && !isLuminanceReduced }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                SpriteView(scene: scene, isPaused: !isSelected, preferredFramesPerSecond: isLuminanceReduced ? 1 : 30)

                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isLive)) { context in
                    let g = isLuminanceReduced ? MotionHub.restingPose : MotionHub.shared.gravity(at: context.date)
                    WorldDialOverlay(date: context.date, gravity: g, size: geo.size, zone: HomeZone.find(homeZone))
                }
                .allowsHitTesting(false)

                if isLuminanceReduced {
                    Color.black.opacity(0.5)
                }
            }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.6) {
            showingSettings = true
        }
        .sheet(isPresented: $showingSettings) {
            WorldSettingsView(homeZone: $homeZone, flipTilt: $flipTilt)
        }
        .onAppear {
            MotionHub.shared.flipTilt = flipTilt
            scene.frozen = isLuminanceReduced
            setMotion(isLive)
        }
        .onDisappear { setMotion(false) }
        .onChange(of: isLive) { setMotion(isLive) }
        .onChange(of: isLuminanceReduced) { _, dimmed in scene.frozen = dimmed }
    }

    private func setMotion(_ on: Bool) {
        guard on != motionOn else { return }
        motionOn = on
        if on { MotionHub.shared.start() } else { MotionHub.shared.stop() }
    }
}

// MARK: - Overlay: hands, centre cap, second time zone

private struct WorldDialOverlay: View {
    let date: Date
    let gravity: SIMD3<Double>
    let size: CGSize
    let zone: HomeZone

    var body: some View {
        let s = WorldDialScene.scale(for: size)
        let R = 0.43 * WorldDialScene.texSize.width * s        // globe radius in points
        let lights = Lighting.lights(gravity)
        let shadow = CGSize(width: -lights.key.x * 3.2, height: -lights.key.y * 3.2)
        let parts = Calendar.current.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        let seconds = Double(parts.second ?? 0) + Double(parts.nanosecond ?? 0) / 1e9
        let minutes = Double(parts.minute ?? 0) + seconds / 60
        let hours = Double((parts.hour ?? 0) % 12) + minutes / 60

        ZStack {
            // Second time zone, engraved in rose gold below 6 o'clock.
            HomeTimeLabel(date: date, zone: zone, lights: lights)
                .position(x: size.width / 2, y: size.height / 2 + 229 * s)

            DauphineHand(length: R * 0.56, width: R * 0.105, tail: R * 0.13,
                         angle: .degrees(hours * 30), lights: lights)
                .shadow(color: .black.opacity(0.55), radius: 1.6, x: shadow.width, y: shadow.height)
            DauphineHand(length: R * 0.90, width: R * 0.08, tail: R * 0.15,
                         angle: .degrees(minutes * 6), lights: lights)
                .shadow(color: .black.opacity(0.55), radius: 2.0, x: shadow.width * 1.4, y: shadow.height * 1.4)
            CenterCap(radius: R * 0.055, lights: lights)
                .shadow(color: .black.opacity(0.5), radius: 1.2, x: shadow.width, y: shadow.height)
        }
        .frame(width: size.width, height: size.height)
    }
}

/// A faceted dauphine hand: two polished facets meeting on a central ridge, each catching the light differently.
private struct DauphineHand: View {
    let length: CGFloat
    let width: CGFloat
    let tail: CGFloat
    let angle: Angle
    let lights: Lighting.Lights

    var body: some View {
        let a = angle.radians
        // Facet normals in screen space: tilted ±40° across the hand, which points along (sin a, -cos a).
        let across = SIMD3<Double>(cos(a), sin(a), 0)
        let left = simd_normalize(-across * 0.64 + SIMD3(0, 0, 0.77))
        let right = simd_normalize(across * 0.64 + SIMD3(0, 0, 0.77))
        ZStack {
            HandFacet(length: length, width: width, tail: tail, side: -1)
                .fill(Lighting.metalGradient(normal: left, lights: lights))
            HandFacet(length: length, width: width, tail: tail, side: 1)
                .fill(Lighting.metalGradient(normal: right, lights: lights))
        }
        .rotationEffect(angle)
    }
}

private struct HandFacet: Shape {
    let length: CGFloat
    let width: CGFloat
    let tail: CGFloat
    let side: CGFloat

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var p = Path()
        p.move(to: CGPoint(x: c.x, y: c.y - length))                                 // tip
        p.addLine(to: CGPoint(x: c.x + side * width / 2, y: c.y - length * 0.18))     // widest point
        p.addLine(to: CGPoint(x: c.x + side * width * 0.2, y: c.y + tail))            // tail
        p.addLine(to: CGPoint(x: c.x, y: c.y + tail))
        p.closeSubpath()
        return p
    }
}

/// Domed rose-gold cap over the hands' pivot, with a highlight that sits where the dome faces the light.
private struct CenterCap: View {
    let radius: CGFloat
    let lights: Lighting.Lights

    var body: some View {
        let k = lights.key
        let half = simd_normalize(k + SIMD3(0, 0, 1))
        let hx = half.x / max(half.z, 0.3) * 0.7
        let hy = half.y / max(half.z, 0.3) * 0.7
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [Lighting.metalColor(normal: SIMD3(0, 0, 1), lights: lights, boost: 1.6),
                             Lighting.metalColor(normal: simd_normalize(SIMD3(-k.x, -k.y, 0.4)), lights: lights)],
                    center: UnitPoint(x: 0.5 + hx * 0.5, y: 0.5 + hy * 0.5),
                    startRadius: 0, endRadius: radius * 2))
            Circle()
                .stroke(Lighting.metalColor(normal: simd_normalize(SIMD3(k.x, k.y, 0.6)), lights: lights), lineWidth: 0.6)
        }
        .frame(width: radius * 2, height: radius * 2)
    }
}

/// "LONDON 16:54": small engraved capitals in rose gold.
private struct HomeTimeLabel: View {
    let date: Date
    let zone: HomeZone
    let lights: Lighting.Lights

    var body: some View {
        let time = date.formatted(Date.FormatStyle(timeZone: zone.timeZone)
            .hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        HStack(spacing: 4) {
            Text(zone.name.uppercased())
                .font(.system(size: 8, weight: .semibold, design: .serif))
                .tracking(1.2)
            Text(time)
                .font(.system(size: 11, weight: .semibold, design: .serif))
                .monospacedDigit()
        }
        .foregroundStyle(Lighting.metalGradient(normal: simd_normalize(SIMD3(0, -0.25, 1)), lights: lights))
        .shadow(color: .black.opacity(0.6), radius: 0.8, x: 0, y: 0.6)
    }
}

// MARK: - Lighting shared with WorldDial.fsh

enum Lighting {
    struct Lights {
        let up: SIMD3<Double>
        let key: SIMD3<Double>
        let fill: SIMD3<Double>
    }

    static let gold = SIMD3<Double>(1.00, 0.80, 0.55)   // champagne rose gold, as in the shader

    /// Same lights as the shader: "up" is opposite to gravity; screen y points down.
    static func lights(_ g: SIMD3<Double>) -> Lights {
        let up = SIMD3(-g.x, g.y, -g.z)
        return Lights(up: simd_normalize(up),
                      key: simd_normalize(up + SIMD3(-0.30, -0.42, 0)),
                      fill: simd_normalize(up + SIMD3(0.95, 0.10, -0.15)))
    }

    private static func smooth(_ e0: Double, _ e1: Double, _ x: Double) -> Double {
        let t = min(max((x - e0) / (e1 - e0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// Polished rose gold seen straight on, for a surface with this normal (envMetal in WorldDial.fsh).
    static func metalColor(normal n: SIMD3<Double>, lights: Lights, boost: Double = 1.4) -> Color {
        let v = SIMD3<Double>(0, 0, 1)
        let nov = max(simd_dot(n, v), 0.001)
        let r = 2 * nov * n - v
        let t = smooth(-0.3, 0.9, simd_dot(r, lights.up))
        let viewer = 1 - 0.2 * smooth(0.86, 0.99, r.z)   // hands sit higher: less of the viewer in them
        let room = (0.03 + t * t) * viewer
        let k = min(max(simd_dot(r, lights.key), 0), 1)
        let f = min(max(simd_dot(r, lights.fill), 0), 1)
        let e = 8 + (1 - 0.1) * 70.0   // polished hands: sharper than the satin relief
        let env = room + 1.6 * pow(k, e) + 4 * pow(k, e * 5) + 1.1 * pow(f, e * 0.7)
        let fres = gold + (SIMD3<Double>(repeating: 1) - gold) * pow(1 - nov, 5)
        let c = fres * env * boost
        func tone(_ x: Double) -> Double { pow(min(max(1 - exp(-x * 1.2), 0), 1), 1 / 1.15) }
        return Color(red: tone(c.x), green: tone(c.y), blue: tone(c.z))
    }

    /// A facet with a slight curve along its length: brighter toward the tip when lit from there.
    static func metalGradient(normal n: SIMD3<Double>, lights: Lights) -> LinearGradient {
        let tipward = simd_normalize(n + SIMD3(0, -0.12, 0))
        let tailward = simd_normalize(n + SIMD3(0, 0.12, 0))
        return LinearGradient(colors: [metalColor(normal: tipward, lights: lights),
                                       metalColor(normal: tailward, lights: lights)],
                              startPoint: .top, endPoint: .bottom)
    }
}

// MARK: - Second time zone

struct HomeZone: Identifiable, Hashable {
    let id: String
    let name: String

    var timeZone: TimeZone { TimeZone(identifier: id) ?? .gmt }

    static let defaultID = "Europe/London"
    static let all: [HomeZone] = [
        HomeZone(id: "Europe/London", name: "London"),
        HomeZone(id: "America/New_York", name: "New York"),
        HomeZone(id: "America/Los_Angeles", name: "Los Angeles"),
        HomeZone(id: "America/Sao_Paulo", name: "São Paulo"),
        HomeZone(id: "Europe/Lisbon", name: "Lisbon"),
        HomeZone(id: "Europe/Paris", name: "Paris"),
        HomeZone(id: "Asia/Dubai", name: "Dubai"),
        HomeZone(id: "Asia/Singapore", name: "Singapore"),
        HomeZone(id: "Asia/Tokyo", name: "Tokyo"),
        HomeZone(id: "UTC", name: "UTC"),
    ]

    static func find(_ id: String) -> HomeZone {
        all.first { $0.id == id } ?? all[0]
    }
}

struct WorldSettingsView: View {
    @Binding var homeZone: String
    @Binding var flipTilt: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Second time zone") {
                    ForEach(HomeZone.all) { zone in
                        Button {
                            homeZone = zone.id
                            dismiss()
                        } label: {
                            HStack {
                                Text(zone.name)
                                Spacer(minLength: 0)
                                if zone.id == homeZone {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color(red: 1.0, green: 0.78, blue: 0.6))
                                }
                            }
                        }
                    }
                }
                Section {
                    Toggle("Flip tilt", isOn: $flipTilt)
                } footer: {
                    Text("Turn on if the light moves the wrong way. Swipe up or down to change faces.")
                }
            }
            .navigationTitle("World")
        }
    }
}
