import Foundation
import ChorusKit

typealias BuiltInVoice = BundledVoice

extension BundledVoice {
    func conditioningURL() throws -> URL? {
        guard let resource else { return nil }
        // SwiftPM bundle lookup also supports packaged native .app resources.
        let packaged = Bundle.main.resourceURL?.appendingPathComponent("Chorus_Chorus.bundle")
        let bundle = packaged.flatMap(Bundle.init(url:)) ?? Bundle.module
        guard let url = bundle.url(forResource: resource, withExtension: "safetensors", subdirectory: "Voices") else {
            throw EngineFailure.message("The bundled voice for \(name) is missing. Rebuild or reinstall Chorus.")
        }
        return url
    }
}
