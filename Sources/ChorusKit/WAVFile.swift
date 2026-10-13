import Foundation

/// A temporary PCM WAV. The producing task owns mutations; only finished files
/// cross actor boundaries. Playback and export retain this object to keep its file alive.
public final class WAVFile: @unchecked Sendable {
    public let url: URL
    public private(set) var sampleCount = 0
    public private(set) var peak: Float = 0
    private let folder: URL
    private var handle: FileHandle?
    public var duration: Double { Double(sampleCount) / Double(WAV.sampleRate) }

    public init() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("Chorus-audio-\(UUID().uuidString)", isDirectory: true)
        url = folder.appendingPathComponent("audio.wav")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            try WAV.header(sampleCount: 0).write(to: url)
            handle = try FileHandle(forWritingTo: url)
            try handle?.seekToEnd()
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    deinit {
        try? handle?.close()
        try? FileManager.default.removeItem(at: folder)
    }

    public func append(_ samples: [Float]) throws {
        guard samples.allSatisfy(\.isFinite) else { throw StudioError.invalidAudio("The engine returned invalid audio samples.") }
        let handle = try writableHandle(adding: samples.count)
        // Bound the intermediate PCM allocation, even for a long speed-rendered block.
        for start in stride(from: 0, to: samples.count, by: 8192) {
            try autoreleasepool {
                let end = min(start + 8192, samples.count)
                var pcm = Data(); pcm.reserveCapacity((end - start) * 2)
                for sample in samples[start..<end] {
                    peak = max(peak, abs(sample))
                    let clamped = max(-1, min(1, sample))
                    let value = UInt16(bitPattern: Int16((clamped < 0 ? clamped * 32768 : clamped * 32767).rounded()))
                    pcm.append(UInt8(value & 255)); pcm.append(UInt8(value >> 8))
                }
                try handle.write(contentsOf: pcm)
            }
        }
        sampleCount += samples.count
    }

    public func appendSilence(seconds: Double) throws {
        guard seconds.isFinite, (0...3).contains(seconds) else { throw StudioError.invalidAudio("Pause must be between 0 and 3 seconds.") }
        let count = Int((seconds * Double(WAV.sampleRate)).rounded())
        let handle = try writableHandle(adding: count)
        var remaining = count * 2
        let zeros = Data(repeating: 0, count: 16384)
        while remaining > 0 {
            let bytes = min(zeros.count, remaining)
            try autoreleasepool { try handle.write(contentsOf: zeros.prefix(bytes)) }
            remaining -= bytes
        }
        sampleCount += count
    }

    public func append(contentsOf audio: WAVFile) throws {
        guard audio !== self, audio.handle == nil, audio.sampleCount > 0 else { throw StudioError.invalidAudio("Finish the source audio before joining it.") }
        let handle = try writableHandle(adding: audio.sampleCount)
        let input = try FileHandle(forReadingFrom: audio.url)
        defer { try? input.close() }
        try input.seek(toOffset: 44)
        var remaining = audio.sampleCount * 2
        while remaining > 0 {
            let copied = try autoreleasepool {
                let data = try input.read(upToCount: min(16384, remaining)) ?? Data()
                guard !data.isEmpty else { throw StudioError.invalidAudio("The temporary audio file is incomplete.") }
                try handle.write(contentsOf: data)
                return data.count
            }
            remaining -= copied
        }
        sampleCount += audio.sampleCount; peak = max(peak, audio.peak)
    }

    public func finish() throws {
        guard let handle else { return }
        guard sampleCount > 0 else { throw StudioError.invalidAudio("The engine returned empty audio.") }
        try handle.seek(toOffset: 0)
        try handle.write(contentsOf: WAV.header(sampleCount: sampleCount))
        try handle.close(); self.handle = nil
    }

    /// Fixed-size peaks computed from disk; covers the final partial bin too.
    public func envelope(bins: Int = 160) throws -> [Float] {
        guard handle == nil else { throw StudioError.invalidAudio("Finish the audio before reading its waveform.") }
        guard bins > 0, sampleCount > 0 else { return [] }
        let count = min(bins, sampleCount)
        var peaks = [Float](repeating: 0, count: count)
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        try input.seek(toOffset: 44)
        var offset = 0
        while offset < sampleCount {
            let frames = min(8192, sampleCount - offset)
            try autoreleasepool {
                let data = try input.read(upToCount: frames * 2) ?? Data()
                guard data.count == frames * 2 else { throw StudioError.invalidAudio("The temporary audio file is incomplete.") }
                data.withUnsafeBytes { raw in
                    let bytes = raw.bindMemory(to: UInt8.self)
                    for i in 0..<frames {
                        let pcm = Int16(bitPattern: UInt16(bytes[i * 2]) | UInt16(bytes[i * 2 + 1]) << 8)
                        let value = Float(pcm) / (pcm < 0 ? 32768 : 32767)
                        let bin = min(count - 1, (offset + i) * count / sampleCount)
                        peaks[bin] = max(peaks[bin], abs(value))
                    }
                }
            }
            offset += frames
        }
        return peaks
    }

