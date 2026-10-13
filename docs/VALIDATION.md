# Local validation — 11 October 2026

The following sections record earlier releases. For 0.3.3, see [Memory lifecycle
and validation](MEMORY.md), including native idle release, current memory
measurements, file-backed audio and the macOS 27 model-loading fix.

Hardware: Apple M1 Pro, 32 GiB RAM. Release build, Swift 6.3.3, macOS 26 SDK.
Engine: ChatterboxCoreML revision b8288834e783f3a6210757fbaf62f9014220bff9.
Model: `iliasaz/chatterbox-nano-coreml`, downloaded through the app's model setup.

## Completed checks

- All six core test suites passed: tagged dialogue/reaction import, malformed
  script rejection, multiline text, WAV encoding/clipping, exact clip spacing,
  and Codable project validation/roundtrip.
- Real Nano inference produced three dialogue clips, joined with two 0.3-second
  pauses. Result: 145,920 frames, mono, 24,000 Hz, signed 16-bit PCM, 6.08 seconds.
- Initial model load: 14.78 seconds. First dialogue generation: 22.31 seconds
  (3.67 seconds of generation per second of audio). This includes cold execution
  overhead and is not a promise of realtime performance.
- `/usr/bin/time -l` measured 1,007,452,160 bytes maximum RSS and 1,039,337,080
  bytes peak memory footprint for the checker including model loading. This is
  total process memory, not an isolated incremental model RAM measurement.
- On-device VoiceCloner created a conditioning bundle from a 12.16-second
  synthetic reference assembled from the test output. A subsequent utterance
  with that bundle produced non-silent, finite 3.88-second audio in 5.25 seconds.
  No private or third-party voice recording was used in the test.
- A repeated dialogue run with network access explicitly denied completed in
  7.90 seconds (1.30 seconds per second of audio), producing the same 6.08-second
  duration. Warm model loading took 1.37 seconds. Offline inference passed.
- The native app restored the edited script, automatically loaded cached Nano,
  generated all three dialogue blocks, played the preview, and exported through
  NSSavePanel. The exported `Chorus-ui.wav` is mono, 24 kHz, 16-bit PCM, 7.48 seconds.
- The 11 MB Apple Silicon app bundle passed `codesign --verify --deep --strict`
  with a local ad hoc signature and correctly sealed resource bundles.

The upstream runtime logged an ANE shape/broadcasting error on this M1 Pro and
successfully completed inference through its accelerator fallback. Core ML works
on this hardware, but a claim that all inference runs on the Neural Engine would
be inaccurate. Expression-tag output was generated; subjective vocal quality
still needs listening evaluation with real authorized reference clips.

Local artifacts in `dist/`: `nano-dialogue.wav`, `nano-dialogue.json`,
`nano-check.log`, `nano-time.log`, `cloned-voice.wav`, and `cloning-check.log`.
These are ignored build artifacts, not committed model weights or recordings.

Turbo integration uses the same validated upstream API and is selectable in the
app; these measurements cover Nano only. No benchmark claim is made for Turbo,
macOS 15, other hardware, long scripts, or the HLD's incremental RAM target.


## Chorus 0.2 voice presets and expressions

- Nine core suites pass, including all 19 expression tags, standalone `[clear throat]`,
  case normalization, legacy cloned-voice migration and preset settings roundtrip.
- Offline AVFoundation speed rendering converts a two-second 440 Hz signal to
  64,000 samples at 0.75× and 38,400 samples at 1.25× (24 kHz). Measured pitch stays
  at 440.2 / 440.0 Hz, with non-silent audio at the tail. The 1× path is unchanged.
- Nano with the bundled English podcast reference, `[sigh]`, 1.15× speed,
  temperature 0.85 and 0.30 s sentence pause produced 2.58 s of valid, non-silent
  24 kHz mono 16-bit WAV in 4.70 s, after a 1.71 s load.
- Turbo with the same reference, experimental Happy style, 1.15× speed and 0.30 s
  sentence pause produced 3.35 s of valid WAV in 25.90 s. This run took 57.25 s to
  load while another Turbo process was active; it is not a standalone benchmark.
- Native app: both editors expose nine reactions plus ten experimental delivery
  styles. Sigh insertion into a dialogue block was verified, then the original
  dialogue restored. Clone voice retains its recording/permission workflow.
  Create voice resolves the packaged podcast conditioning file, generates and
  plays a local preview, and saves the preset with its settings.
- The catalog contains the model default plus the upstream English podcast demo
  reference. Multilingual demo references are intentionally excluded, following
  the upstream catalog's measured short-reference failures on Turbo/Nano.
- Style-specific perceptual quality, similarity and watermark detection after
  speed processing have not been measured. Valid non-silent output is not proof
  of a particular emotion or delivery quality.

Native preset generation produced a 9.10 s WAV from the existing Text to Speech
script at 1.15× speed and a 0.30 s sentence pause. Changing the saved preset to
1.20× disabled export; restoring 1.15× made export available again. Export through
the macOS save panel was verified as 24 kHz mono 16-bit PCM.


## Chorus 0.3 five synthetic bases (2026-10-11)

