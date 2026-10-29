# Polaris

A single-file UI library for Roblox Luau — plus a visual **Polaris Builder**: run it on its own and get an animated splash, then a block editor that generates your entire hub script for you.

```
Polaris.luau   -- obfuscated distribution (the loadstring target)
Builder.luau   -- builder launcher (splash + editor)
src/           -- readable source for both
example.luau   -- Studio LocalScript demo of every element
MyHub.luau     -- a complete example hub built on Polaris
tests/         -- logic test suite (runs under Lune)
build/         -- obfuscation pipeline (repeatable build script)
```

## Status: prototype, logic-tested only

- The code compiles under the Luau compiler, and a 66-case logic suite passes under [Lune](https://lune.dev) with a mocked Roblox environment — against **both** the readable source and the exact obfuscated artifact that is published here (window/element behavior, the builder data model, generated-code execution, JSON round-trips, config persistence, cleanup, theming, search).
- **Visual rendering, dragging, touch handling, splash animation, and layout have NOT been verified in Roblox.** Test in Studio before shipping (checklist below).

## Quick start

**The Builder — run it on its own** (no coding needed):

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/HomekidChud/Polaris/main/Builder.luau"))()
```

You get an animated splash, then a fullscreen block editor, Scratch style: drag blocks from the left palette onto the canvas, tap one to edit it in the right-hand properties panel, preview the live result, and export a ready-to-paste script. The library file itself never opens anything on its own — the Builder only starts from `Builder.luau` (or an explicit `Polaris.Builder:Open()` call).

**The library — use it in your own script:**

```lua
local Polaris = loadstring(game:HttpGet("https://raw.githubusercontent.com/HomekidChud/Polaris/main/Polaris.luau"))()
```

**Studio:** put `src/Polaris.luau` in ReplicatedStorage as a ModuleScript named `Polaris`, then in a LocalScript:
```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Polaris = require(ReplicatedStorage:WaitForChild("Polaris"))
```

```lua
local Window = Polaris:CreateWindow({
	Name = "My Hub",
	Theme = "Midnight",                     -- Default | Midnight | Light
	ToggleKey = Enum.KeyCode.RightControl,  -- show/hide the whole UI
	SaveConfig = true,                     -- see Configs
	ConfigFolder = "MyHub",
})

local Tab = Window:CreateTab({ Name = "Main" })

Tab:CreateToggle({
	Name = "Fly",
	Default = false,
	Flag = "fly",
	Callback = function(value)
		print("fly:", value)
	end,
})
```

## Polaris Builder

Open it with the `Builder.luau` loadstring above, or `Polaris.Builder:Open()` from your own code.

- **Build tab** — set the hub name, theme, config folder; add blocks (Tab, Section, Button, Toggle, Slider, Dropdown, Keybind, Textbox, Color, Paragraph, Divider); the Structure list shows your whole hub as a tree and clicking a block selects it
- **Properties tab** — edit the selected block: names, defaults, slider ranges, dropdown options, keybind keys, flags, and Move up/down, Duplicate, Delete
- **Preview tab** — renders your project as a real Polaris window (config saving disabled so it never touches your saved configs)
- **Export tab** — generates the full Luau script for your hub (loader line, window, tabs, every block with callback stubs), copy-to-clipboard where available, save-to-file on executors, plus project JSON export/import so you can save and reload builder projects

Notes: new blocks are inserted after the selected block; the window name appears in the generated callback stubs; `Polaris.Builder.SplashDuration = 0` skips the splash; `Polaris.Builder:Close()` tears everything down (the project survives in memory).

## Features

- **Window**: drag by title bar, resize via corner grip (min 400x280), minimize, close, toggle keybind, built-in search box that filters elements by name
- **Tabs** with optional icons, sections, dividers
- **Elements**: Button, Toggle, Slider, Dropdown (single and multi-select), ColorPicker (HSV popup), Keybind (with hold mode), Textbox, Paragraph
- **Uniform element API**: every element supports `:Set(value, silent?)`, `:Get()`, `:SetVisible()`, `:SetDisabled()`, `:Destroy()`
- **Themes**: 3 built-in, live switching that updates existing elements, `AddTheme()` for custom themes
- **Configs**: JSON export/import everywhere; file persistence (`Polaris/<folder>/<name>.json`) when the host provides `writefile`/`readfile` (executors), plus an in-memory fallback so save/load works even without file APIs
- **Builder**: splash, block editor, live preview, code + JSON export (see above)
- **Validation**: duplicate flags throw clear errors, sliders clamp and respect step size, dropdowns reject invalid options, config load/import warns about skipped values
- **Client-safe**: only standard client APIs; CoreGui is probed with a fallback to PlayerGui, so it works in Studio and executors

Design goals (exercised by the test suite): no `Init()` requirement; `:Get()`, `:SetVisible()`, `:SetDisabled()` and a silent-`Set` option on every element; live theme switching; element search; multi-select dropdowns; JSON config portability; deferred config auto-load; teardown with connection cleanup; and a builder whose generated scripts actually run.

## About the obfuscated build

The `Polaris.luau` at the repo root (the file the loadstrings fetch) is an obfuscated build of `src/Polaris.luau`. It is produced by `build/build.sh` — a repeatable pipeline that strips Luau-only syntax, then runs [Prometheus](https://github.com/prometheus-lua/Prometheus) with string encryption, constant-array shuffling, number mutation, and anti-tamper passes (the control-flow and VM passes are excluded: their output failed our Luau test suite for this input, and it also references `setfenv`/`getfenv`, which Roblox Luau does not provide). The full test suite is run against the exact published artifact before it is committed.

This is distribution obfuscation — it deters casual reading and copy-paste editing of the loadstring target. It is not unbreakable protection, and the readable source and full history are public in `src/`.

## API

### Window

```lua
local Window = Polaris:CreateWindow(config)
```

| Field | Type | Notes |
|---|---|---|
| `Name` | string | window title (required) |
| `Theme` | string | `"Default"`, `"Midnight"`, `"Light"`, or a custom theme name |
| `ToggleKey` | EnumItem | key that shows/hides the UI (can also be set later with `SetToggleKey`) |
| `Size` | Vector2 | default `Vector2.new(580, 400)` |
| `Position` | UDim2 | default centered |
| `SaveConfig` | bool | auto-load saved config after creation (deferred — create flagged elements right after the window) |
| `ConfigFolder` | string | folder name for config files |

Window methods: `CreateTab`, `SetTitle`, `SetToggleKey`, `SetVisible`, `GetVisible`, `SaveConfig`, `LoadConfig`, `ExportConfig`, `ImportConfig`, `Destroy`.

### Tabs & Sections

```lua
local Tab = Window:CreateTab({ Name = "Main", Icon = "rbxassetid://4483345998" })
Tab:CreateSection({ Name = "Section" })
```

### Elements

| Element | Key options |
|---|---|
| `CreateButton` | `Name`, `Callback` |
| `CreateToggle` | `Name`, `Default`, `Flag`, `Callback` |
| `CreateSlider` | `Name`, `Min`, `Max`, `Default`, `Increment`, `ValueName`, `Flag`, `Callback` |
| `CreateDropdown` | `Name`, `Options`, `Default`, `Multiple`, `Flag`, `Callback`; `:Refresh(options, keepSelection)` |
| `CreateColorPicker` | `Name`, `Default` (Color3), `Flag`, `Callback` |
| `CreateKeybind` | `Name`, `Default` (Enum.KeyCode), `Hold`, `Flag`, `Callback` |
| `CreateTextbox` | `Name`, `Default`, `TextDisappear`, `Flag`, `Callback(text, enterPressed)` |
| `CreateParagraph` | `Text` (update with `:SetText()`) |
| `CreateDivider` | — |

Multi-select dropdown values are tables: `{"a", "b"}` when setting, `{a = true, b = true}` from `:Get()`.

Two behavior notes: keybind callbacks mean "key was pressed", so config load/import restores keybind bindings **silently** (no activation fires); and disabling a textbox sets `TextEditable = false` and releases focus (`.Active` alone does not stop typing).

### Builder

The editor is one fullscreen canvas with `IgnoreGuiInset` (it covers the whole viewport, including the Roblox topbar):

- **Left palette** — tap a chip to add that block to the current tab, or drag it onto a specific column. Dragging a block onto the palette deletes it.
- **Center canvas** — one column per tab. Drag blocks to reorder them within a tab or move them between tabs; tap a block to select it.
- **Right properties panel** — everything about the selected block. Your edits save when you reselect (not on every keystroke).
- **Top bar** — hub name (live), palette/properties toggles, `+ Tab`, `Preview`, `Export`, `New`, `X`.

On screens narrower than `Builder.MinWorkspaceWidth` (900px by default — phones), the palette and properties collapse into toggleable drawers (the ◧ and ⚙ top-bar buttons) that overlay the canvas, which keeps the full screen width; only one drawer shows at a time, tapping a block opens the properties drawer automatically, and the compact top bar moves New into the export panel (which scrolls, so it works at any size). The editor also covers the Roblox topbar via `IgnoreGuiInset` and best-effort hides the hideable CoreGui (chat, backpack, leaderboard, player list, emotes, health) while it's open, restoring it on close — scripts can't remove the topbar buttons themselves.

Everything is designed for touch as well as mouse (drag with a threshold and a floating ghost block, big hit targets, tap-to-add), but none of it has been verified on a real device yet — test in Studio's device emulator before shipping.

| Member | Notes |
|---|---|
| `Polaris.Builder:Open()` | splash (if `SplashDuration > 0`) then the editor |
| `Polaris.Builder:Close()` / `:IsOpen()` | teardown / state |
| `Polaris.Builder:Generate()` | the hub script for the current project |
| `Polaris.Builder:ExportJSON()` / `:ImportJSON(str)` | save / restore builder projects |
| `Polaris.Builder:GetProject()` / `:SetProject(t)` / `:NewProject()` | direct project access |
| `Polaris.Builder:OpenPreview()` / `:ClosePreview()` | live preview window |
| `Polaris.Builder.SplashDuration` | seconds, default 1.6; 0 disables |
| `Polaris.Builder.PolarisURL` | URL used in the generated loader line |

### Flags & Configs

Give any element a `Flag` (unique within the window — duplicates throw). Then:

```lua
Window:SaveConfig("default")       -- writes a file if available, always keeps an in-memory copy
Window:LoadConfig("default")       -- apply (file first, in-memory fallback)
local json = Window:ExportConfig()  -- JSON string
Window:ImportConfig(json)           -- apply JSON
```

With `SaveConfig = true`, the window auto-loads the `"default"` config **deferred** — build your flagged elements immediately after `CreateWindow` and they will be restored. Load/import warns (does not throw) when values can't be applied.

### Themes

```lua
Polaris:SetTheme("Light")               -- live switch, updates existing elements
Polaris:AddTheme("Synthwave", {          -- missing keys inherit Default
	Background = Color3.fromRGB(20, 10, 30),
	Accent = Color3.fromRGB(255, 0, 200),
})
Polaris:GetThemeNames()                  -- for a theme dropdown
```

Theme keys: `Background`, `Secondary`, `Primary`, `Accent`, `Stroke`, `Text`, `SubText`, `Success`, `Warning`, `Danger`.

### Notifications

```lua
Polaris:Notify({
	Title = "Saved",
	Content = "Your config was exported",
	Duration = 4,
	Type = "success", -- success | warning | error (default: accent)
})
```

Notifications stack bottom-right and dismiss on click.

## Studio test checklist

Run `example.luau` as a LocalScript (library in ReplicatedStorage) and verify:

1. Window appears centered, Midnight theme colors applied (dark blue-ish, not white)
2. Drag by title bar stays within the screen; corner grip resizes with a 400x280 minimum
3. Toggle animates and the track turns accent blue when on
4. Slider drags smoothly and snaps to the increment; the value label updates
5. Dropdown opens, options highlight in accent when selected (single and multi)
6. Color picker popup: SV field shows gradients, hue bar is a rainbow, swatch updates
7. Keybind: click the key button, press a key, name updates; callback fires on press
8. Search box filters elements by name; clearing restores all
9. RightControl toggles the whole UI; minimize and close buttons work
10. `Window:ExportConfig()` prints JSON; `ImportConfig` restores values after changing them
11. No errors in Output after `Window:Destroy()`

Builder checklist (run `Polaris.Builder:Open()` in Studio):

1. Splash: dark screen, expanding ring, POLARIS title fades in, progress bar fills, fades to the editor
2. The editor covers the entire screen (no topbar gap) — palette left, canvas center, properties right
3. On desktop and on a phone: tap a palette chip to add a block, drag a block to reorder / move tabs / drop on the palette to delete
4. Tap a block — properties appear on the right; edits stick after reselecting
5. In the device emulator at phone size: the palette/properties are drawers, the ◧/⚙ buttons toggle them, and the canvas spans the full width
6. Chat/backpack/leaderboard hide while the editor is open and come back after close
7. Open Preview — a real window with your blocks appears; Close Preview removes it
8. Export: the generated code runs (paste it into a LocalScript with the library in ReplicatedStorage, replacing the loadstring line with a require)
9. Project JSON export/import round-trips

## Testing

Run from the project root:

```
lune run tests/test.luau                    # tests the obfuscated root Polaris.luau
lune run tests/test.luau src/Polaris.luau    # tests the readable source
```

45 cases covering: window/tab/element creation, toggle Set/Get + silent Set + click simulation, slider clamping/step normalization/drag simulation, window drag clamping from a centered position, dropdown validation + multi-select + JSON map-form values + highlight refresh, color picker round trip, keybind input, textbox, paragraph updates, duplicate-flag errors, SetVisible/SetDisabled/Destroy cleanup (including stopping an in-progress slider drag when disabled), config export/import round trip, in-memory save→load, deferred config auto-load via the scheduler, SetTitle, late SetToggleKey, notification ScreenGui ancestry, theme application and switching (including recoloring an enabled toggle), search filtering, notification validation, toggle keybind, window/tab teardown, the cross-window flag registry, textbox disabling (TextEditable + focus release), config restore never firing keybind activation callbacks — plus the builder: default project shape and copy semantics, add-after-selection insertion, move/duplicate/delete, codegen (escaping, flags, options), JSON round-trip, UI lifecycle and reopen, splash cleanup, live preview windows, and generated scripts executed end-to-end against the mock environment.

## Limitations

- Client-only (errors early if `Players.LocalPlayer` is nil)
- Visuals/layout/input/splash are unverified in a real Roblox client — see checklists above
- Paragraph height is estimated from text length, not measured
- The obfuscated build is distribution obfuscation, not unbreakable protection (source is public in `src/`)

## License

MIT — do whatever you want, credit appreciated.
