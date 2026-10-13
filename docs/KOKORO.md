# Kokoro in Chorus 0.4.0

Create voice defaults to Kokoro. Choose from 20 American English voices, set
speed (0.75–1.35×), preview, and save. A saved preset stores its source voice ID
and delivery settings, not rendered audio. It appears in the voice library and
both the single-voice and dialogue pickers. Editing the source voice or speed
invalidates previously generated output.

First preview or generation downloads the pinned `models-2026-03-23` Core ML
archive from Jud/kokoro-coreml (~103 MB download, ~106 MB installed) into
Application Support/Chorus/Models/Kokoro. Installation uses a staging folder;
cancelled/failed downloads cannot leave a complete-looking installation. Later
generation works offline. Saving a preset requires no download.

The runtime is pinned to `6bfc02afb237a311caee927482e58c028edb6acb`. It uses native
English phonemization with bundled BART fallback, not Python or MLX. American
English voices match the included US phonemizer. Other languages and UK presets
are intentionally not offered yet. This is preset creation, not prompt-based
voice design, reference cloning, or voice blending. Chatterbox remains available
for reference cloning and expression tags. Kokoro rejects those tags with an
explanation rather than reading or silently dropping them.

## Model lifecycle and compute

LocalEngine serializes inference and releases the previous synthesis engine
before switching between Chatterbox and Kokoro. Neither engine loads at launch.
Kokoro is retained for subsequent requests, then released after two idle minutes
or through Unload Engine. WAV output remains backed by temporary files. Kokoro
text is split at sentence boundaries and capped at 350 characters per inference;
results are written to disk inside autorelease pools. Cancellation is checked
between chunks and before/after installation. A running Core ML prediction must
finish before cancellation completes.

CPU compute is currently selected. The default GPU path stalled inside the
macOS 27 Metal driver on the development M1 Pro; CPU mode completed synthesis.
GPU placement can be revisited after validating that driver/runtime combination.

## Verified on M1 Pro, 32 GB, macOS 27

- All 17 ChorusKit suites passed, including legacy voice decoding, Kokoro recipe
  persistence, invalid recipes/settings, unsupported expressions, and bounded
  text preparation.
- The final packaged app displayed the Kokoro/Chatterbox Create Voice tab,
  downloaded models, played its Heart preview, saved `Kokoro Heart`, and reopened
  Customize with the correct source and speed. The existing four local voices
  remained in the library. Screenshot: `appearance/kokoro-customize.png`.
  Existing generated audio was exported before restarting the app.
- Heart, default speed: 89,400 samples / 3.725 seconds of audio, generated in
  1.99 seconds including cold model load. WAV is 24 kHz mono 16-bit PCM, peak
  0.95, RMS 0.15.
- Onyx, 0.9×: first-use download + inference passed; 552,840 samples / 23.035
  seconds of audio generated in 5.86 seconds (download excluded from synthesis
  timer). Fresh install and generation took 70.28 seconds total.
- `/usr/bin/time -l` isolated checker peak memory footprint: Heart 804 MiB;
  Onyx longer passage with first download 1,429 MiB. Maximum RSS: 935 MiB and
  1,657 MiB respectively. These are process peaks, not app idle-memory figures
  or promises for arbitrary scripts. Kokoro is not automatically a lower-memory
  replacement for Nano. Core ML working sets vary with input length and caches.

## Reproduce

```sh
swift build -c release --cache-path .build/cache --disable-sandbox --product chorus-check
.build/release/chorus-check --download-kokoro --kokoro-dir /tmp/chorus-kokoro \
  --kokoro-voice af_heart --speed 1 --out /tmp/kokoro-preview.wav
```

Omit `--download-kokoro` for an already downloaded folder. Use `--text` to test
another passage. No system speech or mock audio is substituted.