- Five Kokoro references generated offline from the cached MLX snapshot
  a71e4d38b236d968966a2002c4c895dbd12b1c3c: Rue/af_bella, Kai/am_fenrir,
  Atlas/am_onyx, Zia/af_heart, Indie/af_nicole. Reference lengths were
  15.950, 15.425, 17.875, 17.975, and 28.175 seconds. Shared Core ML encoders
  produced five distinct conditioning files; no Kokoro runtime is shipped.
- 10/10 validation suites pass, including public-base identity/setting checks,
  preservation of the two previous base IDs, preset roundtrips, and explicit
  script delivery styles taking precedence over a preset style.
- All five bases generated finite, non-silent 24 kHz PCM WAV with their default
  settings on both Nano and Turbo. Combined generation took 20.52 seconds for
  Nano and 78.06 seconds for Turbo; these are smoke checks, not performance
  claims. Individual output lengths were 2.90–4.01 seconds. Artistic delivery
  descriptions and experimental style effectiveness remain subjective.
- Packaged app verified as version 0.3.0, build 3; five conditioning SHA-256
  hashes match REFERENCE_MANIFEST.json. Build script passes deep, strict
  ad-hoc code-signature verification. Total bundle size: 12,236,259 bytes.
- Native UI: library displays only Rue, Kai, Atlas, Zia and Indie as bundled
  bases with gender/accent/role and default speed/style. Create voice selector
  contains exactly those five. Zia starts at 1.10× / advertisement; changing to
  Atlas resets to 0.90× / narration, .65 variation, .45s sentence pause and .20s
  clause pause. Atlas preview generated and played from the installed app's
  packaged profile with Nano. App left open on Voice Library.
- Existing project, single text, voice assignments and both saved local voices
  match the pre-upgrade workspace backup exactly. Saved old podcast presets
  resolve their original asset through a hidden compatibility base. Current
  generated audio and project were exported before restarting the app.

Artifacts: dist/voice-build/references/references.json,
dist/voice-build/auditions-{nano,turbo}/*.wav and all.json,
dist/test-0.3.log, dist/build-app-0.3.log. Assets and provenance are in
Sources/Chorus/Resources/Voices/.


## Chorus 0.3.1 speaker import regression (2026-10-11)

- Root cause: tagged-script import created names with nil voice IDs; each nil
  selection rendered and generated with Rue. Existing nil assignments also
  overwrote any attempted base-name resolution during import.
- Parser now resolves names through a shared lowercase lookup, prioritizing
  existing explicit assignments, then saved local voices, then public bundled
  bases. Unknown names retain the default. Project restore/open applies the
  same resolution only to unassigned speakers. Explicit assignments stay intact.
- `[gasps]` / `[GASPS]` normalize to `[gasp]` before inference and are recognized
  as reactions when standalone. Unknown expression tags remain rejected.
- 12/12 suites pass, including the exact elevator script, all five base names in
  original/lower/upper casing, repeated Atlas/atlas/ATLAS tags, assignment
  precedence, restoration, and the gasp alias. Build/signature validation passes
  for version 0.3.1, build 4.
- Native UI verified from a fresh project with no existing assignments: importing
  examples/disco-elevator.txt produced 5 speakers / 10 blocks, with Atlas, Zia,
  Kai, Rue and Indie selected automatically. No voice picker edits were made.
  All 10 blocks generated with Nano in 36.3 seconds, including `[gasps]`.
  Exported audio verified as 32.11s, mono 24 kHz 16-bit PCM, non-silent.
- Current project/audio were saved before restarting. Existing local voices and
  single-voice text were preserved. App left on the imported script with the new
  audio ready for playback/export.

Artifacts: dist/test-0.3.1.log, dist/build-app-0.3.1.log,
dist/Elevator fixed 0.3.1.wav, dist/Elevator before importer fix.chorus,
dist/Elevator before importer fix.wav, and examples/disco-elevator.txt.

## Chorus 0.3.2 English text normalization (2026-10-11)

- Added an offline normalization step to shared VoiceSettings.preparedText;
  single speech, dialogue, voice preview and the inference checker use it.
  Original editor text and saved project data are not rewritten.
- 15/15 suites pass. New checks cover all five reported candidates, valid and
  invalid clock times, decimal precision/signs, grouped numbers, Indian currency
  grouping and paise, other currencies, titles, known and dotted initialisms,
  all-capital prose, repeated normalization, Unicode and preserved tags/URLs/
  emails/versions/dates/identifiers. Script parsing, voice assignments and
  saved-project roundtrips remain covered.
- A real Nano check logged the prepared text for the five examples and generated
  finite, non-silent mono 24 kHz 16-bit PCM: 9.76s audio in 11.63s generation.
  This verifies engine integration and output validity, not a perceptual
  pronunciation score. The Core ML runtime logged a tensor-shape diagnostic
  before returning valid audio; generation completed successfully.
- Signed bundle verified as 0.3.2/build 5. Native app reopened with Nano ready
  offline, the user's original single-voice text visible and Kai selected.
  Saved project, voices, single text/voice and engine selection match the backup.
  Existing preview audio exported before restart as
  dist/Speech before normalization 0.3.1.wav (61.71s).

Artifacts: dist/build-app-0.3.2.log, dist/normalization-nano-0.3.2.{wav,json,log},
dist/studio-before-normalization.json and examples/normalization-check.txt.
