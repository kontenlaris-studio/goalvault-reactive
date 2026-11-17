#!/usr/bin/env python3
"""Assemble the GoalVault demo video from frames + Piper narration.
Scenes follow video/SCRIPT.md; captions are burned in from display texts."""
import json, subprocess, os, re, sys

V = os.path.dirname(os.path.abspath(__file__))
F = os.path.join(V, "frames")
N = os.path.join(V, "narration")
WORK = os.path.join(V, "_work")
os.makedirs(WORK, exist_ok=True)
FPS = 30
GAP = 0.35
TAIL = 0.8

def run(cmd, **kw):
    r = subprocess.run(cmd, capture_output=True, text=True, **kw)
    if r.returncode != 0:
        print("FAILED:", " ".join(cmd[:6]), "...\n", r.stderr[-1500:])
        sys.exit(1)
    return r

def dur(path):
    r = run(["ffprobe", "-v", "error", "-show_entries", "format=duration",
             "-of", "csv=p=0", path])
    return float(r.stdout.strip())

# ---------- crop the template-picker area out of the builder section shot
from PIL import Image
t = Image.open(f"{F}/dash-templates.png")
t.crop((0, 0, t.width, 660)).save(f"{F}/dash-templates-top.png")

# ---------- compose 1920x1080 stills (blur-pad for dashboard shots)
def compose(src, name):
    out = f"{WORK}/{name}.png"
    if src.endswith(("-title.png", "-flow.png", "-proof.png", "-safety.png", "-closing.png")):
        run(["ffmpeg", "-y", "-v", "error", "-i", src, "-vf", "scale=1920:1080", out])
    else:
        fc = ("[0]scale=1920:1080:force_original_aspect_ratio=increase,crop=1920:1080,gblur=sigma=42,eq=brightness=-0.12[bg];"
              "[0]scale=1920:1080:force_original_aspect_ratio=decrease[fg];"
              "[bg][fg]overlay=(W-w)/2:(H-h)/2")
        run(["ffmpeg", "-y", "-v", "error", "-i", src, "-filter_complex", fc, out])
    return out

segs = json.load(open(f"{N}/segments.json"))
audio_durs = {s["scene"]: dur(f"{N}/scene{s['scene']}.wav") for s in segs}

# scene -> list of (frame, fraction of scene duration)
scene_visuals = {
    1: [("slide-title.png", 1.0)],
    2: [("dash-hero.png", 0.55), ("dash-templates-top.png", 0.45)],
    3: [("dash-form-top.png", 0.5), ("dash-form-bottom.png", 0.5)],
    4: [("slide-flow.png", 1.0)],
    5: [("dash-automations.png", 0.62), ("dash-status.png", 0.38)],
    6: [("slide-proof.png", 1.0)],
    7: [("slide-safety.png", 1.0)],
    8: [("slide-closing.png", 1.0)],
}

scene_starts, t_cursor, clips = {}, 0.0, []
for s in segs:
    sc = s["scene"]
    scene_starts[sc] = t_cursor
    scene_len = audio_durs[sc] + (TAIL if sc == 8 else GAP)
    for img, frac in scene_visuals[sc]:
        d = scene_len * frac
        frames = max(1, round(d * FPS))
        still = compose(f"{F}/{img}", f"s{sc}_{img}")
        clip = f"{WORK}/clip_{sc}_{img}.mp4"
        vf = (f"scale=2560:1440,zoompan=z='1+0.045*on/{frames}':"
              f"x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d={frames}:s=1920x1080:fps={FPS}")
        run(["ffmpeg", "-y", "-v", "error", "-loop", "1", "-i", still,
             "-vf", vf, "-t", f"{frames / FPS:.3f}", "-c:v", "libx264",
             "-preset", "veryfast", "-crf", "17", "-pix_fmt", "yuv420p", clip])
        clips.append(clip)
    t_cursor += scene_len
total = t_cursor
print(f"total duration: {total:.1f}s")

with open(f"{WORK}/clips.txt", "w") as fh:
    for c in clips:
        fh.write(f"file '{c}'\n")
run(["ffmpeg", "-y", "-v", "error", "-f", "concat", "-safe", "0", "-i",
     f"{WORK}/clips.txt", "-c", "copy", f"{WORK}/video_nosub.mp4"])

