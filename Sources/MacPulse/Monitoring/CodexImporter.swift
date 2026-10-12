#if os(macOS)
import Foundation
import MacPulseCore

enum CodexImporter {
    /// Explicitly selected folder only. Limits the work and skips oversized files.
    static func scan(folder: URL) async throws -> [CodexSession] {
        try await Task.detached(priority: .utility) {
            guard let iterator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
            var result: [String: CodexSession] = [:]
            var files = 0
            for case let file as URL in iterator {
                guard file.pathExtension == "jsonl", let attributes = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]), attributes.isRegularFile == true, (attributes.fileSize ?? 0) < 16_000_000 else { continue }
                files += 1; if files > 500 { break }
                let content = try String(contentsOf: file, encoding: .utf8)
                if let session = CodexParser.parse(lines: content.components(separatedBy: .newlines)) { result[session.id] = session }
            }
            return result.values.sorted { $0.date > $1.date }
        }.value
    }
}
#endif
