import SwiftUI

/// Vector artwork for each sprite. Used both for SpriteKit textures and the settings list.
struct SpriteArtwork: View {
    let style: SpriteStyle

    var body: some View {
        GeometryReader { geo in
            switch style {
            case .tennis:
                TennisBallArt(d: min(geo.size.width, geo.size.height))
            case .basketball:
                BasketballArt(d: min(geo.size.width, geo.size.height))
            case .gold:
                GoldBarArt(size: geo.size)
            case .diamond:
                DiamondArt(size: geo.size)
            }
        }
    }
}

// MARK: - Tennis ball

private struct TennisBallArt: View {
    let d: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(
                RadialGradient(
                    colors: [
                        Color(red: 0.93, green: 1.0, blue: 0.50),
                        Color(red: 0.76, green: 0.90, blue: 0.20),
                        Color(red: 0.52, green: 0.66, blue: 0.08),
                    ],
                    center: UnitPoint(x: 0.35, y: 0.3),
                    startRadius: 0,
                    endRadius: d * 0.8
                )
            )
            seam(offset: -d * 0.82)
            seam(offset: d * 0.82)
            Highlight(d: d)
        }
        .frame(width: d, height: d)
        .clipShape(Circle())
    }

    private func seam(offset: CGFloat) -> some View {
        Circle()
            .stroke(Color.white.opacity(0.95), lineWidth: d * 0.07)
            .frame(width: d * 1.3, height: d * 1.3)
            .offset(x: offset)
    }
}

// MARK: - Basketball

private struct BasketballArt: View {
    let d: CGFloat

    var body: some View {
        let line = Color.black.opacity(0.85)
        let lw = d * 0.045

        ZStack {
            Circle().fill(
                RadialGradient(
                    colors: [
                        Color(red: 1.0, green: 0.62, blue: 0.28),
                        Color(red: 0.90, green: 0.42, blue: 0.10),
                        Color(red: 0.58, green: 0.24, blue: 0.05),
                    ],
                    center: UnitPoint(x: 0.35, y: 0.3),
                    startRadius: 0,
                    endRadius: d * 0.8
                )
            )
            Rectangle().fill(line).frame(width: lw, height: d)
            Rectangle().fill(line).frame(width: d, height: lw)
            Circle()
                .stroke(line, lineWidth: lw)
                .frame(width: d * 1.1, height: d * 1.1)
                .offset(x: -d * 0.78)
            Circle()
                .stroke(line, lineWidth: lw)
                .frame(width: d * 1.1, height: d * 1.1)
                .offset(x: d * 0.78)
            Highlight(d: d)
        }
        .frame(width: d, height: d)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.black.opacity(0.45), lineWidth: lw * 0.8))
    }
}

// MARK: - Gold bar

private struct GoldBarArt: View {
    let size: CGSize

    var body: some View {
        let h = size.height
        let edge = Color(red: 0.55, green: 0.37, blue: 0.05)

        ZStack {
            Trapezoid().fill(
                LinearGradient(
                    colors: [
                        Color(red: 1.0, green: 0.90, blue: 0.50),
                        Color(red: 0.95, green: 0.73, blue: 0.20),
                        Color(red: 0.70, green: 0.50, blue: 0.10),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            Trapezoid().fill(
                LinearGradient(
                    colors: [Color.white.opacity(0.5), .clear],
                    startPoint: .top,
                    endPoint: UnitPoint(x: 0.5, y: 0.5)
                )
            )
            RoundedRectangle(cornerRadius: h * 0.08)
                .stroke(edge.opacity(0.7), lineWidth: h * 0.06)
                .frame(width: size.width * 0.4, height: h * 0.4)
                .offset(y: h * 0.1)
            Trapezoid().stroke(edge, lineWidth: h * 0.06)
        }
        .frame(width: size.width, height: size.height)
    }
}

// MARK: - Diamond

private struct DiamondArt: View {
    let size: CGSize

    var body: some View {
        let w = size.width

        ZStack {
            GemShape().fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.88, green: 0.98, blue: 1.0),
                        Color(red: 0.45, green: 0.80, blue: 0.98),
                        Color(red: 0.20, green: 0.48, blue: 0.85),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            GemFacets().stroke(Color.white.opacity(0.7), lineWidth: w * 0.025)
            GemShape().stroke(Color.white.opacity(0.9), lineWidth: w * 0.035)
            Circle()
                .fill(Color.white.opacity(0.85))
                .frame(width: w * 0.1, height: w * 0.1)
                .offset(x: -w * 0.18, y: -size.height * 0.28)
                .blur(radius: w * 0.02)
        }
        .frame(width: size.width, height: size.height)
    }
}

// MARK: - Shapes

private struct Highlight: View {
    let d: CGFloat

    var body: some View {
        Circle().fill(
            RadialGradient(
                colors: [Color.white.opacity(0.35), .clear],
                center: UnitPoint(x: 0.3, y: 0.25),
                startRadius: 0,
                endRadius: d * 0.45
            )
        )
    }
}

struct Trapezoid: Shape {
    var topInset: CGFloat = 0.15

    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + r.width * topInset, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - r.width * topInset, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

struct GemShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + r.width * 0.2, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.8, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.35))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.35))
        p.closeSubpath()
        return p
    }
}

struct GemFacets: Shape {
    func path(in r: CGRect) -> Path {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: r.minX + r.width * x, y: r.minY + r.height * y)
        }
        var p = Path()
        // Girdle
        p.move(to: pt(0, 0.35)); p.addLine(to: pt(1, 0.35))
        // Crown
        p.move(to: pt(0.2, 0)); p.addLine(to: pt(0.35, 0.35))
        p.move(to: pt(0.5, 0)); p.addLine(to: pt(0.35, 0.35))
        p.move(to: pt(0.5, 0)); p.addLine(to: pt(0.65, 0.35))
        p.move(to: pt(0.8, 0)); p.addLine(to: pt(0.65, 0.35))
        // Pavilion
        p.move(to: pt(0.35, 0.35)); p.addLine(to: pt(0.5, 1))
        p.move(to: pt(0.65, 0.35)); p.addLine(to: pt(0.5, 1))
        return p
    }
}
