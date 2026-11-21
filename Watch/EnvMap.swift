import UIKit
import simd

/// CPU reader of Dial/world_env.png (three stacked, log-encoded equirect maps), so SwiftUI parts such as the
/// hands reflect the same environment as the shader-drawn dial. Same mapping as envLookup in WorldDial.fsh.
final class EnvMap {
    static let shared = EnvMap()

    private let width = 256
    private let height = 384
    private var pixels: [UInt8] = []

    private init() {
        guard let image = UIImage(named: "world_env")?.cgImage else { return }
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        buffer.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        pixels = buffer
    }

    /// Radiance in direction r (screen space). level 0 sharp, 1 satin, 2 soft.
    func radiance(_ r: SIMD3<Double>, lights: Lighting.Lights, level: Int) -> SIMD3<Double> {
        guard !pixels.isEmpty else { return SIMD3(repeating: 0.6) }
        let x = simd_dot(r, lights.fill)
        let y = simd_dot(r, lights.up)
        let z = simd_dot(r, lights.key)
        var u = atan2(x, z) / (2 * .pi) + 0.5 + 0.10
        u -= floor(u)
        let v = min(max(acos(min(max(y, -1), 1)) / .pi, 0.5 / 128), 1 - 0.5 / 128)
        let fx = u * Double(width) - 0.5
        let fy = (Double(level) + v) * 128 - 0.5
        let x0 = Int(floor(fx)), y0 = Int(floor(fy))
        let tx = fx - Double(x0), ty = fy - Double(y0)
        func texel(_ xi: Int, _ yi: Int) -> SIMD3<Double> {
            let xw = ((xi % width) + width) % width
            let yc = min(max(yi, 0), height - 1)
            let i = (yc * width + xw) * 4
            return SIMD3(Double(pixels[i]), Double(pixels[i + 1]), Double(pixels[i + 2])) / 255
        }
        let a = texel(x0, y0) * (1 - tx) + texel(x0 + 1, y0) * tx
        let b = texel(x0, y0 + 1) * (1 - tx) + texel(x0 + 1, y0 + 1) * tx
        let c = a * (1 - ty) + b * ty
        let l2 = 8.0056   // log2(1 + 256)
        return SIMD3(exp2(c.x * l2) - 1, exp2(c.y * l2) - 1, exp2(c.z * l2) - 1)
    }
}
