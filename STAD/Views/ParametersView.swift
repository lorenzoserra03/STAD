import SwiftUI

struct ParametersView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Driver data") {
                TextField("Re measured with a multimeter (Ω, optional)", value: $model.knownRe, format: .number)
                TextField("Effective cone diameter (cm)", value: $model.coneDiameterCm, format: .number)
                TextField("Added mass (g)", value: $model.addedMassGrams, format: .number)
            }

            Section {
                HStack {
                    Button("Measure in free air") { model.measure(.freeAir) }
                    Button("Measure with added mass") { model.measure(.addedMass) }
                        .disabled(model.freeAir.isEmpty)
                }
                .disabled(model.isBusy || !model.calibration.isComplete)
            } footer: {
                Text("For Vas, Mms, Cms and Bl: measure in free air, then attach a known mass to the cone (roughly the moving mass) and measure again.")
            }

            if let p = model.resonance {
                Section("Small signal") {
                    row("Fs", p.fs, "Hz", 2)
                    row("Re", p.re, "Ω", 3)
                    row("Zmax", p.zMax, "Ω", 2)
                    row("Qms", p.qms, "", 3)
                    row("Qes", p.qes, "", 3)
                    row("Qts", p.qts, "", 3)
                    if let le = p.le1k { row("Le @ 1 kHz", le * 1000, "mH", 3) }
                    if let le = p.le10k { row("Le @ 10 kHz", le * 1000, "mH", 3) }
                }
            } else if !model.freeAir.isEmpty {
                Section { Text("No resonance found in the curve.").foregroundStyle(.secondary) }
            }

            if let m = model.massParameters {
                Section("Added mass") {
                    row("Mms", m.mms * 1000, "g", 2)
                    row("Cms", m.cms * 1000, "mm/N", 3)
                    row("Vas", m.vas * 1000, "L", 2)
                    row("Bl", m.bl, "T·m", 2)
                    row("η₀", m.efficiency * 100, "%", 3)
                    row("SPL 1 W/1 m", m.sensitivity, "dB", 1)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Thiele-Small Parameters")
    }

    /// Parameter symbols and units are the same in every language.
    private func row(_ name: String, _ value: Double, _ unit: String, _ digits: Int) -> some View {
        LabeledContent {
            Text(verbatim: "\(value.formatted(.number.precision(.fractionLength(digits)))) \(unit)").monospacedDigit()
        } label: {
            Text(verbatim: name)
        }
    }
}
