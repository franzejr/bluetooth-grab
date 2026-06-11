# 🔵 Bluetooth Grab

Move a Bluetooth device — a Magic Keyboard, trackpad, mouse, headphones, or any other paired peripheral — **onto the Mac in front of you** with a single click. 🖱️⌨️🎧

When you share a Bluetooth peripheral between two Macs, switching it over normally means navigating System Settings or toggling the device's power switch by hand. Bluetooth Grab reduces that to: double-click, pick the device, done. ✨

> **Mac-to-Mac only.** Run it on the Mac you want the device to connect **to**.
> Works with any paired device, not just Apple peripherals.

---

## ⬇️ Download

Grab the latest **`Bluetooth Grab.app`** from the [Releases page](https://github.com/franzejr/bluetooth-grab/releases/latest), unzip it, and drag it to your Applications folder or Dock.

> First launch: because the app isn't notarized, right-click it and choose **Open** (instead of double-clicking) to bypass Gatekeeper, then confirm. You only need to do this once. 🔓

You'll still need [`blueutil`](#-requirements) installed. Prefer to build it yourself? See [Getting started](#-getting-started).

---

## 🤔 How it works

1. Clears any stale pairing for the device on this Mac.
2. Re-pairs the device.
3. Connects it.
4. Reports the outcome in a native macOS dialog.

Each run presents a picker of your paired devices with your previous choice pre-selected, so most runs are a single click on **OK**. The selection is saved to `~/.config/bluetooth-grab/devices.conf`.

---

## 📦 Requirements

- macOS
- [`blueutil`](https://github.com/toy/blueutil) — the command-line Bluetooth utility:

  ```bash
  brew install blueutil
  ```

---

## 🚀 Getting started

### Build the app

```bash
./build-app.sh
```

This packages the script into a double-clickable **`Bluetooth Grab.app`**. Double-click it, or drag it to your Dock for one-click access. 📌

Re-run `./build-app.sh` after any change to `bluetooth-grab.sh`.

### Run from the terminal

You can also run the script directly:

```bash
./bluetooth-grab.sh
```

When run in a terminal it prints plain text; when launched as an app it uses native macOS dialogs and notifications.

---

## 🧲 When a device won't connect

A Magic Keyboard (and similar peripherals) stores only **one** host bond at a time. If the device is still actively connected to the other Mac, it won't be in its pairable state.

> **Fix:** toggle the device's power switch off, then on, and run Bluetooth Grab again.

The result dialog repeats this guidance whenever a grab fails. ⚠️

---

## ⚙️ Configuration & logs

| Item | Location |
| --- | --- |
| Saved device selection | `~/.config/bluetooth-grab/devices.conf` |
| Last-run log | `~/.config/bluetooth-grab/last-run.log` |

Every Bluetooth call runs under a hard timeout (default **25s**, configurable via `BT_TIMEOUT`) so a stuck pairing surfaces as a clear failure rather than hanging. ⏱️

---

## 📄 License

Free and open source under the [MIT License](LICENSE) — use it, modify it, share it. 💙
