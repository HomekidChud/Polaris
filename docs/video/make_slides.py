"""Renders the tutorial slides (1920x1080 PNG) used by the Polaris tour video.
Run: python3 docs/video/make_slides.py   (needs playwright + chromium)
The UI drawings are illustrations of the layout, NOT screenshots of a real Roblox session."""
import os
from playwright.sync_api import sync_playwright

OUT = os.path.join(os.path.dirname(__file__), "slides")
os.makedirs(OUT, exist_ok=True)

CSS = """
*{box-sizing:border-box;margin:0;padding:0}
body{width:1920px;height:1080px;background:radial-gradient(1400px 800px at 20% 0%,#2a2f6b,#12142b 60%);color:#fff;font-family:'DejaVu Sans','Liberation Sans',Arial,sans-serif;overflow:hidden;position:relative}
.wrap{position:absolute;left:90px;right:90px;top:60px;bottom:200px}
h1{font-size:92px;font-weight:800;letter-spacing:-1px;line-height:1.05}
h2{font-size:64px;font-weight:800;margin-bottom:26px}
p.sub{font-size:38px;color:#c9cdf5;margin-top:20px;line-height:1.35}
.tag{position:absolute;right:50px;top:30px;font-size:22px;color:#8f95d8}
.note{position:absolute;left:90px;bottom:28px;font-size:22px;color:#8f95d8}
.rb span:nth-child(1){color:#ff5a5f}.rb span:nth-child(2){color:#ffa03c}.rb span:nth-child(3){color:#facd3c}.rb span:nth-child(4){color:#5ac878}.rb span:nth-child(5){color:#46a0ff}.rb span:nth-child(6){color:#a06ef0}.rb span:nth-child(7){color:#ff5a5f}
.code{background:#0b0d1f;border:3px solid #46a0ff;border-radius:22px;padding:34px 40px;font-family:'DejaVu Sans Mono',monospace;font-size:34px;line-height:1.5;color:#9fe3b5;word-break:break-all}
.card{background:#1b1e44;border:3px solid #3a3f86;border-radius:26px;padding:30px}
.tiles{display:grid;grid-template-columns:repeat(3,1fr);gap:26px}
.tile{height:230px;border-radius:30px;display:flex;flex-direction:column;align-items:center;justify-content:center;font-size:42px;font-weight:800;gap:16px}
.ic{width:100px;height:100px;position:relative}.ic i{position:absolute;background:#fff;border-radius:8px;display:block}
.row{display:flex;gap:30px}.col{flex:1}
.pill{display:inline-block;padding:10px 22px;border-radius:999px;background:#2b3070;font-size:28px;margin:6px 10px 6px 0}
.pill.on{background:#46a0ff}
.card h3{font-size:34px;margin-bottom:14px}
.line{font-size:30px;margin:12px 0;color:#d6d9ff}
.bar{height:22px;border-radius:11px;background:#2b3070;margin:10px 0 22px;position:relative}.bar b{position:absolute;left:0;top:0;bottom:0;border-radius:11px;background:#46a0ff}
ul{list-style:none}li{font-size:38px;margin:18px 0;line-height:1.3}
.ok{color:#5ac878}.no{color:#ff7a80}
"""

def page(body, tag="", note=""):
    return f"<html><head><meta charset='utf-8'><style>{CSS}</style></head><body><div class='tag'>{tag}</div><div class='wrap'>{body}</div><div class='note'>{note}</div></body></html>"

ILL = "Illustration of the layout - not a screenshot of a live Roblox session"
def tile(color, name, icon):
    return f"<div class='tile' style='background:{color}'><div class='ic'>{icon}</div>{name}</div>"
def i(x,y,w,h,bg="#fff",r=8): return f"<i style='left:{x}%;top:{y}%;width:{w}%;height:{h}%;background:{bg};border-radius:{r}px'></i>"
LIST = i(10,12,80,18)+i(10,41,80,18)+i(10,70,50,18)
SEARCH = "<i style='left:8%;top:8%;width:58%;height:58%;background:transparent;border:7px solid #fff;border-radius:50%'></i>"+"<i style='left:58%;top:74%;width:40%;height:14%;transform:rotate(45deg)'></i>"
GRID = i(8,8,38,38)+i(54,8,38,38)+i(8,54,38,38)+i(54,54,38,38)
RAIN = "".join(i(4+k*19,50-(k+1)*7,15,30+(k+1)*7,c) for k,c in enumerate(["#ff5a5f","#ffa03c","#facd3c","#5ac878","#46a0ff"]))
PLUS = i(40,8,20,84)+i(8,40,84,20)
DOTS = i(5,35,27,27,"#fff",99)+i(36,35,27,27,"#fff",99)+i(68,35,27,27,"#fff",99)

