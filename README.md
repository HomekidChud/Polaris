# Polaris

A single-file UI library for Roblox Luau. Drop it into any client script and get a themed, draggable, resizable window with tabs and every common control — no `:Init()` call required.

```
Polaris.luau   -- the entire library (one file)
example.luau   -- Studio LocalScript demo of every element
tests/         -- logic test suite (runs under Lune)
```

## Status: prototype, logic-tested only

- The code compiles under the Luau compiler, and a 35-case logic suite passes under [Lune](https://lune.dev) with a mocked Roblox environment (validation, clamping, drag clamping, config round-trips, deferred config loading, cleanup, theming, search).
- **Visual rendering, dragging, touch handling, and layout have NOT been verified in Roblox.** Test in Studio before shipping (checklist below).

## Quick start

**Studio:** put `Polaris.luau` in ReplicatedStorage as a ModuleScript named `Polaris`, then in a LocalScript:
```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Polaris = require(ReplicatedStorage:WaitForChild("Polaris"))
```

**Executor** (once the file is on your GitHub):
```lua
local Polaris = loadstring(game:HttpGet("https://raw.githubusercontent.com/HomekidChud/Polaris/main/Polaris.luau"))()
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

## Features

- **Window**: drag by title bar, resize via corner grip (min 400x280), minimize, close, toggle keybind, built-in search box that filters elements by name
- **Tabs** with optional icons, sections, dividers
- **Elements**: Button, Toggle, Slider, Dropdown (single and multi-select), ColorPicker (HSV popup), Keybind (with hold mode), Textbox, Paragraph
- **Uniform element API**: every element supports `:Set(value, silent?)`, `:Get()`, `:SetVisible()`, `:SetDisabled()`, `:Destroy()`
- **Themes**: 3 built-in, live switching that updates existing elements, `AddTheme()` for custom themes
- **Configs**: JSON export/import everywhere; file persistence (`Polaris/<folder>/<name>.json`) when the host provides `writefile`/`readfile` (executors), plus an in-memory fallback so save/load works even without file APIs
- **Validation**: duplicate flags throw clear errors, sliders clamp and respect step size, dropdowns reject invalid options, config load/import warns about skipped values
- **Client-safe**: only standard client APIs; CoreGui is probed with a fallback to PlayerGui, so it works in Studio and executors

Design goals (exercised by the test suite): no `Init()` requirement; `:Get()`, `:SetVisible()`, `:SetDisabled()` and a silent-`Set` option on every element; live theme switching; element search; multi-select dropdowns; JSON config portability; deferred config auto-load; and teardown with connection cleanup.

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

## Testing

Run from the project root:

```
lune run tests/test.luau
```

35 cases covering: window/tab/element creation, toggle Set/Get + silent Set + click simulation, slider clamping/step normalization/drag simulation, window drag clamping from a centered position, dropdown validation + multi-select + JSON map-form values + highlight refresh, color picker round trip, keybind input, textbox, paragraph updates, duplicate-flag errors, SetVisible/SetDisabled/Destroy cleanup (including stopping an in-progress slider drag when disabled), config export/import round trip, in-memory save→load, deferred config auto-load via the scheduler, SetTitle, late SetToggleKey, notification ScreenGui ancestry, theme application and switching (including recoloring an enabled toggle), search filtering, notification validation, toggle keybind, window/tab teardown, the cross-window flag registry, textbox disabling (TextEditable + focus release), and config restore never firing keybind activation callbacks.

## Limitations

- Client-only (errors early if `Players.LocalPlayer` is nil)
- Visuals/layout/input are unverified in a real Roblox client — see checklist above
- Paragraph height is estimated from text length, not measured

## License

MIT — do whatever you want, credit appreciated.
