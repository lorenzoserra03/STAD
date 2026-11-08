import Foundation
import Observation

@Observable
final class AppModel {
    enum Target { case freeAir, addedMass }

    let io = AudioIO()

    var devices: [AudioDevice] = []
    var inputDevice: AudioDevice?
    var outputDevice: AudioDevice?

    var settings = SweepSettings()
    var calibration: Calibration { didSet { saveCalibration() } }

    var freeAir: [ImpedancePoint] = []
    var addedMass: [ImpedancePoint] = []

    // Driver data entered by the user.
    var knownRe: Double?
    var coneDiameterCm = 0.0
    var addedMassGrams = 0.0

    var status = String(localized: "Ready")
    var warning: String?
    var isBusy = false
    var progress = 0.0

    // Generator
    var generatorOn = false { didSet { updateGenerator() } }
    var generatorFrequency = 1000.0 { didSet { updateGenerator() } }
    var generatorAmplitude = 0.3 { didSet { updateGenerator() } }
    var waveform = Waveform.sine { didSet { updateGenerator() } }

    private var task: Task<Void, Never>?
    private static let calibrationKey = "calibration.v1"

    init() {
        calibration = UserDefaults.standard.data(forKey: Self.calibrationKey)
            .flatMap { try? JSONDecoder().decode(Calibration.self, from: $0) } ?? Calibration()
        refreshDevices()
    }

    // MARK: Derived results

    var resonance: ResonanceParameters? { ThieleSmall.resonance(freeAir, re: knownRe) }

    var massParameters: MassParameters? {
        guard let resonance, let fsLoaded = ThieleSmall.resonanceFrequency(addedMass) else { return nil }
        let radius = coneDiameterCm / 200
        return ThieleSmall.withAddedMass(resonance, fsLoaded: fsLoaded,
                                         addedMass: addedMassGrams / 1000, sd: .pi * radius * radius)
    }

    // MARK: Devices

    func refreshDevices() {
        devices = AudioDevices.all()
        if let tester = AudioDevices.findTester(in: devices) {
            inputDevice = inputDevice ?? tester.input
            outputDevice = outputDevice ?? tester.output
        }
    }

    private func ensureStreaming() throws {
        guard !io.isRunning else { return }
        guard let inputDevice, let outputDevice else { throw TesterError.notFound }
        try io.start(input: inputDevice, output: outputDevice)
    }

    func restartStreaming() {
        io.stop()
        do { try ensureStreaming(); status = String(localized: "Device connected") } catch { status = error.localizedDescription }
    }

    // MARK: Measurements

    func measure(_ target: Target) {
        runSweep(target == .freeAir ? String(localized: "Measuring impedance…")
                                     : String(localized: "Measuring with added mass…"),
                 refineResonance: true) { [self] sweep in
            guard let curve = calibration.impedance(sweep) else { throw TesterError.notCalibrated }
            switch target {
            case .freeAir: freeAir = curve
            case .addedMass: addedMass = curve
            }
        }
    }

    func calibrateOpen() {
        runSweep(String(localized: "Calibration: open leads…")) { [self] in calibration.applyOpen($0) }
    }

    func calibrateShort() {
        runSweep(String(localized: "Calibration: shorted leads…")) { [self] in try calibration.applyShort($0) }
    }

    func calibrateResistor(ohms: Double) {
        runSweep(String(localized: "Calibration: \(ohms.formatted()) Ω resistor…")) { [self] in try calibration.applyResistor($0, ohms: ohms) }
    }

    func cancel() {
        task?.cancel()
    }

    private func runSweep(_ label: String, refineResonance: Bool = false,
                          apply: @escaping ([ChannelRatio]) throws -> Void) {
        guard !isBusy else { return }
        do { try ensureStreaming() } catch { status = error.localizedDescription; return }
        generatorOn = false
        isBusy = true
        progress = 0
        warning = nil
        status = label
        let io = io, frequencies = settings.frequencies, amplitude = settings.amplitude
        task = Task {
            defer { isBusy = false }
            do {
                var sweep = try await Sweep.run(io: io, frequencies: frequencies, amplitude: amplitude) { value in
                    await MainActor.run { self.progress = value }
                }
                if refineResonance, let curve = calibration.impedance(sweep),
                   let extra = Sweep.refinement(around: curve, existing: frequencies) {
                    status = String(localized: "Refining around resonance…")
                    progress = 0
                    sweep += try await Sweep.run(io: io, frequencies: extra, amplitude: amplitude) { value in
                        await MainActor.run { self.progress = value }
                    }
                    sweep.sort { $0.frequency < $1.frequency }
                }
                if sweep.contains(where: { max($0.leftLevel, $0.rightLevel) > 0.95 }) {
                    warning = String(localized: "Input close to clipping: lower the level.")
                }
                try apply(sweep)
                status = String(localized: "Done")
            } catch is CancellationError {
                status = String(localized: "Cancelled")
            } catch {
                status = error.localizedDescription
            }
        }
    }

    // MARK: Generator

    private func updateGenerator() {
        guard !isBusy else { return }
        if generatorOn {
            do { try ensureStreaming() } catch { status = error.localizedDescription; return }
            io.setGenerator(frequency: generatorFrequency, amplitude: generatorAmplitude, waveform: waveform)
        } else {
            io.silence()
        }
    }

    private func saveCalibration() {
        if let data = try? JSONEncoder().encode(calibration) {
            UserDefaults.standard.set(data, forKey: Self.calibrationKey)
        }
    }
}

nonisolated enum TesterError: LocalizedError {
    case notFound
    case notCalibrated

    var errorDescription: String? {
        switch self {
        case .notFound: String(localized: "DATS not found: connect it via USB and press Refresh.")
        case .notCalibrated: String(localized: "Calibrate first with the 1 kΩ resistor (Calibration page).")
        }
    }
}
