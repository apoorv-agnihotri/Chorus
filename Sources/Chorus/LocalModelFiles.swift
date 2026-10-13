import Foundation

/// Local-only discovery: a partial download must not be offered as ready to load.
enum LocalModelFiles {
    static func canLoad(_ directory: URL, watermarkDirectory: URL) -> Bool {
        let support = ["default-conds.safetensors", "speech_emb.npy", "text_emb.npy",
                       "spkr_enc_weight.npy", "spkr_enc_bias.npy", "tokenizer.json", "tokenizer_config.json"]
        return support.allSatisfy { hasFile(directory.appendingPathComponent($0)) }
            && ["T3LM", "S3Encoder", "S3CFM", "S3Vocoder"].allSatisfy { hasModel($0, in: directory) }
            && (hasModel("PerthEncoder", in: directory) || hasModel("PerthEncoder", in: watermarkDirectory))
    }

    private static func hasModel(_ name: String, in directory: URL) -> Bool {
        let compiled = directory.appendingPathComponent(name + ".mlmodelc")
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: compiled.path), !contents.isEmpty { return true }
        let package = directory.appendingPathComponent(name + ".mlpackage")
        return hasFile(package.appendingPathComponent("Manifest.json"))
            && hasFile(package.appendingPathComponent("Data/com.apple.CoreML/model.mlmodel"))
            // Reject missing weights and Git LFS pointers, as the upstream loader does.
            && hasFile(package.appendingPathComponent("Data/com.apple.CoreML/weights/weight.bin"), minimumBytes: 100_000)
    }

    private static func hasFile(_ url: URL, minimumBytes: Int = 1) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]) else { return false }
        return values.isRegularFile == true && (values.fileSize ?? 0) >= minimumBytes
    }
}
