# Chorus 0.3 bundled voice provenance

The five public English base voices are fictional personas. Their reference audio
was generated locally from Kokoro-82M using MLX Audio 0.4.8, then converted into
Chatterbox conditioning profiles with the shared Core ML VoiceCloner. No human
recording was used to create these five profiles and no additional TTS runtime is
required in the app. Chatterbox Turbo or Nano generates all user speech.

| Chorus name | Source voice | Intended role | Reference duration | Default delivery |
|---|---|---|---|---|
| Rue | af_bella | Female actor, expressive and cinematic | 15.950 s | 1.00×, dramatic |
| Kai | am_fenrir | Male actor, grounded and bold | 15.425 s | 1.00×, dramatic |
| Atlas | am_onyx | Deep male narrator, measured | 17.875 s | 0.90×, narration |
| Zia | af_heart | Female advertising, bright and enthusiastic | 17.975 s | 1.10×, advertisement |
| Indie | af_nicole | Female, relaxed and laid-back | 28.175 s | 0.95×, natural |

These role descriptions are creative directions, not guarantees of emotion on
all text. Style tokens remain experimental; users can choose natural delivery or
another style and preview before saving. Speed and pauses are rendered into WAV.
Atlas uses a synthetic Kokoro voice, with no reference to a named actor's audio.

## Sources and license

- Original model: https://huggingface.co/hexgrad/Kokoro-82M (Apache-2.0 weights).
- MLX snapshot: https://huggingface.co/mlx-community/Kokoro-82M-bf16/tree/a71e4d38b236d968966a2002c4c895dbd12b1c3c
- Generation runtime: https://github.com/Blaizzy/mlx-audio (0.4.8).
- Voice encoders: https://github.com/iliasaz/chatterbox-coreml at
  b8288834e783f3a6210757fbaf62f9014220bff9 (MIT).

`KOKORO_LICENSE` retains the source project's Apache-2.0 license. Exact source
voice IDs, generation speed, reference text, WAV hashes, and conditioning hashes
are recorded in `REFERENCE_MANIFEST.json`. Source model weights and generated
reference WAVs are not shipped. The original upstream model credits are at
https://huggingface.co/hexgrad/Kokoro-82M#acknowledgements.

## Reproduce

Use Python with mlx-audio 0.4.8 and misaki[en], and a downloaded local snapshot:

```sh
HF_HUB_OFFLINE=1 python scripts/prepare-bundled-voices.py \
  --model-dir /path/to/Kokoro/snapshot \
  --output-dir dist/voice-build/references
swift build -c release --product chorus-check
.build/release/chorus-check --prepare-voices dist/voice-build/references \
  --voices-out Sources/Chorus/Resources/Voices \
  --model-dir /path/to/chatterbox-nano-coreml
```

VoiceCloner uses MatchaMel, VEMel, VELSTM, S3Tokenizer, and CAMPPlus. Its conditioning
files work with Turbo and Nano. The 15+ second references provide full conditioning
windows for the encoders. Runtime voice settings are defined in BundledVoice.swift.

## Compatibility

`female_random_podcast-conds.safetensors` is retained solely to keep existing 0.2
presets working. It is not listed in the bundled library or new-base selector.
Its original upstream provenance is in `LEGACY_PODCAST_PROVENANCE.md`. The previous
model-default ID is similarly resolved only for existing projects and presets.
