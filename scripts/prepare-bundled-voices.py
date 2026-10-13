"""Create Chorus's synthetic voice references using a local MLX Kokoro snapshot.

Run with an environment containing mlx-audio and misaki[en]. No Kokoro runtime
is shipped in Chorus; the references are converted by chorus-check's Core ML
VoiceCloner. Pass a pinned local snapshot to keep the build reproducible.
"""
import argparse
import hashlib
import json
from pathlib import Path
import wave

import numpy as np
from mlx_audio.tts.utils import load_model


VOICES = [
    ("rue", "af_bella", 0.98,
     "I thought I knew how this story would end. Then you walked through that door, "
     "and everything changed. Don't tell me it was just a coincidence. Look at me. "
     "We still have a chance to make this right, but we have to choose it together. "
     "So, what do you say? Are you coming with me?"),
    ("kai", "am_fenrir", 0.98,
     "You want the truth? I didn't come all this way to give up at the last door. "
     "We made a promise, and I intend to keep it. Maybe we're scared. Maybe the "
     "odds are terrible. But you and I have faced worse than this before. "
     "Take a breath, look ahead, and let's finish what we started."),
    ("atlas", "am_onyx", 0.90,
     "Some journeys begin with a great adventure. Others begin with a quiet "
     "decision to try again. As the evening light moved across the empty street, "
     "he paused and listened. There was no hurry now. Every road had brought "
     "him here, and for the first time in years, he understood what mattered. "
     "The next chapter was still his to write."),
    ("zia", "af_heart", 1.06,
     "Ready for something fresh? Meet your new favorite way to start the day! "
     "Bright ideas, bold little moments, and a whole lot of possibility. "
     "Whether you're heading out with friends or chasing your next big thing, "
     "bring a little extra energy along. Go on, make it yours. "
     "Your next great day starts right here, right now!"),
    ("indie", "af_nicole", 0.96,
     "Hey, take your time. The coffee's warm, the record's spinning, and "
     "there's nowhere we need to rush off to. I found this little track last "
     "night, and the bass line has been living in my head ever since. "
     "Put your phone down for a minute. Settle in, catch the groove, "
     "and let the afternoon do its thing."),
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    if not args.model_dir.is_dir():
        parser.error("--model-dir must be a local Kokoro MLX snapshot")
    args.output_dir.mkdir(parents=True, exist_ok=True)
    model = load_model(args.model_dir, model_type="kokoro")
    records = []
    for name, voice, speed, text in VOICES:
        samples = np.concatenate([
            np.asarray(chunk.audio, dtype=np.float32).reshape(-1)
            for chunk in model.generate(text=text,
                voice=str(args.model_dir / "voices" / f"{voice}.safetensors"), lang_code="a", speed=speed)
        ])
        duration = len(samples) / 24000
        if duration < 15 or not np.isfinite(samples).all() or np.max(np.abs(samples)) < .01:
            raise RuntimeError(f"{name}: reference is short, invalid, or silent ({duration:.2f}s)")
        pcm = (np.clip(samples, -1, 1) * 32767).astype("<i2")
        path = args.output_dir / f"{name}.wav"
        with wave.open(str(path), "wb") as audio:
            audio.setnchannels(1)
            audio.setsampwidth(2)
            audio.setframerate(24000)
            audio.writeframes(pcm.tobytes())
        records.append(dict(name=name, seedVoice=voice, speed=speed, text=text,
                            seconds=duration, sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
        print(f"{name}: {voice}, {duration:.2f}s", flush=True)
    (args.output_dir / "references.json").write_text(json.dumps(
        dict(model="mlx-community/Kokoro-82M-bf16", revision=args.model_dir.name, voices=records),
        indent=2) + "\n")


if __name__ == "__main__":
    main()
