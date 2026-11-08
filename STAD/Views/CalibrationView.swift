import SwiftUI

struct CalibrationView: View {
    @Environment(AppModel.self) private var model
    @State private var resistorOhms = Calibration.defaultResistorOhms

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Device") {
                Picker("Input", selection: $model.inputDevice) {
                    ForEach(model.devices.filter { $0.inputChannels >= 2 }) { Text($0.name).tag(Optional($0)) }
                }
                Picker("Output", selection: $model.outputDevice) {
                    ForEach(model.devices.filter { $0.outputChannels >= 2 }) { Text($0.name).tag(Optional($0)) }
                }
                HStack {
                    Button("Refresh") { model.refreshDevices() }
                    Button("Connect") { model.restartStreaming() }
                }
            }

            Section("Measurement") {
                TextField("Start frequency (Hz)", value: $model.settings.startHz, format: .number)
                TextField("Stop frequency (Hz)", value: $model.settings.stopHz, format: .number)
                TextField("Points per octave", value: $model.settings.pointsPerOctave, format: .number)
                LabeledContent("Output level") {
                    Slider(value: $model.settings.amplitude, in: 0.01...1)
                }
            }

            Section {
                step(1, "Leads open, not connected to anything.", done: model.calibration.open != nil) {
                    model.calibrateOpen()
                }
                HStack {
                    step(2, "Leads on the calibration resistor.", done: model.calibration.isComplete) {
                        model.calibrateResistor(ohms: resistorOhms)
                    }
                    TextField(value: $resistorOhms, format: .number) { Text(verbatim: "Ω") }.frame(width: 70)
                    Text(verbatim: "Ω")
                }
                step(3, "Leads shorted together (optional, measures the lead resistance).",
                     done: model.calibration.shortX != 0) {
                    model.calibrateShort()
                }
            } header: {
                Text("Calibration")
            } footer: {
                Text("Step 2 is required: it measures the internal reference resistor using the 1 kΩ calibration resistor. The other steps improve accuracy and can be repeated in any order.")
            }
            .disabled(model.isBusy)

            Section("Result") {
                LabeledContent("Internal reference resistor") {
                    Text(verbatim: model.calibration.referenceOhms.map { ohms($0, digits: 2) } ?? "—")
                }
                LabeledContent("Lead resistance") { Text(verbatim: ohms(model.calibration.leadOhms, digits: 3)) }
                LabeledContent("Load channel") {
                    switch model.calibration.loadIsRight {
                    case true?: Text("Right")
                    case false?: Text("Left")
                    case nil: Text("Automatic")
                    }
                }
                Button("Reset calibration", role: .destructive) { model.calibration = Calibration() }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Calibration")
    }

    private func ohms(_ value: Double, digits: Int) -> String {
        value.formatted(.number.precision(.fractionLength(digits))) + " Ω"
    }

    private func step(_ n: Int, _ text: LocalizedStringKey, done: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: done ? "checkmark.circle.fill" : "\(n).circle")
                .foregroundStyle(done ? .green : .secondary)
            Text(text)
            Spacer()
            Button("Run", action: action)
        }
    }
}
