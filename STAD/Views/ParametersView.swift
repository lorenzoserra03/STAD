import SwiftUI

struct ParametersView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Dati dell'altoparlante") {
                TextField("Re misurata con multimetro (Ω, facoltativa)", value: $model.knownRe, format: .number)
                TextField("Diametro effettivo del cono (cm)", value: $model.coneDiameterCm, format: .number)
                TextField("Massa aggiunta (g)", value: $model.addedMassGrams, format: .number)
            }

            Section {
                HStack {
                    Button("Misura in aria libera") { model.measure(.freeAir) }
                    Button("Misura con massa aggiunta") { model.measure(.addedMass) }
                        .disabled(model.freeAir.isEmpty)
                }
                .disabled(model.isBusy || !model.calibration.isComplete)
            } footer: {
                Text("Per Vas, Mms, Cms e Bl: misura in aria libera, poi fissa al cono una massa nota (circa la massa mobile) e ripeti.")
            }

            if let p = model.resonance {
                Section("Piccolo segnale") {
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
                Section { Text("Risonanza non trovata nella curva.").foregroundStyle(.secondary) }
            }

            if let m = model.massParameters {
                Section("Massa aggiunta") {
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
        .navigationTitle("Parametri Thiele-Small")
    }

    private func row(_ name: String, _ value: Double, _ unit: String, _ digits: Int) -> some View {
        LabeledContent(name) {
            Text("\(value, format: .number.precision(.fractionLength(digits))) \(unit)").monospacedDigit()
        }
    }
}
