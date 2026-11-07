import SwiftUI

struct GeneratorView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Generatore") {
                Toggle("Uscita attiva", isOn: $model.generatorOn)
                Picker("Forma d'onda", selection: $model.waveform) {
                    Text("Sinusoide").tag(Waveform.sine)
                    Text("Quadra").tag(Waveform.square)
                    Text("Triangolare").tag(Waveform.triangle)
                }
                .pickerStyle(.segmented)
                LabeledContent("Frequenza") {
                    HStack {
                        Slider(value: logFrequency, in: log10(10)...log10(20_000))
                        TextField("Hz", value: $model.generatorFrequency, format: .number.precision(.fractionLength(1)))
                            .frame(width: 90)
                        Text("Hz")
                    }
                }
                LabeledContent("Livello") {
                    HStack {
                        Slider(value: $model.generatorAmplitude, in: 0...1)
                        Text(20 * log10(max(model.generatorAmplitude, 1e-6)), format: .number.precision(.fractionLength(1)))
                            .monospacedDigit().frame(width: 60, alignment: .trailing)
                        Text("dBFS")
                    }
                }
            }

            Section("Ingressi") {
                TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                    let levels = model.io.currentLevels
                    VStack(alignment: .leading) {
                        meter("Sinistro", levels.left)
                        meter("Destro", levels.right)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Generatore")
        .onDisappear { model.generatorOn = false }
    }

    private var logFrequency: Binding<Double> {
        Binding { log10(model.generatorFrequency) } set: { model.generatorFrequency = (pow(10, $0) * 10).rounded() / 10 }
    }

    private func meter(_ name: String, _ rms: Float) -> some View {
        let db = 20 * log10(max(Double(rms), 1e-6))
        return LabeledContent(name) {
            HStack {
                Gauge(value: max(db, -90), in: -90...0) {}.gaugeStyle(.accessoryLinearCapacity)
                Text("\(db, format: .number.precision(.fractionLength(1))) dBFS RMS")
                    .monospacedDigit().frame(width: 130, alignment: .trailing)
            }
        }
    }
}
