#if os(macOS)
import Foundation
import MacPulseCore

struct CodexImportResult { let sessions: [CodexSession]; let skipped: Int }
enum CodexImporter {
    static func scan(folder: URL) async throws -> CodexImportResult {
        try await Task.detached(priority: .utility) {
            guard let iterator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { throw CocoaError(.fileReadNoPermission) }
            var result: [String: CodexSession] = [:], files = 0, skipped = 0
            for case let file as URL in iterator {
                if Task.isCancelled { throw CancellationError() }
                guard file.pathExtension == "jsonl" else { continue }
                guard let attributes = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]), attributes.isRegularFile == true, attributes.isSymbolicLink != true, (attributes.fileSize ?? 0) < 16_000_000 else { skipped += 1; continue }
                files += 1
                if files > 1000 { skipped += 1; continue }
                guard let content = try? String(contentsOf: file, encoding: .utf8), let session = CodexParser.parse(lines: content.components(separatedBy: .newlines)) else { skipped += 1; continue }
                if let existing = result[session.id], existing.lastEvent > session.lastEvent { continue }
                result[session.id] = session
            }
            return CodexImportResult(sessions: result.values.sorted { $0.date > $1.date }, skipped: skipped)
        }.value
    }
}
#endif
