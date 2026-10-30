# Polaris 3.0

Script libraries, deep-research panels and Roblox hubs, from one line.

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/HomekidChud/Polaris/main/Polaris.luau"))().Start()
```

That opens a screen of big coloured tiles and one wide button, "Create your own script hub". Tap a picture and the matching UI appears. The Script Hub tile is a working hub with ready-made scripts and a + Add button for your own. The wide button opens a block editor where blocks and Script blocks (your own code) build a hub you can export and share. Nothing to install, nothing to configure.

Watch the 52 second tour (made for version 2, so it shows five launcher tiles): [docs/video/polaris-tour.mp4](docs/video/polaris-tour.mp4). Read the full walkthrough: [GUIDE.md](GUIDE.md).

## What you get

| Want | One line |
|---|---|
| Tile launcher for everyone | `Polaris.Start()` |
| A hub built from blocks plus your own scripts | `Polaris.MakeHub()` |
| An executor-style window (mock-up, nothing is injected) | `Polaris.MockExecutor()` |
| A script library UI (search, tags, favourites) | `Polaris.Templates.ScriptLibrary({ Manifest = "https://.../scripts.json" })` |
| A deep-research UI (plan, sources, cited report) | `Polaris.Templates.DeepResearch({ Provider = "Perplexity" })` |
| A Roblox hub (live stats, FOV, time of day, output log) | `Polaris.Templates.RobloxHub({ Name = "My Hub" })` |
| All of the above in one window | `Polaris.Templates.Everything()` |
| A UI from plain words | `Polaris.Make("a research tool")` |
| A UI from a table | `Polaris.Hub({ Name = "Hi", Buttons = { Wave = function() print("wave") end } })` |
| Drag and drop designer that exports code | `Polaris.Builder:Open()` |
| Open a Builder project without code | `Polaris.FromProject(jsonText)` |
| An app from a safe JSON spec | `Polaris.Spec.Build({ Name = "App", Tabs = { ... } })` |
| An app from a sentence (demo offline, Perplexity with your key) | `Polaris.Imagine("a clicker game")` |
| The Make Anything window | `Polaris.Imaginer()` |
| Saved state that updates labels and inputs | `Polaris.State(0, { Persist = true })`, `label:Bind(state)` |
| Your own element or Builder block | `Polaris.DefineElement(...)`, `Polaris.DefineBlock(...)` |

New elements on every tab: Label, Progress, Console, ButtonRow, Stats, ScriptLibrary, Research, CodeEditor, Group, Columns, Pages, Spacer, Image, Custom, Table, Chart, Form. Add any of them with `tab:Add("Kind", { ... })`.

## Honest limits

| Limit | What it means |
|---|---|
| Hub scripts | Eight built-in scripts (Fullbright, Wide view, Day or night, FPS counter, Server info, Copy game link, Hide chat, Rejoin). Camera, lighting and screen only. Not tried in a real client. |
| Not tried in real Roblox | All 100+ checks run under Lune with a simulated Roblox. Rendering, dragging, touch and gamepad have not been seen on a real device. Test in Studio first. |
| Web requests | Roblox clients block `HttpService`. Remote scripts, manifests and live research need an executor `request()` or a server with HttpService enabled. |
| `loadstring` | Disabled in normal Studio LocalScripts. Remote scripts only run where `loadstring` exists. |
| Clipboard and saving | Need executor functions (`setclipboard`, `writefile`). Otherwise the UI says so and keeps an in-memory copy. |
| Live research | The Perplexity provider is written to the [official docs](https://docs.perplexity.ai/api-reference/agent-post.md) but has not been run against the live API. It needs your own key, typed into the masked box at run time and never stored. |
| Demo provider | Returns placeholder text. It exists so the UI works with no key. |
| Imagine | The Demo path is keyword matching. The Perplexity path is untested live and can only return a spec of safe actions, never code. |
| v3 layout, tables, charts | Tested under Lune with a simulated Roblox only. |
| Font | Gotham is the new default. It has not been checked visually. |
| Obfuscation | The root `Polaris.luau` is obfuscated to deter casual copying. It is not protection. Readable source is `src/`. |
| Scope | Safe dev tools only (FOV, time of day, output log, stats). No exploit features are included. |

## Repository

```
Polaris.luau          the loadstring target (obfuscated build of src/Polaris.luau)
Start.luau            the same one-liner as a file
Builder.luau          opens the visual Builder on its own
GUIDE.md              how to use everything
docs/API.md           classic API reference
docs/video/           the tour video and the scripts that made it
src/core.luau         window, elements, themes, Builder
src/modules/          Util, Kit, elements, library, research, easy layer, launcher, builder kinds
src/Polaris.luau      generated readable bundle (build/bundle.py)
tests/                Lune test suites (bash tests/run_all.sh)
build/                bundle, obfuscate and verify (bash build/build.sh)
example.luau          Studio demo of every classic element
MyHub.luau            a complete hub example
```

## Developing

```
python3 build/bundle.py          # src/core.luau + src/modules -> src/Polaris.luau
bash tests/run_all.sh            # every test against the readable bundle
bash build/build.sh              # bundle, test, obfuscate, test the published file
```

MIT licensed.
