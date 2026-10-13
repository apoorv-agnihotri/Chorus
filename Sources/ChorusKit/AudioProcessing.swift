import AVFoundation

public enum AudioProcessing {
    /// Renders the speed change into exported PCM while preserving voice pitch.
    public static func changeSpeed(_ samples: [Float], rate: Double) throws -> [Float] {
        guard rate.isFinite, (0.75...1.35).contains(rate), !samples.isEmpty, samples.allSatisfy(\.isFinite) else {
            throw StudioError.invalidAudio("Invalid audio or playback speed.")
        }
        guard abs(rate - 1) > 0.001 else { return samples }
        let engine = AVAudioEngine(), source = AVAudioPlayerNode(), stretch = AVAudioUnitTimePitch()
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(WAV.sampleRate), channels: 1, interleaved: false)!
        engine.attach(source); engine.attach(stretch); stretch.rate = Float(rate)
        engine.connect(source, to: stretch, format: format)
        engine.connect(stretch, to: engine.mainMixerNode, format: format)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
        try engine.start()
        defer { source.stop(); engine.stop() }
        let latency = Int((stretch.auAudioUnit.latency * Double(WAV.sampleRate)).rounded(.up))
        let padding = max(WAV.sampleRate / 4, latency * 2)
        let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count + padding))!
        input.frameLength = input.frameCapacity
        input.floatChannelData![0].update(from: samples, count: samples.count)
        input.floatChannelData![0].advanced(by: samples.count).initialize(repeating: 0, count: padding)
        source.scheduleBuffer(input); source.play()
        let expected = Int((Double(samples.count) / rate).rounded())
        let total = expected + latency
        let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: engine.manualRenderingMaximumFrameCount)!
        var rendered: [Float] = []; rendered.reserveCapacity(total)
        var stalled = 0
        while rendered.count < total {
            let frames = AVAudioFrameCount(min(Int(buffer.frameCapacity), total - rendered.count))
            let result = try engine.renderOffline(frames, to: buffer)
            switch result {
            case .success:
                if buffer.frameLength > 0 {
                    rendered.append(contentsOf: UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
                    stalled = 0
                } else { stalled += 1 }
            case .cannotDoInCurrentContext, .insufficientDataFromInputNode: stalled += 1
            case .error: throw StudioError.invalidAudio("Could not render the voice's speed setting.")
            @unknown default: throw StudioError.invalidAudio("Unsupported audio rendering state.")
            }
            guard stalled < 20 else { throw StudioError.invalidAudio("Audio speed rendering stalled.") }
        }
        let output = Array(rendered.dropFirst(latency).prefix(expected))
        guard output.allSatisfy(\.isFinite) else { throw StudioError.invalidAudio("Speed rendering produced invalid audio.") }
        return output
    }
    /// Shared by preview and export so an accepted sample keeps its character.
    public static func renderCharacter(_ samples: [Float], recipe: CharacterVoiceRecipe) throws -> [Float] {
        _ = try recipe.validated()
        guard !samples.isEmpty, samples.allSatisfy(\.isFinite) else { throw StudioError.invalidAudio("Invalid character audio.") }
        let engine = AVAudioEngine(), source = AVAudioPlayerNode(), pitch = AVAudioUnitTimePitch(), eq = AVAudioUnitEQ(numberOfBands: 3)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(WAV.sampleRate), channels: 1, interleaved: false)!
        pitch.pitch = Float(recipe.pitchCents); pitch.rate = Float(recipe.speed)
        eq.bands[0].filterType = .parametric; eq.bands[0].frequency = Float(recipe.focusHz)
        eq.bands[0].bandwidth = 1; eq.bands[0].gain = Float(recipe.focusGain); eq.bands[0].bypass = false
        eq.bands[1].filterType = .parametric; eq.bands[1].bandwidth = 1
        eq.bands[1].frequency = Float(recipe.bodyEQ?.frequency ?? 180); eq.bands[1].gain = Float(recipe.bodyEQ?.gain ?? 0)
        eq.bands[1].bypass = recipe.bodyEQ == nil
        eq.bands[2].filterType = .highPass; eq.bands[2].frequency = 65; eq.bands[2].bypass = false
        for node in [source as AVAudioNode, pitch, eq] { engine.attach(node) }
        engine.connect(source, to: pitch, format: format); engine.connect(pitch, to: eq, format: format); engine.connect(eq, to: engine.mainMixerNode, format: format)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
        try engine.start(); defer { source.stop(); engine.stop() }
        let latency = Int((pitch.auAudioUnit.latency * format.sampleRate).rounded(.up))
        let padding = max(WAV.sampleRate / 2, latency * 2)
        let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count + padding))!
        input.frameLength = input.frameCapacity
        input.floatChannelData![0].update(from: samples, count: samples.count)
        input.floatChannelData![0].advanced(by: samples.count).initialize(repeating: 0, count: padding)
        source.scheduleBuffer(input); source.play()
        let expected = Int((Double(samples.count) / recipe.speed).rounded()), total = expected + latency
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096)!
        var rendered: [Float] = [], stalled = 0
        while rendered.count < total {
            try Task.checkCancellation()
            let state = try engine.renderOffline(AVAudioFrameCount(min(4096, total - rendered.count)), to: buffer)
            if state == .success, buffer.frameLength > 0 {
                rendered.append(contentsOf: UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength))); stalled = 0
            } else { stalled += 1 }
            guard stalled < 20 else { throw StudioError.invalidAudio("Character audio rendering stalled.") }
        }
        rendered = Array(rendered.dropFirst(latency).prefix(expected))
        let peak = rendered.map { abs($0) }.max() ?? 0
        guard peak > 0.0001, rendered.allSatisfy(\.isFinite) else { throw StudioError.invalidAudio("Character voice produced no audible speech.") }
        for i in rendered.indices {
            let clean = rendered[i] / peak * 0.85
            let grit = Float(recipe.grit), robot = Float(recipe.robot)
            let saturated = clean * (1 - grit) + tanh(clean * 3) * grit * 0.85
            let modulation = Float(sin(2 * Double.pi * 65 * Double(i) / format.sampleRate))
            rendered[i] = saturated * (1 - robot) + saturated * modulation * robot
        }
        return rendered
    }

}
