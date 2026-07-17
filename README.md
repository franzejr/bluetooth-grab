# 🔵 Bluetooth Grab

Move a Bluetooth device — a Magic Keyboard, trackpad, mouse, headphones, or any other paired peripheral — **onto the Mac in front of you** with a single toggle. 🖱️⌨️🎧

When you share a Bluetooth peripheral between two Macs, switching it over normally means navigating System Settings or toggling the device's power switch by hand. Bluetooth Grab is a small app with a window of your paired devices and an on/off switch next to each one: flip it on to grab the device onto this Mac, flip it off to release it for the other Mac. ✨

> **Mac-to-Mac only.** Run it on the Mac you want the device to connect **to**.
> Works with any paired device, not just Apple peripherals.

---

## ⬇️ Download

Grab the latest **`Bluetooth Grab.app`** from the [Releases page](https://github.com/franzejr/bluetooth-grab/releases/latest), unzip it, and drag it to your Applications folder or Dock.

> **First launch, two one-time steps:** 🔓
> 1. Because the app isn't notarized, right-click it and choose **Open** (instead of double-clicking) to bypass Gatekeeper, then confirm.
> 2. macOS will ask to let **Bluetooth Grab** use Bluetooth — click **Allow**. Without this, macOS blocks `blueutil` and the device list stays empty. If you dismissed it, grant it under **System Settings → Privacy & Security → Bluetooth**.

You'll still need [`blueutil`](#-requirements) installed. Prefer to build it yourself? See [Getting started](#-getting-started).

---

## 🤔 How it works

Open the app and you get a window listing every paired device with a switch:

| Action | What happens |
| --- | --- |
| **Toggle on** | Grabs the device onto this Mac — a plain `connect`, and only if that fails a re-pair. |
| **Toggle off** | Releases the device (disconnects it) so another Mac can grab it. |

The window **auto-refreshes** every few seconds, so the switches always reflect reality — if the other Mac grabs a device, its switch flips off here on its own.

To move a device between two Macs, run the app on both: **toggle it off** on the Mac that has it, then **toggle it on** on the Mac you want it on. Releasing it first is what makes the grab succeed — an Apple peripheral bonds to one host at a time, so it has to be let go before another Mac can take it.

> Turning off the keyboard or mouse you're currently using asks for confirmation first, so you don't accidentally disconnect what you're typing on. ⚠️

---

## 📦 Requirements

- macOS 13 (Ventura) or newer
- [`blueutil`](https://github.com/toy/blueutil) — the command-line Bluetooth utility the app drives:

  ```bash
  brew install blueutil
  ```

If `blueutil` isn't installed, the app says so and tells you the install command.

> **Empty device list?** If the app shows *"No paired Bluetooth devices"* even though you have some, macOS is almost certainly blocking Bluetooth access. Grant it under **System Settings → Privacy & Security → Bluetooth**, then reopen the app. A diagnostic log is kept at `~/.config/bluetooth-grab/last-run.log`.

---

## 🚀 Getting started

The app is a small SwiftUI program (in `Sources/BluetoothGrab/`) that talks to `blueutil`. Building it needs the Swift toolchain that ships with Xcode / the Command Line Tools.

### Build the app

```bash
./build-app.sh
```

This compiles the app in release mode and packages it into a double-clickable **`Bluetooth Grab.app`**. Drag it to your Dock for one-click access. 📌

Re-run `./build-app.sh` after any change to the sources.

### Develop

```bash
swift run     # build and launch straight from source
swift test    # run the unit + integration tests
```

The Bluetooth logic lives in `BlueutilClient`, which takes an injected command runner — so the grab/release behavior is unit-tested against a fake `blueutil`, no hardware required. A guarded integration test exercises the real `blueutil` when it's installed.

---

## 🧲 When a device won't connect

An Apple peripheral (Magic Keyboard and friends) stores only **one** host bond at a time. If the device is still actively connected to the other Mac, it won't be in its pairable state, and the grab can't take.

> **Fix:** release it on the other Mac first (toggle it off there). If that Mac is off or unreachable, flick the device's power switch off, then on, and toggle it on here again.

A normal grab never *unpairs* a device, so a failed grab never strips the device from this Mac — worst case, the switch just stays off and the status line tells you what to do.

### Force grab (last resort)

A normal grab (the toggle) tries a plain connect, then a re-pair — both non-destructive, so a device that won't connect just stays in the list and you can toggle it again to retry.

If a device is genuinely stuck — a stale or corrupt bond that no amount of retrying connects — open the **⋯** menu on that device's row and choose **Force grab…**. This unpairs the device and re-pairs it from scratch. Because it unpairs, it asks for confirmation first, and the device has to be in pairing mode (power switch off/on) for it to take. If the re-pair fails, the device drops off the list until you pair it again in System Settings — so it's a deliberate last resort, not the everyday path.

---

## 📄 License

Free and open source under the [MIT License](LICENSE) — use it, modify it, share it. 💙