    public func export(to destination: URL) throws {
        guard handle == nil else { throw StudioError.invalidAudio("Finish the audio before exporting it.") }
        let fm = FileManager.default
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".Chorus-export-\(UUID().uuidString).wav")
        defer { try? fm.removeItem(at: temporary) }
        try fm.copyItem(at: url, to: temporary)
        if fm.fileExists(atPath: destination.path) { _ = try fm.replaceItemAt(destination, withItemAt: temporary) }
        else { try fm.moveItem(at: temporary, to: destination) }
    }

    private func writableHandle(adding count: Int) throws -> FileHandle {
        guard let handle else { throw StudioError.invalidAudio("The audio file has already been finished.") }
        guard count >= 0, count <= (Int(UInt32.max) - 36) / 2 - sampleCount else { throw StudioError.invalidAudio("Audio exceeds the WAV file size limit.") }
        return handle
    }
}

extension WAVFile {
    /// Adjust only quiet speech. Pauses are excluded from the level measurement,
    /// and adequately loud clips are returned byte-for-byte unchanged.
    public func leveledSpeech() throws -> WAVFile {
        guard handle == nil else { throw StudioError.invalidAudio("Finish the audio before leveling it.") }
        let windowFrames = WAV.sampleRate / 50 // 20 ms speech windows
        var energy = 0.0, frames = 0, activeEnergy = 0.0, activeFrames = 0
        func measureWindow() {
            // Ignore pauses and near-silence rather than amplifying noise.
            if frames > 0, energy / Double(frames) >= 0.00001 {
                activeEnergy += energy; activeFrames += frames
            }
            energy = 0; frames = 0
        }
        try readPCM { samples in
            for sample in samples {
                energy += Double(sample) * Double(sample); frames += 1
                if frames == windowFrames { measureWindow() }
            }
        }
        measureWindow()
        guard activeFrames > 0 else { return self }
        let rms = sqrt(activeEnergy / Double(activeFrames))
        // -22 dBFS is the intervention threshold; -20 dBFS the modest target.
        // Do not try to turn near-silence into speech. Never add more than 6 dB.
        guard rms >= 0.005, rms < 0.0794328 else { return self }
        let gain = Float(min(2, 0.1 / rms))
        let output = try WAVFile()
        let limiter = SpeechPeakLimiter(gain: gain)
        try readPCM { samples in
            try Task.checkCancellation()
            try output.append(limiter.process(samples))
        }
        try output.append(limiter.flush())
        try output.finish()
        return output
    }

    private func readPCM(_ body: ([Float]) throws -> Void) throws {
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        try input.seek(toOffset: 44)
        var remaining = sampleCount
        while remaining > 0 {
            try Task.checkCancellation()
            try autoreleasepool {
                let frames = min(8192, remaining)
                let bytes = try input.read(upToCount: frames * 2) ?? Data()
                guard bytes.count == frames * 2 else { throw StudioError.invalidAudio("The temporary audio file is incomplete.") }
                let samples = bytes.withUnsafeBytes { raw -> [Float] in
                    let data = raw.bindMemory(to: UInt8.self)
                    return (0..<frames).map { i in
                        let pcm = Int16(bitPattern: UInt16(data[i * 2]) | UInt16(data[i * 2 + 1]) << 8)
                        return Float(pcm) / (pcm < 0 ? 32768 : 32767)
                    }
                }
                try body(samples)
                remaining -= frames
            }
        }
    }
}

/// A short lookahead catches isolated peaks before they reach playback/export.
/// Gain recovers over 80 ms; no per-chunk normalization, added delay, or hard clip.
private final class SpeechPeakLimiter {
    private let gain: Float
    private let ceiling: Float = 0.85
    private let lookahead = WAV.sampleRate / 200 // 5 ms
    private let release = Float(exp(-1 / (0.08 * Double(WAV.sampleRate))))
    private var attenuation: Float = 1
    private var ring: [Float]
    private var written = 0
    private var emitted = 0
    private var peaks: [(index: Int, value: Float)] = []
    private var head = 0

    init(gain: Float) {
        self.gain = gain
        ring = [Float](repeating: 0, count: WAV.sampleRate / 200 + 1)
    }
    func process(_ samples: [Float]) -> [Float] {
        var result: [Float] = []; result.reserveCapacity(samples.count)
        for sample in samples {
            let value = sample * gain
            ring[written % ring.count] = value
            while peaks.count > head, peaks.last!.value <= abs(value) { peaks.removeLast() }
            peaks.append((written, abs(value)))
            written += 1
            if written - emitted > lookahead { result.append(next()) }
        }
        return result
    }
    func flush() -> [Float] {
        var result: [Float] = []; result.reserveCapacity(written - emitted)
        while emitted < written { result.append(next()) }
        return result
    }
    private func next() -> Float {
        while head < peaks.count, peaks[head].index < emitted { head += 1 }
        let peak = head < peaks.count ? peaks[head].value : 0
        let allowed = peak > ceiling ? ceiling / peak : 1
        attenuation = min(allowed, 1 - (1 - attenuation) * release)
        let sample = ring[emitted % ring.count] * attenuation
        emitted += 1
        if head > 256 { peaks.removeFirst(head); head = 0 }
        return sample
    }
}
