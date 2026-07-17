import Foundation

/// The result of attempting to grab a device onto this Mac.
enum GrabOutcome: Equatable {
  /// The device was already connected here — nothing to do.
  case alreadyConnected
  /// We connected it (directly, or after re-pairing).
  case connected
  /// We could not connect it. Almost always this means the device is still
  /// held by the other Mac and isn't in its pairable window — the user needs
  /// to release it there (toggle off) or power-cycle the peripheral.
  case failed
}

/// Talks to the `blueutil` command-line tool. This is the brain of the app:
/// listing paired devices, reading connection state, and the grab/release
/// logic. It never touches Bluetooth directly — everything goes through an
/// injected `CommandRunner`, which keeps the logic fully unit-testable.
struct BlueutilClient: Sendable {
  private let runner: any CommandRunner
  private let blueutilPath: String
  private let connectTimeout: Int
  /// A brief pause after `--unpair` before re-pairing, so the removal settles.
  /// Injectable (a no-op in tests) to keep `resetPairing` fast and hardware-free.
  private let settle: @Sendable () -> Void

  init(
    runner: any CommandRunner,
    blueutilPath: String = BlueutilClient.defaultBlueutilPath(),
    connectTimeout: Int = 6,
    settle: @escaping @Sendable () -> Void = { Thread.sleep(forTimeInterval: 1) }
  ) {
    self.runner = runner
    self.blueutilPath = blueutilPath
    self.connectTimeout = connectTimeout
    self.settle = settle
  }

  // MARK: - Reading state

  /// Every paired device, with its current connection state — or `nil` if the
  /// query itself failed. Callers should treat `nil` as "state unknown, keep
  /// what you had" rather than "no devices": a transient failure on a poll must
  /// not blank out the list or drop a device mid-grab.
  func pairedDevices() -> [BluetoothDevice]? {
    let result = runner.run(blueutilPath, arguments: ["--paired"])
    guard result.succeeded else {
      AppLog.log("--paired failed (exit \(result.exitCode))")
      return nil
    }
    return result.stdout
      .split(separator: "\n")
      .compactMap(Self.parseDeviceLine)
  }

  func isConnected(_ address: String) -> Bool {
    connectionState(address) == true
  }

