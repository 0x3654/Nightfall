# DarkThemeSync

Форк [Nightfall](https://github.com/r-thomson/Nightfall) — переключатель тёмной темы macOS — с синхронизацией темы в Windows-VM Parallels.

> [!IMPORTANT]
> **Этот форк** (база — оригинальный [r-thomson/Nightfall](https://github.com/r-thomson/Nightfall) @ `9e3f0a1`) расширяет его:
>
> - 🌓 **Синк темы в Windows-VM** — галка в настройках: любая смена темы мака (хоткей, Control Center, таймер) перекрашивает все указанные Parallels-VM с Windows за пару секунд. Событийно, без поллинга.
> - 🖥 **Self-provisioning** — приложение само находит VM, кнопкой Setup разворачивает обвязку в госте и показывает статус каждой VM; Remove снимает. Установка с нуля = один app.
> - ⚙️ **Список VM через запятую** — пуш параллельно во все живые, выключенные тихо пропускаются.
> - 🔓 **App Sandbox снята** — без неё нельзя запускать `prlctl`.

---

Nightfall lets you manage macOS's dark mode from the menu bar. Left click the icon to toggle dark mode; right click to reveal additional options.

https://user-images.githubusercontent.com/29545379/150662417-90e6a4f8-7ad9-436a-8ee9-0b11882e0d4a.mp4

## Download

| | Version | Signed |
|---|---|---|
| **This fork** (+ Windows-VM theme sync) | [releases of this repository](../../releases) | ✗ ad-hoc |
| **Official release** | [latest](https://github.com/r-thomson/Nightfall/releases/latest) | ✓ |

1. Download **Nightfall-arm64.zip** from the releases page
2. Unzip and move **Nightfall.app** into **Applications**
3. Launch — grant **Screen Recording** permission if you enable animated transitions

> Unsigned build note: on first launch macOS may block the app.
> Right-click → **Open** → **Open**, or System Settings → Privacy & Security → **Open Anyway**.

### Build from source

```sh
cd nightfall-fork
xcodebuild -project Nightfall.xcodeproj -scheme Nightfall -configuration Release \
  -derivedDataPath build CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="BetterOSD Dev"
```
## Usage

**Left click** Nightfall’s icon in the menu bar to toggle dark mode.  
**Right click** the icon to show the options menu.

### Setting a Keyboard Shortcut

Nightfall allows you to toggle dark mode from anywhere with a configurable keyboard shortcut. By default, this will be set to <kbd>^⌥⌘T</kbd>. You can change this in Nightfall's settings.

### Using Animated Transitions

If “Animated transition“ is enabled in preferences, Nightfall will smooth over the transition between light and dark modes with a short animation. Because of how this feature works (source code [here](Nightfall/ToggleDarkMode.swift)), **you’ll need to grant Nightfall [screen recording permissions](https://support.apple.com/guide/mac-help/control-access-to-screen-recording-on-mac-mchld6aa7d23/mac)**.

### Hiding Nightfall

If you’d like to hide Nightfall from your menu bar without quitting the app, you can do so by holding the Command key and dragging the icon out of the menu bar. To reveal Nightfall again, re-open the app while it’s still running.

