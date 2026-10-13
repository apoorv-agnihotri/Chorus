# Developer guide

The public release downloads Nano and Kokoro together during first-run setup.
Turbo remains optional. The sections below describe the runtime and developer tools.

A native, offline voice studio for Apple Silicon Macs. SwiftUI, Kokoro-82M voice references and Chatterbox narration
Turbo or Nano voices, local reference voices, and 24 kHz PCM WAV export. No accounts.

## Build and run

Requires an Apple Silicon Mac, macOS 15+, and Swift 6.2+ with a macOS 26 SDK
(Xcode 26 or recent Command Line Tools). The SDK is needed to compile Liquid
Glass; the resulting app falls back to native material on macOS 15.

```sh
cd Chorus
bash scripts/build-app.sh
open dist/Chorus.app
```

The first build fetches open-source Swift dependencies. `Package.resolved` pins
them. The app bundle is ad hoc signed for local use. Distributing a notarized
release requires your Apple Developer signing identity and notarization
credentials; neither is needed to build or use this local app.

## Use the studio

1. Click **Create voice** to open **Voice Lab**. Choose one trait from **Identity**,
   **Pitch & Body**, **Texture**, **Delivery**, and **Character Style**. Create a
   sample, listen, give it a name, and save it. **Randomize** chooses from all available traits
   with a saved seed.
   **Another take** retains the traits and changes the synthesis seed. Any trait
   change requires a new sample before saving. Kokoro creates a clean reference,
   Chatterbox encodes and previews it, and saved pitch/EQ/texture/pacing is applied
   once after narration. Reference encodings are cached per Kokoro base.
   All five categories have 20 selectable choices matching the supplied catalog.
   Natural age, breathiness, emotion, and genre labels are experimental
   approximations, not validated new model capabilities. Chatterbox expression
   tags remain available; explicit script delivery tags override Lab suggestions.
   Existing Pocket voices remain readable for compatibility; new Lab voices use
   Kokoro and Chatterbox only.

Cached engines load on first generation rather than at launch. After two idle
minutes, Chorus releases the synthesis models and automatically reloads them for
the next generation. **Local engine → Unload engine** (also in the Studio menu)
releases the engine immediately; Chatterbox needs Load to enable it again, while
Kokoro and character voices wake automatically for the next preview/generation. Playback and WAV
export remain available. Cloning releases synthesis models before loading its
reference encoders. Reloading trades some first-generation latency for lower idle
memory; Core ML can retain system caches after app-owned model references are released.

**Import script** (⌘I) accepts the format in `examples/dialogue.txt`. Speaker tags
must be alone on a line and use a single name, underscores, or hyphens. Speaker
names are matched without case sensitivity. Chatterbox supports the **Expression**
menu. Reactions are `[laugh]`, `[chuckle]`, `[sigh]`, `[gasp]`, `[cough]`,
`[clear throat]`, `[shush]`, `[groan]`, and `[sniff]`. Experimental styles are
`[happy]`, `[angry]`, `[surprised]`, `[whispering]`, `[crying]`, `[sarcastic]`,
`[dramatic]`, `[fear]`, `[narration]`, and `[advertisement]`. These tags stay in
speech even on a line of their own; known expression names are reserved and cannot
serve as standalone speaker tags. Case is normalized before inference. Arbitrary
stage directions are rejected at generation. Kokoro and character voices reject expression tags with a
clear message; use punctuation for pauses or choose a Chatterbox voice for reactions.
`[gasps]` is accepted as an alias and normalized to the model's `[gasp]` token.
Unrecognized standalone single-word tags are speaker names by definition.

Click **Add dialogue**, choose a voice on the block, and enter its text. Each block's
voice can be changed independently, including blocks imported with the same speaker
tag. The voice menu includes bundled voices and your saved and cloned voices.
In **Voice Library → Your voices**, **Delete** removes a saved voice after confirmation.
Bundled voices cannot be deleted. Blocks using a deleted voice switch to Rue; any
unshared recording file moves to the Mac's Trash.

Generated speech is measured per dialogue block or preview. Quiet speech receives
at most 6 dB of gain with short lookahead peak protection and a sample ceiling of
−1.4 dBFS. Speech windows below −50 dBFS are excluded from the measurement. Clips
already at −22 dBFS active RMS or louder, silence, and near-silence pass through
unchanged. This modest level correction applies to both playback and WAV exports;
it preserves duration and pitch. This is an RMS-based adjustment, not LUFS mastering.

The current workspace saves automatically. Missing voices are shown in the picker
and must be reassigned before generation. Use **New script** to start again and
**Export WAV** to save your generated audio.