  /// The connected state of a device, or `nil` when we can't determine it (the
  /// query failed or returned something unexpected). Distinguishing "unknown"
  /// from "not connected" keeps us from reporting a release/grab as done when
  /// we never actually confirmed the state.
  private func connectionState(_ address: String) -> Bool? {
    let result = runner.run(blueutilPath, arguments: ["--is-connected", address])
    guard result.succeeded else { return nil }
    switch result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) {
    case "1": return true
    case "0": return false
    default: return nil
    }
  }

  // MARK: - Grab / release

  /// Grab a device onto this Mac.
  ///
  /// We try the gentle path first — a plain `--connect`, which is all a device
  /// that's already bonded here and currently free needs. Only if that fails do
  /// we re-pair (the device must be in pairing mode for that to take). We never
  /// `--unpair` first: unpairing then failing to re-pair would strip the device
  /// from this Mac entirely, which is exactly the "grab lost my device" trap.
  func grab(_ address: String) -> GrabOutcome {
    if isConnected(address) {
      AppLog.log("grab \(address): already connected")
      return .alreadyConnected
    }

    if connectAndVerify(address) {
      AppLog.log("grab \(address): connected")
      return .connected
    }

    // Fallback: the bond may be stale or absent. Re-pair (only takes effect if
    // the device is in its pairable window) and try once more.
    _ = runner.run(blueutilPath, arguments: ["--pair", address])
    if connectAndVerify(address) {
      AppLog.log("grab \(address): connected after re-pair")
      return .connected
    }

    AppLog.log("grab \(address): FAILED (device likely held by another Mac)")
    return .failed
  }

  /// Forcibly grab a device by tearing down its bond and re-pairing from
  /// scratch: `--unpair`, then `--pair`, then connect.
  ///
  /// This is the aggressive path for a device a normal `grab` can't connect —
  /// a stale or corrupt bond where `--connect` fails and `--pair` is a no-op
  /// because a broken bond record already exists. Unlike `grab`, it *does*
  /// `--unpair` — which strips the pairing if the re-pair then fails — so it's
  /// only ever run on explicit user request, never automatically. The device
  /// must be in pairing mode for the re-pair to take.
  func forceGrab(_ address: String) -> GrabOutcome {
    AppLog.log("force-grab \(address): unpairing")
    _ = runner.run(blueutilPath, arguments: ["--unpair", address])
    settle()
    _ = runner.run(blueutilPath, arguments: ["--pair", address])
    if connectAndVerify(address) {
      AppLog.log("force-grab \(address): connected")
      return .connected
    }
    AppLog.log("force-grab \(address): FAILED (put the device in pairing mode and retry)")
    return .failed
  }

  /// Release a device from this Mac so another host can grab it. Reports success
  /// only when we positively confirm the device is no longer connected — a
  /// failed state query counts as "couldn't confirm", not "released".
  func release(_ address: String) -> Bool {
    _ = runner.run(blueutilPath, arguments: ["--disconnect", address])
    _ = runner.run(blueutilPath, arguments: ["--wait-disconnect", address, String(connectTimeout)])
    let released = connectionState(address) == false
    AppLog.log("release \(address): \(released ? "released" : "could not confirm release")")
    return released
  }

  // MARK: - Internals

  /// Issue a connect and wait for it to take, then confirm via `--is-connected`
  /// (the source of truth) rather than trusting the connect's own exit code.
  private func connectAndVerify(_ address: String) -> Bool {
    _ = runner.run(blueutilPath, arguments: ["--connect", address])
    _ = runner.run(blueutilPath, arguments: ["--wait-connect", address, String(connectTimeout)])
    return isConnected(address)
  }

  // MARK: - Parsing

  /// Compiled once — `pairedDevices()` runs on every poll, so recompiling these
  /// per device per cycle would be wasteful.
  private static let addressRegex = try! NSRegularExpression(pattern: #"address: ([^,]+),"#)
  private static let nameRegex = try! NSRegularExpression(pattern: #"name: "([^"]*)""#)
  /// The connection status is the field immediately after the address, so we
  /// anchor to it — never scanning the free-form device name for "connected".
  private static let statusRegex = try! NSRegularExpression(pattern: #"address: [^,]+, (not connected|connected),"#)

  /// Parse one line of `blueutil --paired` output, e.g.
  ///   address: dc-2c-26-36-d5-ef, not connected, ... name: "Keychron K3", ...
  static func parseDeviceLine(_ line: Substring) -> BluetoothDevice? {
    guard let address = capture(addressRegex, in: line) else { return nil }
    let name = capture(nameRegex, in: line) ?? ""
    let isConnected = capture(statusRegex, in: line) == "connected"
    return BluetoothDevice(address: address, name: name, isConnected: isConnected)
  }

  private static func capture(_ regex: NSRegularExpression, in line: Substring) -> String? {
    let text = String(line)
    guard
      let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
      let range = Range(match.range(at: 1), in: text)
    else { return nil }
    return String(text[range])
  }

  // MARK: - Locating blueutil

  /// GUI apps don't inherit a shell PATH, so we look in the usual Homebrew
  /// spots explicitly. Falls back to the Apple-Silicon path.
  static func defaultBlueutilPath() -> String {
    let candidates = ["/opt/homebrew/bin/blueutil", "/usr/local/bin/blueutil"]
    return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
      ?? candidates[0]
  }

  /// Whether `blueutil` is installed where we expect it.
  static func isInstalled() -> Bool {
    FileManager.default.isExecutableFile(atPath: defaultBlueutilPath())
  }
}
