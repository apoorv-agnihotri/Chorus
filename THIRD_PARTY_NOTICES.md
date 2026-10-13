# Third-party notices

Chorus app code is MIT licensed. Model weights are separate downloads; the app's
license does not confer ownership of those weights or reference recordings.

- Chatterbox models and reference implementation: Resemble AI, MIT.
  https://github.com/resemble-ai/chatterbox
  https://huggingface.co/ResembleAI/chatterbox-turbo
  https://huggingface.co/ResembleAI/chatterbox-nano
- ChatterboxCoreML runtime and Core ML conversion artifacts: Ilia Sazonov, MIT.
  https://github.com/iliasaz/chatterbox-coreml
  https://huggingface.co/iliasaz/chatterbox-turbo-coreml
  https://huggingface.co/iliasaz/chatterbox-nano-coreml
- Kokoro-82M: hexgrad and its credited contributors, Apache-2.0. Five synthetic
  reference recordings were generated at development time using the MLX Audio
  conversion `mlx-community/Kokoro-82M-bf16`. Chorus ships derived Chatterbox
  conditioning profiles. New Kokoro presets use the native Core ML runtime,
  with model weights downloaded separately during first-run setup (or on first use if setup is skipped).
  https://huggingface.co/hexgrad/Kokoro-82M
  https://huggingface.co/mlx-community/Kokoro-82M-bf16
  https://github.com/hexgrad/kokoro
  https://github.com/Blaizzy/mlx-audio
- KokoroCoreML runtime/conversion: Jud, Apache-2.0; includes Misaki-derived
  English phonemization (Apache-2.0) and swift-bart-g2p (Apache-2.0).
  https://github.com/Jud/kokoro-coreml
  https://github.com/Jud/swift-bart-g2p
- Perth watermarking: Resemble AI, MIT; Core ML runtime by Ilia Sazonov, MIT.
  https://github.com/resemble-ai/Perth
  https://github.com/iliasaz/perth-coreml
- RUAccent: Denis Petrov, MIT; Core ML runtime by Ilia Sazonov, MIT. This is a
  transitive dependency; Chorus exposes only English Turbo and Nano.
  https://github.com/iliasaz/ruaccent-coreml
- Hugging Face swift-transformers and swift-huggingface: Apache-2.0.
- Hugging Face swift-jinja: Apache-2.0.
- jkrukowski/swift-safetensors: MIT.
- Apple swift-collections, swift-crypto, swift-asn1: Apache-2.0 with Swift exception.
- ibireme/yyjson: MIT. mattt/EventSource: MIT.

The build script includes each resolved dependency's original LICENSE and NOTICE
files in `Chorus.app/Contents/Resources/ThirdPartyLicenses`. `Package.resolved`
records exact versions and revisions. See the upstream ChatterboxCoreML NOTICE
for complete model attribution and `Vendor/swift-transformers/UPSTREAM.md` for
the attributed Hub/Tokenizers subset and its macOS resource lookup modification.
Its Apache-2.0 license is bundled. Chatterbox speech retains the upstream Perth watermark. Kokoro speech is not
Perth-watermarked. Reference voices require recordings you own or are authorized to use.

The hidden compatibility English podcast voice is derived from Resemble AI's own published
`female_random_podcast.wav` demo prompt by the ChatterboxCoreML project's local
voice encoders. The conditioning bundle is included with its upstream provenance
in `Sources/Chorus/Resources/Voices/LEGACY_PODCAST_PROVENANCE.md`; the source recording is not
redistributed. Copyright and source attribution are retained in the app bundle.
Speed processing occurs after synthesis; watermark detection after this audio
transformation has not been measured.

The five public base voices are fictional Chorus personas derived from Kokoro
voices. Their source IDs, prompts, snapshot revision, and asset hashes are recorded
in `Sources/Chorus/Resources/Voices/REFERENCE_MANIFEST.json`. Kokoro's Apache license
and `PROVENANCE.md` are included alongside those profiles in the app bundle. Atlas
is an original synthetic narrator profile; no named actor's recording was used.

## Character voice runtime

Pocket TTS is by Kyutai. Chorus downloads the public MLX conversion
`mlx-community/pocket-tts`, pinned at
`cbf71d5f6657bbc3f4bc02f85ee408261225bec7`, with its eight preset embeddings. The conversion declares CC BY 4.0; credit
Kyutai and the MLX community conversion. Model license:
https://creativecommons.org/licenses/by/4.0/
Model provenance: https://huggingface.co/mlx-community/pocket-tts
Upstream: https://github.com/kyutai-labs/pocket-tts

The native Pocket/Mimi/tokenizer implementation is adapted from Prince Canuma's
mlx-audio-swift (MIT), revision `244458d7b61e54ff135073ddc9ed76782bb20758`.
Its original license is included as `POCKET_RUNTIME_LICENSE`; modifications are
documented in `Sources/ChorusPocket/UPSTREAM.md`.
Apple MLX and mlx-swift 0.31.2 are MIT licensed. The bundled shader library comes
from the official mlx-metal 0.31.2 distribution. See `Vendor/mlx-swift/UPSTREAM.md`
and the bundled MLX license. Character DSP is performed after synthesis; Pocket
audio has no Perth watermark. Character prompts select synthetic bases and
processing recipes; they do not download recordings of named characters or actors.
