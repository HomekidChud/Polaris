"""Builds the Polaris tour with VideoCraft (https://homekidchud.github.io/artcraft-live/videocraft/).
Generates a VideoCraft project from docs/video/slides/*.png + captions, opens it in a headless browser,
records it with VideoCraft's own exporter, and saves the WebM.  Then: ffmpeg -> mp4."""
import base64, json, os, sys, time
from playwright.sync_api import sync_playwright

HERE = os.path.dirname(os.path.abspath(__file__))
SL = os.path.join(HERE, "slides")
PLAN = [
    ("01_title", 4.0, "Polaris 2.0: one line, one tap"),
    ("02_oneline", 6.0, "Paste this one line. It loads everything."),
    ("03_tap", 7.0, "Tap a picture, or tap the pink button to make your own hub."),
    ("04_library", 6.0, "Script Hub: ready-made scripts, plus + Add for your own."),
    ("05_research", 6.0, "Deep Research: plan, sources, cited report."),
    ("06_hub", 6.0, "Roblox Hub: live stats, sliders, output log."),
    ("07_builder", 7.0, "Blocks build the hub. Script blocks hold your own code."),
    ("08_limits", 7.0, "Honest limits: read them before you rely on it."),
    ("09_outro", 4.0, "GUIDE.md has every step."),
]
media, clips, caps = [], [], []
t = 0.0
for n, (name, dur, text) in enumerate(PLAN):
    data = "data:image/png;base64," + base64.b64encode(open(os.path.join(SL, name + ".png"), "rb").read()).decode()
    mid = f"m_{n}"
    media.append({"id": mid, "type": "image", "name": name + ".png", "duration": 0, "data": data})
    clips.append({"id": f"c_{n}", "track": "v", "kind": "media", "mediaId": mid, "start": t, "dur": dur, "in": 0, "volume": 1, "fit": "contain"})
    caps.append({"id": f"cap_{n}", "start": t + 0.3, "dur": dur - 0.6, "text": text, "pos": "bottom", "size": 1.5, "color": "#ffffff", "bg": True})
    t += dur
proj = {"app": "videocraft", "version": 1, "name": "Polaris 2.0 tour", "aspect": "16:9", "fps": 30,
        "clips": clips, "scenes": [], "captions": caps, "media": media}
pj = os.path.join(HERE, "polaris-tour.vfproject.json")
json.dump(proj, open(pj, "w"))
print("project written, length", t, "s")

out = os.path.join(HERE, "polaris-tour.webm")
with sync_playwright() as p:
    b = p.chromium.launch(args=["--autoplay-policy=no-user-gesture-required", "--use-gl=swiftshader", "--enable-unsafe-swiftshader"])
    ctx = b.new_context(viewport={"width": 1400, "height": 900}, accept_downloads=True)
    pg = ctx.new_page()
    pg.goto("https://homekidchud.github.io/artcraft-live/videocraft/", wait_until="networkidle", timeout=90000)
    pg.set_input_files("#file-open", pj)
    pg.wait_for_timeout(3000)
    pg.screenshot(path=os.path.join(HERE, "_loaded.png"))
    with pg.expect_download(timeout=int((t + 120) * 1000)) as dl:
        pg.click("#btn-export-top")
    dl.value.save_as(out)
    print("saved", out, os.path.getsize(out))
    b.close()
