import Foundation

/// Core ML can report a model-type error when accelerator loading fails, even
/// for a valid multifunction ML Program. Retry that error once on CPU.
public enum ModelLoadRecovery {
    public static func load<Value>(primary: () async throws -> Value,
                                   cpuFallback: () async throws -> Value) async throws -> Value {
        try Task.checkCancellation()
        do { return try await primary() }
        catch {
            try Task.checkCancellation()
            guard shouldRetryOnCPU(error) else { throw error }
            return try await cpuFallback()
        }
    }

    public static func shouldRetryOnCPU(_ error: Error) -> Bool {
        if error is CancellationError { return false }
        var current: NSError? = error as NSError
        // Bounded traversal also protects against malformed underlying-error cycles.
        for _ in 0..<8 {
            guard let issue = current else { break }
            let message = issue.localizedDescription.lowercased()
            if message.contains("functionname"), message.contains("must be"),
               message.contains("nil"), message.contains("ml program") { return true }
            current = issue.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return false
    }
}
