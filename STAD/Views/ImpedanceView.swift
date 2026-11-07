import Charts
import SwiftUI

struct ImpedanceView: View {
    @Environment(AppModel.self) private var model
    @State private var exporting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ImpedanceChart(curves: curves)
        }
        .padding()
        .navigationTitle("Impedenza")
        .toolbar {
            Button("Misura", systemImage: "play.fill") { model.measure(.freeAir) }
                .disabled(model.isBusy || !model.calibration.isComplete)
            Button("Esporta .zma", systemImage: "square.and.arrow.up") { exporting = true }
                .disabled(model.freeAir.isEmpty)
        }
        .fileExporter(isPresented: $exporting, document: TextFile(text: ImpedanceExport.zma(model.freeAir)),
                      contentType: .zma, defaultFilename: "impedenza") { _ in }
    }

    private var curves: [(String, [ImpedancePoint])] {
        var result = [("Aria libera", model.freeAir)]
        if !model.addedMass.isEmpty { result.append(("Con massa", model.addedMass)) }
        return result
    }
}

struct ImpedanceChart: View {
    var curves: [(String, [ImpedancePoint])]

    var body: some View {
        VStack(spacing: 12) {
            Chart {
                ForEach(curves, id: \.0) { name, points in
                    ForEach(points) { p in
                        LineMark(x: .value("Hz", p.frequency), y: .value("Ω", p.magnitude))
                            .foregroundStyle(by: .value("Curva", name))
                            .interpolationMethod(.monotone)
                    }
                }
            }
            .chartXScale(domain: 10...20_000, type: .log)
            .chartXAxis { frequencyAxis }
            .chartYAxisLabel("|Z| (Ω)")

            Chart {
                ForEach(curves, id: \.0) { name, points in
                    ForEach(points) { p in
                        LineMark(x: .value("Hz", p.frequency), y: .value("°", p.phase))
                            .foregroundStyle(by: .value("Curva", name))
                            .interpolationMethod(.monotone)
                    }
                }
            }
            .chartXScale(domain: 10...20_000, type: .log)
            .chartYScale(domain: -90...90)
            .chartXAxis { frequencyAxis }
            .chartYAxisLabel("Fase (°)")
            .frame(maxHeight: 220)
        }
        .overlay {
            if curves.allSatisfy({ $0.1.isEmpty }) {
                ContentUnavailableView("Nessuna misura", systemImage: "waveform.path.ecg",
                                       description: Text("Collega l'altoparlante ai puntali e premi Misura."))
            }
        }
    }

    private var frequencyAxis: some AxisContent {
        AxisMarks(values: [10, 20, 50, 100, 200, 500, 1000, 2000, 5000, 10_000, 20_000]) { value in
            AxisGridLine()
            AxisValueLabel {
                if let f = value.as(Double.self) {
                    Text(f >= 1000 ? "\(Int(f / 1000))k" : "\(Int(f))")
                }
            }
        }
    }
}
