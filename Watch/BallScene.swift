import SpriteKit
import CoreMotion
import WatchKit

/// Physics scene: 40 pieces inside an edge loop, with gravity driven by wrist tilt.
final class BallScene: SKScene {
    let pieceCount = 40

    /// Manual override in case tilt feels inverted on a given wrist/crown setup.
    var flipTilt = false

    private let motion = CMMotionManager()
    private var crownOnLeft = false
    private var smoothedGravity = CGVector(dx: 0, dy: -1)
    private let gravityStrength: CGFloat = 9.8 * 1.6   // a bit stronger than real life feels snappier
    private let smoothing: CGFloat = 0.35              // low-pass filter on the sensor

    private var style: SpriteStyle = .tennis
    private var texture: SKTexture?
    private var pieces: [(node: SKSpriteNode, scale: CGFloat)] = []
    private var hasPoured = false
    private var lastUnit: CGFloat = 0

    /// Base size of a piece, relative to the screen (radius of a tennis ball).
    private var unit: CGFloat { min(size.width, size.height) * 0.055 }

    // MARK: - Public API

    func setStyle(_ newStyle: SpriteStyle, texture newTexture: SKTexture) {
        style = newStyle
        texture = newTexture
        for piece in pieces {
            restyle(piece.node, scale: piece.scale, pop: true)
        }
    }

    func startMotion() {
        crownOnLeft = WKInterfaceDevice.current().crownOrientation == .left
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 60.0   // 60 Hz
        motion.startDeviceMotionUpdates()                // pulled every frame in update(_:)
    }

    func stopMotion() {
        if motion.isDeviceMotionActive {
            motion.stopDeviceMotionUpdates()
        }
    }

    /// Tap to throw everything "up" (against the current gravity).
    func shake() {
        let g = physicsWorld.gravity
        let length = hypot(g.dx, g.dy)
        let up = length > 1 ? CGVector(dx: -g.dx / length, dy: -g.dy / length) : CGVector(dx: 0, dy: 1)

        for piece in pieces {
            guard let body = piece.node.physicsBody else { continue }
            body.isResting = false
            let kick = CGFloat.random(in: 180...320)
            let side = CGFloat.random(in: -120...120)
            body.velocity = CGVector(
                dx: body.velocity.dx + up.dx * kick + up.dy * side,
                dy: body.velocity.dy + up.dy * kick - up.dx * side
            )
            body.angularVelocity += .random(in: -8...8)
        }
    }

    // MARK: - Scene lifecycle

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        guard size.width > 0, size.height > 0 else { return }
        rebuildBoundary()

        if abs(unit - lastUnit) > 0.5 {
            lastUnit = unit
            for piece in pieces {
                restyle(piece.node, scale: piece.scale, pop: false)
            }
        }
        keepPiecesInside()
    }

    override func update(_ currentTime: TimeInterval) {
        if !hasPoured, texture != nil, size.width > 0 {
            hasPoured = true
            lastUnit = unit
            rebuildBoundary()
            pour()
        }
        updateGravity()
        keepPiecesInside()
    }

    // MARK: - Gravity

    private func updateGravity() {
        var target = CGVector(dx: 0, dy: -1)   // simulator / no sensor: plain "down"

        if let gravity = motion.deviceMotion?.gravity {
            // With the crown on the left the screen is rotated 180°, so flip both axes.
            let sign: CGFloat = (crownOnLeft != flipTilt) ? -1 : 1
            target = CGVector(dx: CGFloat(gravity.x) * sign, dy: CGFloat(gravity.y) * sign)
        }

        smoothedGravity.dx += (target.dx - smoothedGravity.dx) * smoothing
        smoothedGravity.dy += (target.dy - smoothedGravity.dy) * smoothing

        let newGravity = CGVector(dx: smoothedGravity.dx * gravityStrength,
                                  dy: smoothedGravity.dy * gravityStrength)
        let delta = hypot(newGravity.dx - physicsWorld.gravity.dx,
                          newGravity.dy - physicsWorld.gravity.dy)
        physicsWorld.gravity = newGravity

        // Sleeping bodies ignore gravity changes, so wake them when the wrist moves.
        if delta > 0.05 {
            for piece in pieces {
                piece.node.physicsBody?.isResting = false
            }
        }
    }

    // MARK: - Pieces

    /// Pour the pieces in one by one for a nicer launch.
    private func pour() {
        let spawn = SKAction.run { [weak self] in self?.spawnPiece() }
        let wait = SKAction.wait(forDuration: 0.035)
        run(.repeat(.sequence([spawn, wait]), count: pieceCount), withKey: "pour")
    }

    private func spawnPiece() {
        guard let texture else { return }
        let scale = CGFloat.random(in: 0.88...1.08)
        let nodeSize = style.nodeSize(unit: unit * scale)

        let node = SKSpriteNode(texture: texture, size: nodeSize)
        node.position = CGPoint(
            x: size.width / 2 + .random(in: -size.width * 0.2...size.width * 0.2),
            y: size.height / 2 + .random(in: -8...8)
        )
        node.zRotation = .random(in: 0..<(.pi * 2))

        let body = style.makeBody(size: nodeSize)
        body.velocity = CGVector(dx: .random(in: -60...60), dy: .random(in: -60...60))
        node.physicsBody = body

        node.setScale(0.2)
        node.run(.scale(to: 1, duration: 0.2))

        addChild(node)
        pieces.append((node, scale))
    }

    /// Swap texture + physics body in place, keeping position and momentum.
    private func restyle(_ node: SKSpriteNode, scale: CGFloat, pop: Bool) {
        let velocity = node.physicsBody?.velocity ?? .zero
        let spin = node.physicsBody?.angularVelocity ?? 0
        let newSize = style.nodeSize(unit: unit * scale)

        if let texture { node.texture = texture }
        node.size = newSize

        let body = style.makeBody(size: newSize)
        body.velocity = velocity
        body.angularVelocity = spin
        node.physicsBody = body

        if pop {
            node.removeAction(forKey: "pop")
            node.setScale(0.6)
            node.run(.scale(to: 1, duration: 0.18), withKey: "pop")
        }
    }

    // MARK: - Bounds

    /// Edge loop around the screen, with rounded corners to match the watch display.
    private func rebuildBoundary() {
        let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
        let radius = min(rect.width, rect.height) * 0.2
        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        let edge = SKPhysicsBody(edgeLoopFrom: path)
        edge.friction = 0.3
        edge.restitution = 0
        physicsBody = edge
    }

    /// Safety net: anything that tunnels out gets put back in the middle.
    private func keepPiecesInside() {
        guard size.width > 0 else { return }
        let limits = CGRect(origin: .zero, size: size).insetBy(dx: -30, dy: -30)
        for piece in pieces where !limits.contains(piece.node.position) {
            piece.node.position = CGPoint(x: size.width / 2, y: size.height / 2)
            piece.node.physicsBody?.velocity = .zero
        }
    }
}
