import XCTest
@testable import BluetoothGrab

/// A fake `blueutil` that models the semantics the real tool exposes, so we can
/// exercise the grab/release logic without any Bluetooth hardware.
// Single-threaded within each test, so unchecked Sendable is fine here.
final class FakeBluetooth: CommandRunner, @unchecked Sendable {
  var pairedOutput = ""
  var connected: Set<String> = []
  /// Addresses `--connect` connects immediately (device is free / bonded here).
  var connectableDirectly: Set<String> = []
  /// Addresses `--connect` connects only after a `--pair` (in pairing mode).
  var connectableAfterPair: Set<String> = []
  /// Simulate a `--paired` query that fails (non-zero exit).
  var pairedFails = false
  /// Simulate a `--is-connected` query that fails (non-zero exit, empty stdout).
  var isConnectedFails = false

  private(set) var calls: [[String]] = []
  private var pairedThisSession: Set<String> = []

  func run(_ executable: String, arguments: [String]) -> CommandResult {
    calls.append(arguments)
    switch arguments.first {
    case "--paired":
      if pairedFails { return CommandResult(exitCode: 1, stdout: "") }
      return CommandResult(exitCode: 0, stdout: pairedOutput)

    case "--is-connected":
      if isConnectedFails { return CommandResult(exitCode: 1, stdout: "") }
      let addr = arguments[1]
      return CommandResult(exitCode: 0, stdout: connected.contains(addr) ? "1" : "0")

    case "--connect":
      let addr = arguments[1]
      let canConnect = connectableDirectly.contains(addr)
        || (pairedThisSession.contains(addr) && connectableAfterPair.contains(addr))
      if canConnect { connected.insert(addr) }
      return CommandResult(exitCode: canConnect ? 0 : 1, stdout: "")

    case "--wait-connect":
      let addr = arguments[1]
      return CommandResult(exitCode: connected.contains(addr) ? 0 : 1, stdout: "")

    case "--pair":
      pairedThisSession.insert(arguments[1])
      return CommandResult(exitCode: 0, stdout: "")

    case "--unpair":
      let addr = arguments[1]
      connected.remove(addr)
      pairedThisSession.remove(addr)
      return CommandResult(exitCode: 0, stdout: "")

    case "--disconnect":
      connected.remove(arguments[1])
      return CommandResult(exitCode: 0, stdout: "")

    default:
      return CommandResult(exitCode: 0, stdout: "")
    }
  }

  var issuedCommands: [String] { calls.compactMap(\.first) }
}

final class BlueutilClientTests: XCTestCase {

  // MARK: - Parsing

  func testParsesConnectedAndDisconnectedDevices() {
    let paired = """
    address: dc-2c-26-36-d5-ef, connected, not favourite, paired, name: "Keychron K3", recent access date: 2026-07-16
    address: e5-4a-16-66-3b-77, not connected, not favourite, paired, name: "MX Vertical", recent access date: 2026-07-16
    """
    let fake = FakeBluetooth()
    fake.pairedOutput = paired
    let client = BlueutilClient(runner: fake)

    let devices = client.pairedDevices()

    XCTAssertEqual(devices?.count, 2)
    XCTAssertEqual(devices?[0], BluetoothDevice(address: "dc-2c-26-36-d5-ef", name: "Keychron K3", isConnected: true))
    XCTAssertEqual(devices?[1], BluetoothDevice(address: "e5-4a-16-66-3b-77", name: "MX Vertical", isConnected: false))
  }

