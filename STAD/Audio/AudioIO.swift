import AVFoundation
import CoreAudio

nonisolated enum AudioIOError: LocalizedError {
    case noAudioUnit
    case coreAudio(OSStatus)
    case needsStereoInput
    case notRunning

    var errorDescription: String? {
        switch self {
        case .noAudioUnit: String(localized: "Audio unit not available.")
        case .coreAudio(let status): String(localized: "Core Audio error \(status).")
        case .needsStereoInput: String(localized: "The input device must have two channels.")
        case .notRunning: String(localized: "The audio stream is not running.")
        }
    }
}

nonisolated enum Waveform: String, CaseIterable, Identifiable, Codable, Sendable {
    case sine, square, triangle
    var id: Self { self }

    /// One period sampled at `phase` ∈ [0, 1).
    func value(at phase: Double) -> Double {
        switch self {
        case .sine: sin(2 * .pi * phase)
        case .square: phase < 0.5 ? 1 : -1
        case .triangle: phase < 0.5 ? 4 * phase - 1 : 3 - 4 * phase
        }
    }
}

/// Full-duplex streaming on the tester: a generator on both output channels and
/// a stereo capture of the two inputs. Thread-safe; the render and tap callbacks
/// run on Core Audio threads.
nonisolated final class AudioIO: @unchecked Sendable {
    struct Levels: Sendable {
        var left: Float = 0
        var right: Float = 0
        var peak: Float = 0
    }

    private let lock = NSLock()

    // Generator parameters, written by callers.
    private var frequency = 1000.0
    private var targetAmplitude = 0.0
    private var waveform = Waveform.sine

    // Render-thread state.
    private var phase = 0.0
    private var amplitude = 0.0

    // Capture state.
    private var capturing = false
    private var captureLeft: [Float] = []
    private var captureRight: [Float] = []
    private var levels = Levels()

    private var outputEngine: AVAudioEngine?
    private var inputEngine: AVAudioEngine?
    private var sampleRate = 48_000.0

    var isRunning: Bool { lock.withLock { outputEngine != nil } }
    var inputSampleRate: Double { lock.withLock { sampleRate } }
    var currentLevels: Levels { lock.withLock { levels } }

    deinit { stop() }

    func start(input: AudioDevice, output: AudioDevice) throws {
        stop()
        let out = AVAudioEngine()
        let inp = AVAudioEngine()
        try Self.select(output.id, on: out.outputNode)
        try Self.select(input.id, on: inp.inputNode)

        let outputRate = out.outputNode.outputFormat(forBus: 0).sampleRate
        let source = AVAudioSourceNode { [unowned self] _, _, frames, bufferList in
            render(frames: Int(frames), into: UnsafeMutableAudioBufferListPointer(bufferList), sampleRate: outputRate)
            return noErr
        }
        out.attach(source)
        try out.connectNode(source, to: out.mainMixerNode,
                            format: AVAudioFormat(standardFormatWithSampleRate: outputRate, channels: 2))
        out.mainMixerNode.outputVolume = 1

        let inputFormat = inp.inputNode.inputFormat(forBus: 0)
        guard inputFormat.channelCount >= 2 else { throw AudioIOError.needsStereoInput }
        inp.inputNode.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [unowned self] buffer, _ in
            receive(buffer)
        }

        try out.start()
        do { try inp.start() } catch { out.stop(); throw error }
        lock.withLock {
            outputEngine = out
            inputEngine = inp
            sampleRate = inputFormat.sampleRate
        }
    }

    func stop() {
        let (out, inp) = lock.withLock {
            defer { outputEngine = nil; inputEngine = nil; capturing = false }
            return (outputEngine, inputEngine)
        }
        inp?.inputNode.removeTap(onBus: 0)
        inp?.stop()
        out?.stop()
    }

    func setGenerator(frequency: Double, amplitude: Double, waveform: Waveform = .sine) {
        lock.withLock {
            self.frequency = frequency
            self.targetAmplitude = min(max(amplitude, 0), 1)
            self.waveform = waveform
        }
    }

    func silence() {
        lock.withLock { targetAmplitude = 0 }
    }

    /// Records `frames` samples of both inputs, starting now.
    func capture(frames: Int) async throws -> (left: [Float], right: [Float]) {
        guard isRunning else { throw AudioIOError.notRunning }
        lock.withLock {
            captureLeft.removeAll(keepingCapacity: true)
            captureRight.removeAll(keepingCapacity: true)
            captureLeft.reserveCapacity(frames)
            captureRight.reserveCapacity(frames)
            capturing = true
        }
        defer { lock.withLock { capturing = false } }
        while lock.withLock({ captureLeft.count }) < frames {
            try await Task.sleep(for: .milliseconds(15))
            guard isRunning else { throw AudioIOError.notRunning }
        }
        return lock.withLock { (Array(captureLeft.prefix(frames)), Array(captureRight.prefix(frames))) }
    }

    private func render(frames: Int, into buffers: UnsafeMutableAudioBufferListPointer, sampleRate: Double) {
        let (f, target, wave) = lock.withLock { (frequency, targetAmplitude, waveform) }
        let step = f / sampleRate
        let smoothing = 1 - exp(-1 / (0.005 * sampleRate)) // ~5 ms ramp, avoids clicks
        for i in 0..<frames {
            amplitude += (target - amplitude) * smoothing
            let value = Float(amplitude * wave.value(at: phase))
            phase += step
            if phase >= 1 { phase -= phase.rounded(.down) }
            for buffer in buffers {
                buffer.mData?.assumingMemoryBound(to: Float.self)[i] = value
            }
        }
    }

    private func receive(_ buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData, buffer.format.channelCount >= 2 else { return }
        let n = Int(buffer.frameLength)
        let left = UnsafeBufferPointer(start: channels[0], count: n)
        let right = UnsafeBufferPointer(start: channels[1], count: n)
        var sumL: Float = 0, sumR: Float = 0, peak: Float = 0
        for i in 0..<n {
            sumL += left[i] * left[i]
            sumR += right[i] * right[i]
            peak = max(peak, abs(left[i]), abs(right[i]))
        }
        let current = Levels(left: (sumL / Float(max(n, 1))).squareRoot(),
                             right: (sumR / Float(max(n, 1))).squareRoot(),
                             peak: peak)
        lock.withLock {
            levels = current
            if capturing {
                captureLeft.append(contentsOf: left)
                captureRight.append(contentsOf: right)
            }
        }
    }

    private static func select(_ device: AudioDeviceID, on node: AVAudioIONode) throws {
        try node.withAudioUnit { (unit: borrowing AudioUnit?) throws(AudioIOError) in
            guard let unit = copy unit else { throw .noAudioUnit }
            var id = device
            let status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
                                              kAudioUnitScope_Global, 0, &id,
                                              UInt32(MemoryLayout<AudioDeviceID>.size))
            guard status == noErr else { throw .coreAudio(status) }
        }
    }
}