English text normalization runs locally before every generation, including dialogue
and voice previews. Editor text and saved scripts are preserved. For example,
`2:00 a.m.` becomes `two in the morning`, `3:45 p.m.` becomes
`three forty-five in the afternoon`, `6.9` becomes `six point nine`,
`₹1,500` becomes `one thousand five hundred rupees`, and `HELLO THERE!` becomes
`Hello there!`. Common titles (`Dr.`, `Mr.`, `Prof.`), dotted initialisms,
and known acronyms (`AI`, `TTS`, `WAV`, etc.) get spoken forms. Currency supports
rupees, dollars, pounds and euros, including minor units; decimals retain each
fractional digit. Bare valid H:MM times are read without guessing a.m./p.m.
Reaction tags, URLs, email addresses, identifiers, dotted versions, and explicit
ISO/slash dates are preserved. This is a bounded English normalizer, not a general
date, phone-number, duration or locale-dependent pronunciation system. Unknown
abbreviations are left to the model. See `examples/normalization-check.txt`.

## Local files and network behavior

Application data lives in `~/Library/Application Support/Chorus/`:

- `studio.json`: autosaved project, single-voice text, voice library, engine path.
- `Models/hub/`: downloaded Core ML packages and reference encoders.
- `Voices/`: local `*-conds.safetensors` voice conditioning files.
- `Models/Pocket/`: Pocket weights, tokenizer, and eight conditioning embeddings.
- `Models/Kokoro/`: the separately downloaded Kokoro Core ML models and voice packs.

The upstream compiler keeps compiled artifacts in its Application Support cache.
Audio preview uses temporary PCM WAV files, removed when replaced, when a script
is reset, or when their owning objects are released on normal exit. There is no analytics or server.
First-use model setup uses the network, including the first character sample
and legacy Kokoro preview. Cached model loading, inference, playback, and export
operate locally. The native MLX runtime uses a bundled, version-matched Metal
shader library (about 150 MB installed, 47 MB compressed) and no Python runtime. The app loads the Perth watermark directly
from local files, bypassing upstream's implicit download fallback. A local model
folder needs a local Perth encoder too, or the one-time setup completed in the
app's model cache. The supplied runtime uses Core ML with ANE/GPU/CPU placement
chosen by the engine; not every component runs on the Neural Engine.

## Verification

```sh
bash scripts/test.sh
swift run -c release chorus-check --download nano --home ./models --out ./smoke.wav
swift run -c release chorus-check --model-dir PATH --home ./models --out ./dialogue.wav --script examples/dialogue.txt
```

`chorus-check` runs real inference, rejects empty/invalid/silent output, and writes
audio duration, generation time, and realtime factor alongside the WAV. Use
`--reference AUDIO --voice-out CONDS --voice CONDS` to test on-device cloning.
Use `/usr/bin/time -l` around the built checker to measure peak process memory.
`chorus-check --audio-memory-benchmark legacy|file` compares one hour of synthetic
audio assembly through the previous in-memory path and the file-backed path,
without loading models. This measures audio retention, not full TTS inference.
The self-contained Swift test runner works without Xcode's test frameworks.
Tests cover script parsing, expression preservation, project validation, PCM
headers/clipping, dialogue spacing, legacy clone migration, preset persistence,
and speed rendering duration and pitch. `chorus-check` also accepts `--text`,
`--speed`, `--variation`, `--sentence-pause`, `--clause-pause`, and `--expression`.

See `VALIDATION.md` for measured Nano inference and local voice-creation
results on the development Mac. `Vendor/swift-transformers` contains an attributed
Hub/Tokenizers subset with a small fix for resource lookup in signed app bundles.
See `MEMORY.md` for the 0.3.3 model lifecycle, memory measurements and the
automatic-placement loading fix verified on macOS 27.

This is an MVP: expressive quality and model performance need evaluation on
multiple Macs. The HLD's 3–4 GB incremental RAM is a target, not a guarantee.
Cancellation is cooperative and can wait for an in-flight Core ML step. Long
projects store completed audio on disk, with bounded PCM copy/waveform buffers.
At 1× speed, engine chunks go directly to a temporary WAV. Other speeds still
buffer one dialogue block for pitch-preserving time stretching. The app supports
English Turbo/Nano, not multilingual, a DAW, or a chatbot. Delivery variation
controls sampling temperature, not emotional intensity; Turbo/Nano ignore CFG
and exaggeration, so those sliders are deliberately absent. Pauses split synthesis
at sentence/comma boundaries and can affect continuity. Preview experimental
styles rather than assuming token presence guarantees a particular performance.

MIT. See `THIRD_PARTY_NOTICES.md` and bundled dependency licenses.

## Kokoro integration

See [KOKORO.md](KOKORO.md) for runtime placement, memory measurements,
and the real-engine check command. Only one synthesis engine is kept resident when
switching between Kokoro and Chatterbox voices.
