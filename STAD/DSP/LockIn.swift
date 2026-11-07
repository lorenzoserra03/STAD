import Foundation

/// Synchronous (lock-in) detection of a single known frequency.
nonisolated enum LockIn {
    /// Complex peak amplitude of the `frequency` component of `x`, with phase
    /// relative to the first sample. Accurate when `x` spans a whole number of periods.
    static func phasor(_ x: [Float], frequency: Double, sampleRate: Double) -> Complex {
        guard !x.isEmpty else { return .zero }
        let w = 2 * Double.pi * frequency / sampleRate
        let cw = cos(w), sw = sin(w)
        var c = 1.0, s = 0.0
        var i = 0.0, q = 0.0
        for v in x {
            let sample = Double(v)
            i += sample * c
            q -= sample * s
            (c, s) = (c * cw - s * sw, s * cw + c * sw)
        }
        let n = Double(x.count)
        return Complex(re: 2 * i / n, im: 2 * q / n)
    }
}
