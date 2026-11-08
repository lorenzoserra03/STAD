import SwiftUI

struct GeneratorView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Generator") {
                Toggle("Output on", isOn: $model.generatorOn)
                Picker("Waveform", selection: $model.waveform) {
                    Text("Sine").tag(Waveform.sine)
                    Text("Square").tag(Waveform.square)
                    Text("Triangle").tag(Waveform.triangle)
                }
                .pickerStyle(.segmented)
                LabeledContent("Frequency") {
                    HStack {
                        Slider(value: logFrequency, in: log10(10)...log10(20_000))
                        TextField(value: $model.generatorFrequency, format: .number.precision(.fractionLength(1))) {
                            Text(verbatim: "Hz")
                        }
                        .frame(width: 90)
                        Text(verbatim: "Hz")
                    }
                }
                LabeledContent("Level") {
                    HStack {
                        Slider(value: $model.generatorAmplitude, in: 0...1)
                        Text(20 * log10(max(model.generatorAmplitude, 1e-6)), format: .number.precision(.fractionLength(1)))
                            .monospacedDigit().frame(width: 60, alignment: .trailing)
                        Text(verbatim: "dBFS")
                    }
                }
            }

            Section("Inputs") {
                TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                    let levels = model.io.currentLevels
                    VStack(alignment: .leading) {
                        meter("Left", levels.left)
                        meter("Right", levels.right)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Generator")
        .onDisappear { model.generatorOn = false }
    }

    private var logFrequency: Binding<Double> {
        Binding { log10(model.generatorFrequency) } set: { model.generatorFrequency = (pow(10, $0) * 10).rounded() / 10 }
    }

    private func meter(_ name: LocalizedStringKey, _ rms: Float) -> some View {
        let db = 20 * log10(max(Double(rms), 1e-6))
        return LabeledContent(name) {
            HStack {
                Gauge(value: max(db, -90), in: -90...0) {}.gaugeStyle(.accessoryLinearCapacity)
                Text(verbatim: "\(db.formatted(.number.precision(.fractionLength(1)))) dBFS RMS")
                    .monospacedDigit().frame(width: 130, alignment: .trailing)
            }
        }
    }
}
