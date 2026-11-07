import Foundation

nonisolated struct Complex: Codable, Hashable, Sendable {
    var re: Double
    var im: Double

    static let zero = Complex(re: 0, im: 0)
    static let one = Complex(re: 1, im: 0)

    init(re: Double, im: Double = 0) {
        self.re = re
        self.im = im
    }

    var magnitude: Double { hypot(re, im) }
    var phaseDegrees: Double { atan2(im, re) * 180 / .pi }

    static func + (a: Complex, b: Complex) -> Complex { Complex(re: a.re + b.re, im: a.im + b.im) }
    static func - (a: Complex, b: Complex) -> Complex { Complex(re: a.re - b.re, im: a.im - b.im) }
    static func * (a: Complex, b: Complex) -> Complex {
        Complex(re: a.re * b.re - a.im * b.im, im: a.re * b.im + a.im * b.re)
    }
    static func * (a: Complex, k: Double) -> Complex { Complex(re: a.re * k, im: a.im * k) }
    static func / (a: Complex, b: Complex) -> Complex {
        let d = b.re * b.re + b.im * b.im
        return Complex(re: (a.re * b.re + a.im * b.im) / d, im: (a.im * b.re - a.re * b.im) / d)
    }
}

nonisolated enum Interpolation {
    /// Linear interpolation on a log-frequency axis; clamps outside the range.
    /// `points` must be sorted by frequency.
    static func value<T>(at f: Double, in points: [T], frequency: (T) -> Double,
                         value: (T) -> Complex) -> Complex? {
        guard let first = points.first, let last = points.last else { return nil }
        if f <= frequency(first) { return value(first) }
        if f >= frequency(last) { return value(last) }
        let upper = points.firstIndex { frequency($0) >= f }!
        let a = points[upper - 1], b = points[upper]
        let t = log(f / frequency(a)) / log(frequency(b) / frequency(a))
        return value(a) * (1 - t) + value(b) * t
    }

    /// Log-frequency position where `y` crosses `level` between two samples.
    static func crossing(f0: Double, y0: Double, f1: Double, y1: Double, level: Double) -> Double {
        guard y1 != y0 else { return f0 }
        let t = (level - y0) / (y1 - y0)
        return f0 * pow(f1 / f0, t)
    }
}
