import Foundation

/// Deterministic 24 kHz, mono, signed 16-bit PCM. No platform encoder or compressed intermediates.
public enum WAV {
    public static let sampleRate = 24_000
    public static func encode(_ samples: [Float]) throws -> Data {
        guard !samples.isEmpty else { throw StudioError.invalidAudio("The engine returned empty audio.") }
        guard samples.count <= (Int(UInt32.max) - 36) / 2 else { throw StudioError.invalidAudio("Audio exceeds the WAV file size limit.") }
        guard samples.allSatisfy(\.isFinite) else { throw StudioError.invalidAudio("The engine returned invalid audio samples.") }
        var data = try header(sampleCount: samples.count)
        data.reserveCapacity(44 + samples.count * 2)
        for sample in samples {
            let clamped = max(-1, min(1, sample))
            let value = UInt16(bitPattern: Int16((clamped < 0 ? clamped * 32768 : clamped * 32767).rounded()))
            data.append(UInt8(value & 255)); data.append(UInt8(value >> 8))
        }
        return data
    }
    static func header(sampleCount: Int) throws -> Data {
        guard sampleCount >= 0, sampleCount <= (Int(UInt32.max) - 36) / 2 else { throw StudioError.invalidAudio("Audio exceeds the WAV file size limit.") }
        var data = Data()
        func ascii(_ s: String) { data.append(contentsOf: s.utf8) }
        func u16(_ v: UInt16) { data.append(UInt8(v & 255)); data.append(UInt8(v >> 8)) }
        func u32(_ v: UInt32) { for shift in stride(from: 0, to: 32, by: 8) { data.append(UInt8((v >> shift) & 255)) } }
        let bytes = UInt32(sampleCount * 2)
        ascii("RIFF"); u32(36 + bytes); ascii("WAVEfmt "); u32(16)
        u16(1); u16(1); u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 2)); u16(2); u16(16)
        ascii("data"); u32(bytes)
        return data
    }
    public static func stitch(_ clips: [[Float]], pause: Double) throws -> [Float] {
        guard pause.isFinite, (0...3).contains(pause) else { throw StudioError.invalidAudio("Pause must be between 0 and 3 seconds.") }
        guard !clips.isEmpty, clips.allSatisfy({ !$0.isEmpty }) else { throw StudioError.invalidAudio("Every dialogue block must have audio.") }
        var result: [Float] = []
        let silence = [Float](repeating: 0, count: Int((pause * Double(sampleRate)).rounded()))
        for (i, clip) in clips.enumerated() {
            if i > 0 { result.append(contentsOf: silence) }
            result.append(contentsOf: clip)
        }
        return result
    }
    public static func envelope(_ samples: [Float], bins: Int = 160) -> [Float] {
        guard bins > 0, !samples.isEmpty else { return [] }
        let stride = max(1, samples.count / bins)
        return (0..<min(bins, samples.count)).map { i in
            let start = i * stride, end = min(samples.count, (i + 1) * stride)
            return samples[start..<end].reduce(Float(0)) { max($0, abs($1)) }
        }
    }
}
