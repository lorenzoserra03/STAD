import Foundation

nonisolated struct ImpedancePoint: Codable, Hashable, Sendable, Identifiable {
    var frequency: Double
    var z: Complex

    var id: Double { frequency }
    var magnitude: Double { z.magnitude }
    var phase: Double { z.phaseDegrees }
}

/// Small-signal parameters read from the free-air impedance curve
/// (the classic "Re, Zmax, f1/f2" method, R. H. Small 1972).
nonisolated struct ResonanceParameters: Sendable {
    var fs: Double
    var re: Double
    var zMax: Double
    var f1: Double
    var f2: Double
    var qms: Double
    var qes: Double
    var qts: Double
    var le1k: Double?
    var le10k: Double?
}

/// Parameters that need the moving mass, obtained with the added-mass method.
nonisolated struct MassParameters: Sendable {
    var mms: Double  // kg
    var cms: Double  // m/N
    var vas: Double  // m³
    var bl: Double   // T·m
    var efficiency: Double
    var sensitivity: Double  // dB SPL, 1 W / 1 m
}

nonisolated enum ThieleSmall {
    static let airDensity = 1.204      // kg/m³ at 20 °C
    static let speedOfSound = 343.0    // m/s

    /// - Parameter re: DC resistance if known (e.g. from a multimeter); otherwise
    ///   estimated from the impedance minimum above resonance.
    static func resonance(_ curve: [ImpedancePoint], re knownRe: Double? = nil) -> ResonanceParameters? {
        let low = curve.filter { $0.frequency < 1000 }
        guard low.count >= 5,
              let peak = low.indices.dropFirst().dropLast().max(by: { low[$0].magnitude < low[$1].magnitude })
        else { return nil }

        // fs where the phase crosses zero next to the peak.
        var fs = low[peak].frequency
        for i in max(peak - 1, 1)...min(peak + 1, low.count - 1)
        where low[i - 1].phase > 0 && low[i].phase <= 0 {
            fs = Interpolation.crossing(f0: low[i - 1].frequency, y0: low[i - 1].phase,
                                        f1: low[i].frequency, y1: low[i].phase, level: 0)
        }
        let zMax = peakMagnitude(low, around: peak)

        let re = knownRe ?? estimateRe(curve, fs: fs)
        guard re > 0, zMax > re else { return nil }
        let r0 = zMax / re
        let level = re * r0.squareRoot()

        guard let f1 = crossing(low, from: peak, step: -1, level: level),
              let f2 = crossing(curve, from: peak, step: 1, level: level), // `low` is a prefix of `curve`
              f2 > f1 else { return nil }

        let qms = fs * r0.squareRoot() / (f2 - f1)
        let qes = qms / (r0 - 1)
        return ResonanceParameters(
            fs: fs, re: re, zMax: zMax, f1: f1, f2: f2,
            qms: qms, qes: qes, qts: qms * qes / (qms + qes),
            le1k: inductance(curve, at: 1000), le10k: inductance(curve, at: 10_000))
    }

    /// Added-mass method: `fsLoaded` is the resonance with `addedMass` (kg) on the cone.
    static func withAddedMass(_ p: ResonanceParameters, fsLoaded: Double, addedMass: Double,
                              sd: Double) -> MassParameters? {
        let ratio = pow(p.fs / fsLoaded, 2)
        guard ratio > 1, addedMass > 0, sd > 0 else { return nil }
        let mms = addedMass / (ratio - 1)
        let w = 2 * Double.pi * p.fs
        let cms = 1 / (w * w * mms)
        let vas = airDensity * speedOfSound * speedOfSound * sd * sd * cms
        let bl = (w * mms * p.re / p.qes).squareRoot()
        let efficiency = 4 * Double.pi * Double.pi / pow(speedOfSound, 3) * pow(p.fs, 3) * vas / p.qes
        return MassParameters(mms: mms, cms: cms, vas: vas, bl: bl,
                              efficiency: efficiency, sensitivity: 112.1 + 10 * log10(efficiency))
    }

    /// Resonance frequency only, for the loaded measurement.
    static func resonanceFrequency(_ curve: [ImpedancePoint]) -> Double? {
        resonance(curve)?.fs
    }

    /// Lowest resistive part between fs and 10·fs, an upper bound close to Re.
    static func estimateRe(_ curve: [ImpedancePoint], fs: Double) -> Double {
        let band = curve.filter { $0.frequency > fs && $0.frequency < min(10 * fs, 2000) }
        return band.map(\.z.re).min() ?? curve.map(\.z.re).min() ?? 0
    }

    /// Vertex of the parabola through the three samples around the peak (on a
    /// log-frequency axis), so a coarse grid does not clip the top of the curve.
    private static func peakMagnitude(_ curve: [ImpedancePoint], around i: Int) -> Double {
        // y = y1 + a·u² + c·u with u = log f − log f1
        let u0 = log(curve[i - 1].frequency / curve[i].frequency)
        let u2 = log(curve[i + 1].frequency / curve[i].frequency)
        let dy0 = curve[i - 1].magnitude - curve[i].magnitude
        let dy2 = curve[i + 1].magnitude - curve[i].magnitude
        let a = (dy0 * u2 - dy2 * u0) / (u0 * u0 * u2 - u2 * u2 * u0)
        let c = (dy0 - a * u0 * u0) / u0
        guard a < 0 else { return curve[i].magnitude }
        return curve[i].magnitude - c * c / (4 * a)
    }

    private static func inductance(_ curve: [ImpedancePoint], at f: Double) -> Double? {
        guard let last = curve.last, last.frequency >= f,
              let z = Interpolation.value(at: f, in: curve, frequency: \.frequency, value: \.z) else { return nil }
        return z.im / (2 * .pi * f)
    }

    private static func crossing(_ curve: [ImpedancePoint], from start: Int, step: Int, level: Double) -> Double? {
        var i = start
        while curve.indices.contains(i + step) {
            let a = curve[i], b = curve[i + step]
            if a.magnitude >= level && b.magnitude < level {
                return Interpolation.crossing(f0: a.frequency, y0: a.magnitude,
                                              f1: b.frequency, y1: b.magnitude, level: level)
            }
            i += step
        }
        return nil
    }
}
