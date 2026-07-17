import Foundation
import SwiftUI

/// Drives the device list window: loads paired devices, polls their connection
/// state so a toggle always reflects reality, and runs grab/release off the
/// main thread (a grab can block for several seconds while Bluetooth settles).
@MainActor
final class DeviceListViewModel: ObservableObject {
  @Published private(set) var devices: [BluetoothDevice] = []
  @Published private(set) var busyAddresses: Set<String> = []
  @Published private(set) var status: String?
  @Published private(set) var blueutilMissing = false

  /// While an operation is in flight the real state lags, so we show the state
  /// the user asked for. Cleared once a refresh confirms the real state.
  private var optimistic: [String: Bool] = [:]

  /// The toggle position for a device: the pending target if mid-operation,
  /// otherwise the real connection state.
  func isOn(_ device: BluetoothDevice) -> Bool {
    optimistic[device.address] ?? device.isConnected
  }

  func isBusy(_ device: BluetoothDevice) -> Bool {
    busyAddresses.contains(device.address)
  }

  /// Address of a device whose release needs confirming (the one you're using).
  @Published var pendingRelease: BluetoothDevice?

  /// Device awaiting confirmation for a force grab (unpair is destructive).
  @Published var pendingForceGrab: BluetoothDevice?

  private let client: BlueutilClient
  private let pollInterval: Duration
  private var pollTask: Task<Void, Never>?

  /// In-flight grab/release, keyed by address (one per device — the busy guard
  /// prevents a second). Tracked so `stop()` can cancel them on teardown.
  private var operations: [String: Task<Void, Never>] = [:]

  init(
    client: BlueutilClient = BlueutilClient(runner: ProcessCommandRunner()),
    pollInterval: Duration = .seconds(3)
  ) {
    self.client = client
    self.pollInterval = pollInterval
  }

  // MARK: - Lifecycle

  func start() {
    blueutilMissing = !BlueutilClient.isInstalled()
    guard !blueutilMissing else {
      status = "blueutil not found — install it with:  brew install blueutil"
      return
    }
    pollTask = Task { [weak self] in await self?.pollLoop() }
  }

  func stop() {
    pollTask?.cancel()
    pollTask = nil
    operations.values.forEach { $0.cancel() }
    operations.removeAll()
  }

  private func pollLoop() async {
    while !Task.isCancelled {
      await refresh()
      try? await Task.sleep(for: pollInterval)
    }
  }

  /// Reload the device list, but don't clobber a device mid-toggle. A failed
  /// query returns nil — we keep the current list rather than blanking it, so a
  /// transient poll error doesn't flash an empty "no devices" state.
  func refresh() async {
    let client = self.client
    let busy = busyAddresses
    let queried = await Task.detached { client.pairedDevices() }.value
    guard let loaded = queried else { return }
    devices = loaded.map { device in
      busy.contains(device.address)
        ? (devices.first { $0.address == device.address } ?? device)
        : device
    }
  }

  // MARK: - Toggling

  /// Called when a device's toggle is flipped. Grabs when turning on; when
  /// turning off, confirms first if it's the device you're currently using.
  func setConnected(_ device: BluetoothDevice, to on: Bool) {
    guard !busyAddresses.contains(device.address) else { return }
    if on {
      grab(device)
    } else if isLikelyInputDevice(device) {
      pendingRelease = device
    } else {
      release(device)
    }
  }

  func confirmRelease() {
    guard let device = pendingRelease else { return }
    pendingRelease = nil
    release(device)
  }

  func cancelRelease() {
    // Snap the toggle back on — the device is still connected.
    pendingRelease = nil
    objectWillChange.send()
  }

  // MARK: - Force grab

  /// Ask to force-grab a device — the aggressive unpair-and-repair path for a
  /// device a normal grab can't connect. Because it unpairs, it always confirms
  /// first (a failed force grab drops the device until it's re-paired).
  func requestForceGrab(_ device: BluetoothDevice) {
    guard !busyAddresses.contains(device.address) else { return }
    pendingForceGrab = device
  }

  func confirmForceGrab() {
    guard let device = pendingForceGrab else { return }
    pendingForceGrab = nil
    forceGrab(device)
  }

  func cancelForceGrab() {
    pendingForceGrab = nil
  }

  private func forceGrab(_ device: BluetoothDevice) {
    perform(device, verb: "Force-grabbing", target: true) { client in
      client.forceGrab(device.address) != .failed
    }
    .onDone { [weak self] ok in
      self?.status = ok
        ? "✓ \(device.displayName) — force-grabbed and connected"
        : "✗ \(device.displayName) — force grab failed. Put the device in pairing mode (power switch off/on), then re-pair it in System Settings if it's no longer listed."
    }
  }

  private func grab(_ device: BluetoothDevice) {
    perform(device, verb: "Grabbing", target: true) { client in client.grab(device.address) != .failed }
      .onDone { [weak self] ok in
        self?.status = ok
          ? "✓ \(device.displayName) — connected"
          : "✗ \(device.displayName) — couldn't grab. Toggle it on again to retry, or release it on the other Mac. Still stuck? Use ⋯ → Force grab."
      }
  }

  private func release(_ device: BluetoothDevice) {
    perform(device, verb: "Releasing", target: false) { client in client.release(device.address) }
      .onDone { [weak self] ok in
        self?.status = ok
          ? "○ \(device.displayName) — released. Another Mac can grab it now."
          : "✗ \(device.displayName) — couldn't release."
      }
  }

  // MARK: - Internals

  /// Marks a device busy, runs a blocking blueutil operation off-main, then
  /// refreshes. Returns a tiny handle so callers can set a status message.
  @discardableResult
  private func perform(
    _ device: BluetoothDevice,
    verb: String,
    target: Bool,
    _ operation: @escaping @Sendable (BlueutilClient) -> Bool
  ) -> OperationHandle {
    let handle = OperationHandle()
    busyAddresses.insert(device.address)
    optimistic[device.address] = target
    status = "\(verb) \(device.displayName)…"
    let client = self.client
    let address = device.address
    operations[address] = Task { [weak self] in
      let ok = await Task.detached { operation(client) }.value
      guard let self else { return }
      self.busyAddresses.remove(address)
      await self.refresh()
      self.optimistic[address] = nil
      self.operations[address] = nil
      handle.completion?(ok)
    }
    return handle
  }

  /// A Magic Keyboard/Trackpad/Mouse is one you might be typing on right now, so
  /// releasing it deserves a confirm. Heuristic on the name — good enough, and
  /// the user can always confirm.
  private func isLikelyInputDevice(_ device: BluetoothDevice) -> Bool {
    let name = device.displayName.lowercased()
    return ["keyboard", "trackpad", "mouse", "magic"].contains { name.contains($0) }
  }
}

/// Lets `perform` hand back a completion the caller fills in, without threading
/// the status text through every operation.
final class OperationHandle {
  fileprivate var completion: (@MainActor (Bool) -> Void)?
  @discardableResult
  func onDone(_ block: @escaping @MainActor (Bool) -> Void) -> OperationHandle {
    completion = block
    return self
  }
}
