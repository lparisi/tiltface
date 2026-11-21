import SpriteKit
import simd

/// The World face dial: one sprite covering the screen, drawn by WorldDial.fsh from two data textures.
final class WorldDialScene: SKScene {
    /// Texture size in texels (see tools/textures/gen_world_dial.py).
    static let texSize = CGSize(width: 432, height: 528)

    /// When set, the lights stay put (Always On / dimmed screen).
    var frozen = false

    private var dial = SKSpriteNode(color: .black, size: WorldDialScene.texSize)
    private let gravityUniform = SKUniform(name: "u_gravity", vectorFloat3: vector_float3(0, -0.5, -0.866))
    private let viewUniform = SKUniform(name: "u_view", vectorFloat2: vector_float2(432, 528))
    private var built = false

    /// Points per texel for the current screen (aspect fill), shared with the SwiftUI overlay.
    static func scale(for size: CGSize) -> CGFloat {
        max(size.width / texSize.width, size.height / texSize.height)
    }

    override func sceneDidLoad() {
        super.sceneDidLoad()
        build()
    }

    private func build() {
        guard !built else { return }
        built = true
        backgroundColor = .black

        let metal = SKTexture(imageNamed: "world_metal")
        let mat = SKTexture(imageNamed: "world_mat")
        metal.filteringMode = .linear
        mat.filteringMode = .linear
        // A textured sprite guarantees v_tex_coord; if the shader ever fails, the raw map shows instead of black.
        dial = SKSpriteNode(texture: metal, size: Self.texSize)
        NSLog("WorldDial: textures %@ %@", "\(metal.size())", "\(mat.size())")

        let shader = SKShader(fileNamed: "WorldDial.fsh")
        shader.uniforms = [
            SKUniform(name: "u_metal", texture: metal),
            SKUniform(name: "u_mat", texture: mat),
            gravityUniform,
            SKUniform(name: "u_tex", vectorFloat2: vector_float2(Float(Self.texSize.width), Float(Self.texSize.height))),
            viewUniform,
        ]
        dial.shader = shader
        addChild(dial)
        layoutDial()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        build()
        layoutDial()
    }

    private func layoutDial() {
        guard size.width > 0, size.height > 0 else { return }
        let s = Self.scale(for: size)
        dial.size = CGSize(width: Self.texSize.width * s, height: Self.texSize.height * s)
        dial.position = CGPoint(x: size.width / 2, y: size.height / 2)
        viewUniform.vectorFloat2Value = vector_float2(Float(size.width / s), Float(size.height / s))
    }

    override func update(_ currentTime: TimeInterval) {
        build()
        let g = frozen ? MotionHub.restingPose : MotionHub.shared.gravity()
        let n = simd_normalize(g)
        gravityUniform.vectorFloat3Value = vector_float3(Float(n.x), Float(n.y), Float(n.z))
    }
}
