import SwiftUI
import UniformTypeIdentifiers

nonisolated enum ImpedanceExport {
    /// Plain text "frequency magnitude phase", the format most crossover and
    /// box design tools read as .zma.
    static func zma(_ curve: [ImpedancePoint]) -> String {
        curve.map { String(format: "%.4f\t%.4f\t%.3f", $0.frequency, $0.magnitude, $0.phase) }
            .joined(separator: "\n") + "\n"
    }
}

extension UTType {
    nonisolated static let zma = UTType(filenameExtension: "zma", conformingTo: .plainText) ?? .plainText
}

nonisolated struct TextFile: FileDocument {
    static let readableContentTypes: [UTType] = [.zma, .plainText]
    var text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
