# Memory lifecycle — Chorus 0.3.3

Measured on 11 October 2026: Apple M1 Pro, 32 GiB RAM, macOS 27.0.1,
release builds using Swift 6.4 / macOS 27 SDK. Qwen is not integrated.

## Changes

- Restore a cached engine's local configuration at launch; load synthesis models
  on first generation or voice preview. Loading explicitly in the engine sheet
  still warms them immediately.
- Release synthesis models after 120 idle seconds and reload on the next
  generation. Playback/export do not require a resident engine. The timer is
  cancelled while loading, downloading, generating, previewing or cloning.
- Expose immediate unloading in Local engine and the Studio menu. It disables
  generation until the user loads an engine again, while keeping existing audio.
- Release synthesis models before cloning loads its separate reference encoders.
- Write 1× synthesis chunks directly to temporary 16-bit WAV files. Join one
  finished dialogue block at a time using 16 KiB copy buffers. Compute waveform
  peaks from disk, play using a file URL, and export with a staged file copy.
- Drain Foundation autorelease buffers per PCM write/read. Without this, a
  synchronous long file operation accumulated hundreds of MB of temporary data.
- Clear completed task references and preview audio when no longer needed. On
  normal app termination, stop playback and release the completed output file.
  Interrupted processes can leave temporary files for the OS to purge.

Non-default speed still buffers **one block** for AVAudioUnitTimePitch to preserve
continuity. This is not a fully bounded streaming time-stretch implementation.
Models, Core ML state, accelerator buffers and framework caches still consume
memory. Releasing a model does not guarantee immediate reclamation of every cache.

## Native Nano lifecycle

The existing 12-block project and its five voice assignments were used unchanged.
It generated 37.646375 seconds of non-silent mono 24 kHz 16-bit PCM in 53.1 seconds.
The native save panel exported `dist/Memory optimized 0.3.3.wav` successfully.

| State | Process physical footprint (`vmmap`) |
| --- | ---: |
| Launch, cached engine configured but not loaded | 69.0 MiB |
| Generated preview available, model resident | 501.9 MiB |
| Peak during that native session | 669.4 MiB |
| After automatic two-minute model release, preview retained | 122.4 MiB |

Voice preview successfully reloaded the idle engine automatically. Immediate
unload was also exercised; playback and WAV export remained enabled.
These are lifecycle snapshots, not a matched before/after comparison against the
user-reported 1.5 GB. Memory while synthesizing still depends on the selected model.

## Isolated audio benchmark

`chorus-check --audio-memory-benchmark legacy|file` assembles 120 distinct
30-second synthetic clips: one hour, 86,400,000 frames, 172,800,044 WAV bytes.
It exercises the previous clips → stitched Float array → WAV Data path versus
file-backed block assembly, waveform calculation and export. It does not load
speech models or include SwiftUI / AVAudioPlayer.

| Measurement (`/usr/bin/time -l`) | Legacy | File-backed |
| --- | ---: | ---: |
| Peak physical footprint | 1,235,633,736 bytes | 6,210,112 bytes |
| Maximum resident set size | 1,241,022,464 bytes | 12,861,440 bytes |

Peak physical footprint fell **99.5%** in this audio-only workload. Do not apply
that percentage to full app memory or model weights.

Artifacts: `dist/memory-audio-{legacy,file}-final.log`.

## Model loading fix and inference checks

The old app and old checker both failed with:
`MLModelConfiguration`'s `.functionName` property must be `nil` unless the model
type is ML Program.

Inspection via MLModelAsset confirmed the cached Nano T3 model actually contains
`prefill` and `decode`. Direct function probes succeeded for CPU-only, CPU+GPU
and CPU+Neural Engine. Automatic `.all` loaded prefill but failed on decode.
Recompiling under a separate cache identity reproduced the same failure.

The app and checker now explicitly use CPU+Neural Engine for **T3 only**. Synth
and watermark stages keep their previous compute policies. This avoids the
observed automatic-placement failure without deleting models or disabling watermarks.

- Real Nano dialogue: 151,680 frames / 6.32 seconds, non-silent, valid WAV.
- Real Nano with Kai at 1.15× speed: 3.547833 seconds, non-silent, valid WAV.
- Real Turbo: 3.96 seconds, non-silent, valid WAV. First load took 45.04 seconds.
- All 16 correctness suites pass, including byte-for-byte file-backed PCM
  equivalence, exact pause placement, export replacement, multi-buffer handling,
  rejection of invalid samples and cleanup of finished/unfinished files.
- Signed native app built and verified as 0.3.3 / build 6.

The short Nano checker baseline (old audio assembly, forced to the same T3
placement through CHATTERBOX_DECODE_CU=ane) peaked at 593,167,896 bytes physical
footprint; the optimized checker peaked at 659,293,696 bytes. There is **no measured
peak reduction for this short inference workload**. Runs were not a controlled
performance experiment; runtime caches and accelerator state dominate short
utterances. The demonstrated benefits are lower idle residency and bounded
retention of completed long-form audio.

Artifacts: `dist/memory-before-ane.{log,wav,json}`, `dist/memory-after-nano.*`,
`dist/memory-{speed,turbo}-smoke.*`, `dist/memory-function-probe.log`,
`dist/memory-app-{idle,loaded,idle-released}.log`, `dist/memory-tests-final.log`.

## Reproduce

```sh
bash scripts/test.sh
bash scripts/build-app.sh
swift build -c release --product chorus-check
BIN_DIR="$(swift build -c release --show-bin-path)"
/usr/bin/time -l "$BIN_DIR/chorus-check" --audio-memory-benchmark legacy
/usr/bin/time -l "$BIN_DIR/chorus-check" --audio-memory-benchmark file
```

SDK 27 introduces a State macro whose plugin is absent from this CLT installation.
The `ViewState` alias selects the existing SwiftUI State property wrapper and
keeps its established behavior. No plugin installation is needed.

## Intermittent function-load recovery (2026-10-13)

The same cached Nano T3 model later failed on prefill within a running app,
although separate CPU, GPU, and Neural Engine probes loaded both functions.
The app now retries the specific `functionName ... nil ... ML Program` load
error once with CPU-only T3 placement. Normal loads retain CPU + Neural Engine;
synth and watermark configuration remain the same. Cancellation, unrelated
errors, and a failed CPU attempt propagate without further retries. No model
files are deleted or downloaded as part of recovery. The checker shares the
recovery helper and accepts `--t3-cpu-only` to verify real CPU inference.

Verification: all 24 regression suites pass, including successful primary load,
one targeted retry, wrapped errors, CPU failure propagation, and cancellation.
Real Nano CPU-only inference with Rue produced 3.40 seconds of non-silent audio
in 3.21 seconds after a 3.64-second model load. The signed app was rebuilt.

The reported Mature / Chest-Heavy / Harsh / Angry / Superhero combination also
passed real CPU-only synthesis using its cached `am_onyx` reference, followed
by the exact compiled Lab effects and speech-level correction: 8.25925 seconds,
finite samples, peak 0.84897. The intermittent live failure was not forced;
error injection tests cover dispatch to the verified CPU load path.