  func testFallsBackToAddressWhenNameIsMissing() {
    let line = Substring(#"address: 38-09-fb-1d-04-a2, not connected, paired, name: "", recent access date: x"#)
    let device = BlueutilClient.parseDeviceLine(line)
    XCTAssertEqual(device?.displayName, "38-09-fb-1d-04-a2")
  }

  func testConnectionStateIgnoresTheDeviceName() {
    // A disconnected device whose *name* contains ", connected," must not be
    // read as connected — the status comes from the field after the address.
    let disconnected = Substring(#"address: aa-bb, not connected, paired, name: "Cam, connected, v2", recent: x"#)
    XCTAssertEqual(BlueutilClient.parseDeviceLine(disconnected)?.isConnected, false)

    let connected = Substring(#"address: cc-dd, connected, paired, name: "Keychron K3", recent: x"#)
    XCTAssertEqual(BlueutilClient.parseDeviceLine(connected)?.isConnected, true)
  }

  func testPairedDevicesReturnsNilWhenTheQueryFails() {
    let fake = FakeBluetooth()
    fake.pairedFails = true
    let client = BlueutilClient(runner: fake)
    XCTAssertNil(client.pairedDevices(), "a failed query must be distinguishable from an empty list")
  }

  // MARK: - Grab

  func testGrabReturnsAlreadyConnectedWithoutTouchingThePairing() {
    let fake = FakeBluetooth()
    fake.connected = ["aa-bb"]
    let client = BlueutilClient(runner: fake)

    XCTAssertEqual(client.grab("aa-bb"), .alreadyConnected)
    XCTAssertFalse(fake.issuedCommands.contains("--connect"))
    XCTAssertFalse(fake.issuedCommands.contains("--pair"))
  }

  func testGrabConnectsAFreeDeviceWithoutRepairing() {
    let fake = FakeBluetooth()
    fake.connectableDirectly = ["aa-bb"]
    let client = BlueutilClient(runner: fake)

    XCTAssertEqual(client.grab("aa-bb"), .connected)
    XCTAssertTrue(fake.connected.contains("aa-bb"))
    XCTAssertFalse(fake.issuedCommands.contains("--pair"), "a plain connect must not trigger a re-pair")
  }

  func testGrabFallsBackToPairingWhenPlainConnectFails() {
    let fake = FakeBluetooth()
    fake.connectableAfterPair = ["aa-bb"]  // only connects once in pairing mode
    let client = BlueutilClient(runner: fake)

    XCTAssertEqual(client.grab("aa-bb"), .connected)
    XCTAssertTrue(fake.issuedCommands.contains("--pair"))
  }

  func testGrabNeverUnpairsSoAFailedGrabDoesNotLoseTheDevice() {
    let fake = FakeBluetooth()  // device connects via no path → held by other Mac
    let client = BlueutilClient(runner: fake)

    XCTAssertEqual(client.grab("aa-bb"), .failed)
    XCTAssertFalse(fake.issuedCommands.contains("--unpair"),
                   "must never unpair — that would strip the device from this Mac")
  }

  // MARK: - Reset pairing

  func testResetPairingUnpairsThenRepairsAndConnects() {
    let fake = FakeBluetooth()
    fake.connectableAfterPair = ["aa-bb"]  // only reconnects after a fresh pair
    let client = BlueutilClient(runner: fake, settle: {})

    XCTAssertEqual(client.resetPairing("aa-bb"), .connected)
    XCTAssertEqual(fake.issuedCommands.filter { $0 == "--unpair" }.count, 1,
                   "reset must clear the old bond exactly once")
    XCTAssertTrue(fake.issuedCommands.contains("--pair"))
  }

  func testResetPairingFailsWhenDeviceNotInPairingMode() {
    let fake = FakeBluetooth()  // never connectable → not in pairing mode
    let client = BlueutilClient(runner: fake, settle: {})

    XCTAssertEqual(client.resetPairing("aa-bb"), .failed)
  }

  // MARK: - Release

  func testReleaseDisconnectsTheDevice() {
    let fake = FakeBluetooth()
    fake.connected = ["aa-bb"]
    let client = BlueutilClient(runner: fake)

    XCTAssertTrue(client.release("aa-bb"))
    XCTAssertFalse(fake.connected.contains("aa-bb"))
  }

  func testReleaseReportsFailureWhenStateCannotBeConfirmed() {
    // If the post-disconnect state query fails, we must not claim success —
    // reporting "released" while the device is still held would strand the
    // other Mac's grab with no explanation.
    let fake = FakeBluetooth()
    fake.connected = ["aa-bb"]
    fake.isConnectedFails = true
    let client = BlueutilClient(runner: fake)

    XCTAssertFalse(client.release("aa-bb"))
  }
}