slides = {}
slides["01_title"] = page("""
<div style='height:100%;display:flex;flex-direction:column;justify-content:center'>
<h1 class='rb'><span>P</span><span>o</span><span>l</span><span>a</span><span>r</span><span>i</span><span>s</span> 2.0</h1>
<p class='sub' style='font-size:56px;color:#fff;margin-top:30px'>One line. Tap a picture. Done.</p>
<p class='sub'>Script libraries, deep-research panels and Roblox hubs for any script.</p></div>""")
slides["02_oneline"] = page("""
<h2>Step 1: paste one line</h2>
<div class='code'>loadstring(game:HttpGet("https://raw.githubusercontent.com/HomekidChud/Polaris/main/Polaris.luau"))().Start()</div>
<p class='sub'>That single line loads everything. No installs, no setup, no files.</p>""", "Polaris 2.0")
slides["03_tap"] = page(f"""
<h2>Step 2: tap a picture</h2>
<div class='tiles'>{tile('#4285f4','Script Hub',LIST)}
{tile('#965feb','Research',SEARCH)}{tile('#34a864','Game Hub',GRID)}
{tile('#f08c28','Everything',RAIN)}{tile('#ebbe28','Play',DOTS)}</div>
<div style='margin-top:12px;height:104px;border-radius:30px;background:#e6508c;display:flex;align-items:center;gap:30px;padding:0 40px'>
<div class='ic' style='width:70px;height:70px'>{PLUS}</div><div><div style='font-size:46px;font-weight:800'>Create your own script hub</div><div style='font-size:26px;color:#ffe1f0'>Snap blocks together and add your own scripts</div></div></div>""", "Polaris launcher", ILL)
slides["04_library"] = page(f"""
<h2>Script Hub</h2>
<div class='row'><div class='col card'>
<div class='line' style='background:#0b0d1f;border-radius:14px;padding:14px 20px'>Search scripts...</div>
<div style='margin:16px 0'><span class='pill on'>All</span><span class='pill'>Favourites</span><span class='pill'>This game</span><span class='pill'>look</span><span class='pill'>tools</span><span class='pill' style='background:#e6508c'>+ Add</span></div>
<div class='card' style='margin:14px 0'><h3>Fullbright</h3><div class="line">Brightens a dark game.</div></div>
<div class='card' style='margin:14px 0'><h3>FPS counter</h3><div class="line">Frames per second in the corner.</div></div></div>
<div class='col'><p class='sub' style='margin-top:0'>Ready-made scripts. Search, filter, star favourites.</p><p class='sub'>Tap + Add to put in your own link or code.</p><p class='sub'>Remote scripts ask before they run.</p></div></div>""", "Script library UI", ILL)
slides["05_research"] = page(f"""
<h2>Deep Research</h2>
<div class='row'><div class='col card'>
<div class='line' style='background:#0b0d1f;border-radius:14px;padding:14px 20px'>How do hubs stay fast?</div>
<div style='margin:16px 0'><span class='pill'>Quick</span><span class='pill on'>Standard</span><span class='pill'>Deep</span><span class='pill'>Max</span></div>
<div class='line ok'>1. Plan the question</div><div class='line ok'>2. Search sources</div><div class='line'>3. Write the report</div>
<div class='bar'><b style='width:66%'></b></div></div>
<div class='col card'><h3>Report</h3><div class='line'>A cited answer appears here, with numbered sources you can copy or save.</div><div class='line' style='color:#46a0ff'>[1] example.com/source</div></div></div>""", "Deep-research UI", ILL)
slides["06_hub"] = page(f"""
<h2>Roblox Hub</h2>
<div class='row'><div class='col card'><h3>Live stats</h3>
<span class='pill'>FPS 60</span><span class='pill'>Ping 42</span><span class='pill'>Players 12</span>
<h3 style='margin-top:26px'>Camera</h3><div class='line'>Field of view</div><div class='bar'><b style='width:45%'></b></div><div class='line'>Time of day</div><div class='bar'><b style='width:60%'></b></div></div>
<div class='col card' style='font-family:DejaVu Sans Mono,monospace'><h3>Output</h3><div class='line'>[info] Hub loaded</div><div class='line'>[info] FOV set to 70</div></div></div>""", "Roblox script UI", ILL)
slides["07_builder"] = page("""
<h2>Make your own: blocks plus scripts</h2>
<div class='row'><div class='col card'><h3>Blocks build the hub</h3>
<span class='pill' style='background:#4682c8'>Label</span><span class='pill' style='background:#4cb06e'>Toggle</span><span class='pill' style='background:#9669e1'>Slider</span><span class='pill' style='background:#4285f4'>Script Library</span><span class='pill' style='background:#965feb'>Research</span><span class='pill' style='background:#4682c8'>Stats</span>
<h3 style='margin-top:26px'>Script blocks do the work</h3><span class='pill' style='background:#eb643c'>Script: Say hello</span><span class='pill' style='background:#eb643c'>Script: Wide view</span></div>
<div class='col'><div class='code' style='font-size:27px'>-- inside a Script block<br>workspace.CurrentCamera<br>&nbsp;&nbsp;.FieldOfView = 100</div>
<p class='sub' style='font-size:32px'>Press Export. You get a ready hub script to share.</p></div></div>""", "Hub maker", ILL)
slides["08_limits"] = page(f"""
<h2>Honest limits</h2>
<ul><li><span class='ok'>Works:</span> tested in a simulated Roblox environment, over 100 automated checks</li>
<li><span class='no'>Not proven:</span> real Roblox rendering, touch and gamepad input</li>
<li><span class='no'>Needs an executor:</span> web requests, clipboard, saving files</li>
<li><span class='no'>Needs your key:</span> live research uses your own Perplexity API key</li></ul>""", "Capabilities and limits")
slides["09_outro"] = page("""
<div style='height:100%;display:flex;flex-direction:column;justify-content:center'>
<h1>Read <span style='color:#46a0ff'>GUIDE.md</span></h1>
<p class='sub' style='font-size:46px;color:#fff'>github.com/HomekidChud/Polaris</p>
<p class='sub'>Every feature, every limit, every step.</p></div>""")

with sync_playwright() as p:
    b = p.chromium.launch()
    pg = b.new_page(viewport={"width":1920,"height":1080})
    for name, html in slides.items():
        pg.set_content(html)
        pg.screenshot(path=os.path.join(OUT, name + ".png"))
        print("wrote", name)
    b.close()
