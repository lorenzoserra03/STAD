import Foundation

nonisolated struct SweepSettings: Codable, Equatable, Sendable {
    var startHz = 10.0
    var stopHz = 20_000.0
    var pointsPerOctave = 12.0
    /// Generator level, fraction of full scale.
    var amplitude = 0.3

    var frequencies: [Double] {
        let octaves = log2(stopHz / startHz)
        let count = max(2, Int((octaves * pointsPerOctave).rounded()) + 1)
        return (0..<count).map { startHz * pow(stopHz / startHz, Double($0) / Double(count - 1)) }
    }
}

/// One stepped-sine point: the right/left input ratio at `frequency`.
/// Both inputs are sampled by the same converter, so the ratio is independent
/// of output/input latency.
nonisolated struct ChannelRatio: Codable, Hashable, Sendable {
    var frequency: Double
    var ratio: Complex
    var leftLevel: Double
    var rightLevel: Double
}

nonisolated enum Sweep {
    @concurrent
    static func run(io: AudioIO, frequencies: [Double], amplitude: Double,
                    progress: @escaping @Sendable (Double) async -> Void) async throws -> [ChannelRatio] {
        defer { io.silence() }
        let sampleRate = io.inputSampleRate
        var result: [ChannelRatio] = []
        for (index, f) in frequencies.enumerated() {
            try Task.checkCancellation()
            io.setGenerator(frequency: f, amplitude: amplitude)
            // Pipeline latency plus a few periods for the driver's resonance to settle.
            try await Task.sleep(for: .seconds(0.15 + 8 / f))
            let periods = max(10, (0.1 * f).rounded(.up))
            let frames = Int((periods * sampleRate / f).rounded())
            let (left, right) = try await io.capture(frames: frames)
            let l = LockIn.phasor(left, frequency: f, sampleRate: sampleRate)
            let r = LockIn.phasor(right, frequency: f, sampleRate: sampleRate)
            result.append(ChannelRatio(frequency: f, ratio: r / l, leftLevel: l.magnitude, rightLevel: r.magnitude))
            await progress(Double(index + 1) / Double(frequencies.count))
        }
        return result
    }

    /// Extra frequencies, 1/48 octave apart, within ±1/3 octave of the impedance
    /// peak, so the narrow resonance is sampled densely without slowing the
    /// whole sweep. Nil if there is no peak below 1 kHz.
    static func refinement(around curve: [ImpedancePoint], existing: [Double]) -> [Double]? {
        let low = curve.filter { $0.frequency < 1000 }
        guard low.count >= 3,
              let peak = low.indices.dropFirst().dropLast().max(by: { low[$0].magnitude < low[$1].magnitude })
        else { return nil }
        let center = low[peak].frequency
        let step = 1.0 / 48
        return (-16...16)
            .map { center * pow(2, Double($0) * step) }
            .filter { f in existing.allSatisfy { abs(log2(f / $0)) > step / 2 } }
    }
}