# ---------- narration track (scene wavs + silence gaps)
run(["ffmpeg", "-y", "-v", "error", "-f", "lavfi", "-i",
     "anullsrc=r=22050:cl=mono", "-t", str(GAP), f"{WORK}/gap.wav"])
with open(f"{WORK}/audio.txt", "w") as fh:
    for s in segs:
        fh.write(f"file '{N}/scene{s['scene']}.wav'\n")
        if s["scene"] != 8:
            fh.write(f"file '{WORK}/gap.wav'\n")
run(["ffmpeg", "-y", "-v", "error", "-f", "concat", "-safe", "0", "-i",
     f"{WORK}/audio.txt", "-c", "copy", f"{WORK}/narration_full.wav"])

# ---------- captions (display text, sentence chunks timed by word share)
DISPLAY = {
    1: 'Every "automatic" payout in crypto has a catch: somebody still has to press the button. A savings goal fills up — and waits. An escrow is fully funded — and the freelancer still chases the release. GoalVault removes the button entirely.',
    2: "GoalVault is a no-code builder for Reactive automations, built for the Set It and Forget It track. You pick a template — a savings goal, or pay-when-funded escrow — and the vault you deploy finishes itself. No code, no server, no keeper.",
    3: "Creating one takes under a minute. Who should receive the money? What is the target? The dashboard turns plain answers into exact deployment parameters, and your wallet deploys the vault on Sepolia. Then you just fund it — whenever, in as many deposits as you like.",
    4: "Behind the scenes, every deposit emits an event carrying the running total and the target. A reactive contract on Lasna listens for those events and checks the condition on-chain, in about a second. Below target, it does nothing. The moment the total reaches the target, it requests a callback — once, and only once.",
    5: "The callback lands back on Sepolia and releases the funds to the beneficiary automatically. Here is a real goal from the live deployment: fully funded, 100%, completed and paid out — with nobody pressing anything. The Reactive panel shows both automations live and subscribed.",
    6: "And this is the proof, live on testnet. A deposit of 0.02 ETH crossed the 0.03 target on Sepolia. The Lasna reactive transaction fired GoalTargetHit and requested the callback. One Sepolia block later, the callback transaction paid out the full amount. Both templates ran this exact loop, end to end.",
    7: "It is also safe to leave running. A below-target deposit was evaluated and correctly ignored — zero logs, no payout. Contract debt is zero on both sides. Creators can cancel and refund every contributor, the owner can pause or retry a callback, and 58 tests pass.",
    8: "Set it, and forget it — because Reactive remembers for you. GoalVault: templates anyone can use, and automations that finish themselves. Thank you.",
}

def srt_ts(x):
    h = int(x // 3600); m = int((x % 3600) // 60); ss = x % 60
    return f"{h:02d}:{m:02d}:{ss:06.3f}".replace(".", ",")

def chunks(text):
    parts = re.split(r"(?<=[.!?])\s+", text)
    out = []
    for p in parts:
        words = p.split()
        while len(words) > 14:
            out.append(" ".join(words[:14])); words = words[14:]
        if words:
            out.append(" ".join(words))
    return out

srt, idx = [], 1
for s in segs:
    sc = s["scene"]
    cs = chunks(DISPLAY[sc])
    total_words = sum(len(c.split()) for c in cs)
    cur = scene_starts[sc]
    for c in cs:
        d = audio_durs[sc] * len(c.split()) / total_words
        srt.append(f"{idx}\n{srt_ts(cur)} --> {srt_ts(cur + d)}\n{c}\n")
        idx += 1
        cur += d
open(f"{WORK}/captions.srt", "w").write("\n".join(srt))

# ---------- final mux: burn captions + narration
style = ("FontName=DejaVu Sans,FontSize=20,PrimaryColour=&HFFFFFF,"
         "OutlineColour=&H90000000,BorderStyle=1,Outline=2,Shadow=0,"
         "Alignment=2,MarginV=34")
run(["ffmpeg", "-y", "-v", "error", "-i", f"{WORK}/video_nosub.mp4",
     "-i", f"{WORK}/narration_full.wav",
     "-vf", f"subtitles={WORK}/captions.srt:force_style='{style}'",
     "-c:v", "libx264", "-preset", "medium", "-crf", "20", "-pix_fmt", "yuv420p",
     "-c:a", "aac", "-b:a", "128k", "-ar", "44100", "-t", f"{total:.2f}",
     "-movflags", "+faststart", f"{V}/demo.mp4"])
print("demo.mp4 written")
