import SwiftUI

enum Page: String, CaseIterable, Identifiable {
    case impedance, parameters, generator, calibration

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .impedance: "Impedance"
        case .parameters: "T/S Parameters"
        case .generator: "Generator"
        case .calibration: "Calibration"
        }
    }

    var symbol: String {
        switch self {
        case .impedance: "waveform.path.ecg"
        case .parameters: "speaker.wave.2"
        case .generator: "waveform"
        case .calibration: "slider.horizontal.3"
        }
    }
}

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var page: Page? = .impedance

    var body: some View {
        NavigationSplitView {
            List(Page.allCases, selection: $page) { page in
                Label(page.title, systemImage: page.symbol)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } detail: {
            Group {
                switch page ?? .impedance {
                case .impedance: ImpedanceView()
                case .parameters: ParametersView()
                case .generator: GeneratorView()
                case .calibration: CalibrationView()
                }
            }
            .safeAreaInset(edge: .bottom) { StatusBar() }
        }
    }
}

struct StatusBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            if model.isBusy {
                ProgressView(value: model.progress).frame(width: 160)
                Button("Cancel", action: model.cancel)
            }
            Text(model.status).foregroundStyle(.secondary)
            if let warning = model.warning {
                Label(warning, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
            Spacer()
            if !model.calibration.isComplete {
                Label("Not calibrated", systemImage: "exclamationmark.circle").foregroundStyle(.orange)
            }
        }
        .font(.callout)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

#Preview {
    ContentView().environment(AppModel())
}
