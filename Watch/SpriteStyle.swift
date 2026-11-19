import SwiftUI
import SpriteKit

/// The four sprite sets, with their sizes and physics shapes.
enum SpriteStyle: String, CaseIterable, Identifiable {
    case tennis
    case gold
    case diamond
    case basketball

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tennis: return "Tennis balls"
        case .gold: return "Gold bars"
        case .diamond: return "Diamonds"
        case .basketball: return "Basketballs"
        }
    }

    var accent: Color {
        switch self {
        case .tennis: return Color(red: 0.86, green: 1.0, blue: 0.36)
        case .gold: return Color(red: 1.0, green: 0.80, blue: 0.30)
        case .diamond: return Color(red: 0.55, green: 0.88, blue: 1.0)
        case .basketball: return Color(red: 1.0, green: 0.55, blue: 0.20)
        }
    }

    /// Restitution 0.4 as specced; gold bars land with more of a thud.
    var restitution: CGFloat {
        self == .gold ? 0.15 : 0.4
    }

    /// Size of one piece, where `unit` is roughly a tennis-ball radius.
    func nodeSize(unit u: CGFloat) -> CGSize {
        switch self {
        case .tennis: return CGSize(width: 2.0 * u, height: 2.0 * u)
        case .basketball: return CGSize(width: 2.4 * u, height: 2.4 * u)
        case .gold: return CGSize(width: 2.5 * u, height: 1.2 * u)
        case .diamond: return CGSize(width: 2.1 * u, height: 1.8 * u)
        }
    }

    /// Physics body matching the drawn silhouette (SpriteKit coords, origin at center, y up).
    func makeBody(size: CGSize) -> SKPhysicsBody {
        let w = size.width
        let h = size.height
        let body: SKPhysicsBody

        switch self {
        case .tennis, .basketball:
            body = SKPhysicsBody(circleOfRadius: w / 2)

        case .gold:
            // Trapezoid ingot, narrower on top. Counter-clockwise, convex.
            body = SKPhysicsBody(polygonFrom: Self.polygon([
                CGPoint(x: -w / 2, y: -h / 2),
                CGPoint(x: w / 2, y: -h / 2),
                CGPoint(x: w * 0.35, y: h / 2),
                CGPoint(x: -w * 0.35, y: h / 2),
            ]))

        case .diamond:
            // Classic gem: flat table, girdle, pointed pavilion. Counter-clockwise, convex.
            body = SKPhysicsBody(polygonFrom: Self.polygon([
                CGPoint(x: 0, y: -h / 2),
                CGPoint(x: w / 2, y: h * 0.15),
                CGPoint(x: w * 0.3, y: h / 2),
                CGPoint(x: -w * 0.3, y: h / 2),
                CGPoint(x: -w / 2, y: h * 0.15),
            ]))
        }

        body.restitution = restitution
        body.friction = 0.3
        body.linearDamping = 0.1
        body.angularDamping = 0.35
        body.allowsRotation = true
        return body
    }

    private static func polygon(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: points)
        path.closeSubpath()
        return path
    }
}

/// Renders the SwiftUI artwork into SpriteKit textures (no image assets needed).
@MainActor
enum SpriteFactory {
    private static var cache: [SpriteStyle: SKTexture] = [:]

    static func texture(for style: SpriteStyle) -> SKTexture {
        if let cached = cache[style] { return cached }

        let size = style.nodeSize(unit: 40)
        let renderer = ImageRenderer(
            content: SpriteArtwork(style: style)
                .frame(width: size.width, height: size.height)
        )
        renderer.scale = 2

        let texture: SKTexture
        if let image = renderer.cgImage {
            texture = SKTexture(cgImage: image)
        } else {
            texture = SKTexture()
        }
        cache[style] = texture
        return texture
    }
}
