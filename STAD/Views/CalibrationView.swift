import SwiftUI

struct CalibrationView: View {
    @Environment(AppModel.self) private var model
    @State private var resistorOhms = Calibration.defaultResistorOhms

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Dispositivo") {
                Picker("Ingresso", selection: $model.inputDevice) {
                    ForEach(model.devices.filter { $0.inputChannels >= 2 }) { Text($0.name).tag(Optional($0)) }
                }
                Picker("Uscita", selection: $model.outputDevice) {
                    ForEach(model.devices.filter { $0.outputChannels >= 2 }) { Text($0.name).tag(Optional($0)) }
                }
                HStack {
                    Button("Aggiorna") { model.refreshDevices() }
                    Button("Collega") { model.restartStreaming() }
                }
            }

            Section("Misura") {
                TextField("Frequenza iniziale (Hz)", value: $model.settings.startHz, format: .number)
                TextField("Frequenza finale (Hz)", value: $model.settings.stopHz, format: .number)
                TextField("Punti per ottava", value: $model.settings.pointsPerOctave, format: .number)
                LabeledContent("Livello di uscita") {
                    Slider(value: $model.settings.amplitude, in: 0.01...1)
                }
            }

            Section {
                step(1, "Puntali aperti, non collegati a nulla.", done: model.calibration.open != nil) {
                    model.calibrateOpen()
                }
                HStack {
                    step(2, "Puntali sul resistore di calibrazione.", done: model.calibration.isComplete) {
                        model.calibrateResistor(ohms: resistorOhms)
                    }
                    TextField("Ω", value: $resistorOhms, format: .number).frame(width: 70)
                    Text("Ω")
                }
                step(3, "Puntali in corto tra loro (facoltativo, misura la resistenza dei cavi).",
                     done: model.calibration.shortX != 0) {
                    model.calibrateShort()
                }
            } header: {
                Text("Calibrazione")
            } footer: {
                Text("Il passo 2 è obbligatorio: misura il resistore di riferimento interno usando il resistore di calibrazione da 1 kΩ. Gli altri passi migliorano la precisione e si possono ripetere in qualsiasi ordine.")
            }
            .disabled(model.isBusy)

            Section("Risultato") {
                LabeledContent("Resistore di riferimento interno") {
                    Text(model.calibration.referenceOhms.map { String(format: "%.2f Ω", $0) } ?? "—")
                }
                LabeledContent("Resistenza dei puntali") { Text(String(format: "%.3f Ω", model.calibration.leadOhms)) }
                LabeledContent("Canale del carico") {
                    Text(model.calibration.loadIsRight.map { $0 ? "Destro" : "Sinistro" } ?? "Automatico")
                }
                Button("Azzera calibrazione", role: .destructive) { model.calibration = Calibration() }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Calibrazione")
    }

    private func step(_ n: Int, _ text: String, done: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: done ? "checkmark.circle.fill" : "\(n).circle")
                .foregroundStyle(done ? .green : .secondary)
            Text(text)
            Spacer()
            Button("Esegui", action: action)
        }
    }
}
