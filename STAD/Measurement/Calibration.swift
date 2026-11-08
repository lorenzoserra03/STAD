import Foundation

/// Model of the jig: the generator drives the load through an internal
/// reference resistor Rref. One input sees the generator ("source"), the other
/// the voltage across the load ("load"). With h = V_load / V_source, after the
/// open-clip correction,
///
///     Z = Rref · h / (1 − h) − R_leads
///
/// Rref comes from a resistor of known value (the 1 kΩ calibration resistor
/// by default). Open clips (input gain mismatch) and shorted clips (lead
/// resistance) refine it. The steps can run in any order.
nonisolated struct Calibration: Codable, Equatable, Sendable {
    static let defaultResistorOhms = 1000.0

    /// Right/left ratio with the clips open, per frequency.
    var open: [ChannelRatio]?
    /// Which input measures the load, once a calibration step has seen it drop.
    var loadIsRight: Bool?
    /// h/(1−h) with the clips shorted; Rref times this is the lead resistance.
    var shortX = 0.0
    /// h/(1−h) measured on the calibration resistor.
    var resistorX: Double?
    var resistorOhms = Calibration.defaultResistorOhms

    var referenceOhms: Double? { resistorX.map { resistorOhms / ($0 - shortX) } }
    var isComplete: Bool { referenceOhms != nil }
    var leadOhms: Double { (referenceOhms ?? 0) * shortX }

    /// Load/source ratio corrected with the open-clip measurement.
    func h(_ point: ChannelRatio, loadIsRight: Bool) -> Complex {
        var ratio = point.ratio
        if let open, let o = Interpolation.value(at: point.frequency, in: open,
                                                 frequency: \.frequency, value: \.ratio) {
            ratio = ratio / o
        }
        return loadIsRight ? ratio : .one / ratio
    }

    func x(_ point: ChannelRatio, loadIsRight: Bool) -> Complex {
        let h = h(point, loadIsRight: loadIsRight)
        return h / (.one - h)
    }

    func impedance(_ sweep: [ChannelRatio]) -> [ImpedancePoint]? {
        guard let referenceOhms else { return nil }
        let right = loadIsRight ?? detectLoadIsRight(sweep)
        return sweep.map { p in
            ImpedancePoint(frequency: p.frequency,
                           z: (x(p, loadIsRight: right) - Complex(re: shortX)) * referenceOhms)
        }
    }

    /// The load channel is the one that drops when a load is connected, so
    /// with a passive load its corrected ratio stays below 1.
    func detectLoadIsRight(_ sweep: [ChannelRatio]) -> Bool {
        Self.median(Self.band(sweep).map { h($0, loadIsRight: true).magnitude }) <= 1
    }

    // MARK: Calibration steps

    mutating func applyOpen(_ sweep: [ChannelRatio]) {
        open = sweep
    }

    /// Lead resistance, from a sweep with the clips shorted together.
    mutating func applyShort(_ sweep: [ChannelRatio]) throws {
        let right = detectLoadIsRight(sweep)
        let x = Self.median(Self.band(sweep).map { x($0, loadIsRight: right).re })
        // Leads are a fraction of an ohm against a reference of tens of ohms.
        guard abs(x) < 0.05 else { throw CalibrationError.shortNotDetected }
        loadIsRight = right
        shortX = x
    }

    /// Rref, from a sweep of a resistor of known value.
    mutating func applyResistor(_ sweep: [ChannelRatio], ohms: Double) throws {
        let right = detectLoadIsRight(sweep)
        let x = Self.median(Self.band(sweep).map { x($0, loadIsRight: right).re })
        guard ohms > 0, x - shortX > 1e-4 else { throw CalibrationError.resistorNotDetected }
        loadIsRight = right
        resistorOhms = ohms
        resistorX = x
    }

    /// Mid band, where the jig is flattest.
    private static func band(_ sweep: [ChannelRatio]) -> [ChannelRatio] {
        let mid = sweep.filter { (50...5000).contains($0.frequency) }
        return mid.isEmpty ? sweep : mid
    }

    private static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }
}

nonisolated enum CalibrationError: LocalizedError {
    case resistorNotDetected
    case shortNotDetected

    var errorDescription: String? {
        switch self {
        case .resistorNotDetected: String(localized: "Resistor not detected: check the connections.")
        case .shortNotDetected: String(localized: "Short not detected: clip the two leads firmly together and try again.")
        }
    }
}
