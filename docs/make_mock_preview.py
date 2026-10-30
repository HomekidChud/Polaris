"""Draws docs/mock-executor.png: an ILLUSTRATION of the Polaris.MockExecutor() layout, not a screenshot of Roblox."""
import os
from playwright.sync_api import sync_playwright
HTML = """<html><body style="margin:0;width:1100px;height:760px;background:#0b0a14;font-family:'DejaVu Sans',Arial,sans-serif;color:#e8e4fa">
<div style="position:absolute;left:60px;top:40px;width:980px;height:650px;background:#0e0c18;border:2px solid #34305a;border-radius:14px;overflow:hidden">
 <div style="height:44px;background:#16132a;display:flex;align-items:center;padding:0 18px;font-weight:700;font-size:18px">Mock Executor<span style="margin-left:auto;color:#968ebe;font-weight:400">_ &nbsp; X</span></div>
 <div style="display:flex;gap:8px;padding:10px 14px"><b style="background:#9a6eff;padding:7px 18px;border-radius:7px;font-size:15px">Editor</b><span style="background:#221f3a;padding:7px 18px;border-radius:7px;font-size:15px">Script Hub</span><span style="background:#221f3a;padding:7px 18px;border-radius:7px;font-size:15px">Settings</span></div>
 <div style="padding:0 20px;font-size:16px"><span style="color:#ff6b78">&#9679;</span> Not attached (mock)</div>
 <div style="margin:10px 20px 0;display:flex;gap:10px;align-items:center;font-size:14px;color:#968ebe">Script tab <span style="background:#221f3a;padding:6px 14px;border-radius:6px;color:#e8e4fa">Script 1 &#9662;</span></div>
 <div style="margin:10px 20px;height:190px;background:#161326;border:1px solid #34305a;border-radius:8px;display:flex;font-family:'DejaVu Sans Mono',monospace;font-size:15px;line-height:24px;padding-top:8px">
  <div style="width:40px;text-align:right;color:#6f6894;padding-right:8px">1<br>2</div>
  <div style="color:#9fe3b5"><span style="color:#7a739e">-- Type a script here, then press Execute.</span><br>print("hello from the mock")</div></div>
 <div style="margin:0 20px;display:flex;gap:10px;font-size:15px;font-weight:700">
  <span style="flex:1;text-align:center;background:#9a6eff;padding:9px;border-radius:7px">Attach</span><span style="flex:1;text-align:center;background:#4cc38a;padding:9px;border-radius:7px">Execute</span><span style="flex:1;text-align:center;background:#221f3a;padding:9px;border-radius:7px">Clear</span><span style="flex:1;text-align:center;background:#221f3a;padding:9px;border-radius:7px">Clear output</span></div>
 <div style="margin:10px 20px 0;display:flex;gap:10px;font-size:15px;font-weight:700"><span style="flex:1;text-align:center;background:#221f3a;padding:8px;border-radius:7px">New tab</span><span style="flex:1;text-align:center;background:#221f3a;padding:8px;border-radius:7px">Close tab</span></div>
 <div style="margin:12px 20px 0;height:118px;background:#161326;border:1px solid #34305a;border-radius:8px;padding:10px 12px;font-family:'DejaVu Sans Mono',monospace;font-size:13px;line-height:20px;color:#968ebe">
  [12:01:08] Mock executor ready. Nothing here injects into anything.<br><span style="color:#ff6b78">[12:01:10] Press Attach first (the mock wants the green light).</span><br>[12:01:12] Attach pressed. This is a mock: nothing is being injected.<br><span style="color:#6be39a">[12:01:13] Status light is green. Execute is now allowed.</span></div>
</div>
<div style="position:absolute;left:60px;bottom:8px;font-size:15px;color:#8f89b4">Illustration of the layout - not a screenshot of a live Roblox session</div></body></html>"""
out = os.path.join(os.path.dirname(__file__), "mock-executor.png")
with sync_playwright() as p:
    b = p.chromium.launch(); pg = b.new_page(viewport={"width":1100,"height":760}); pg.set_content(HTML); pg.screenshot(path=out); b.close()
print(out)
