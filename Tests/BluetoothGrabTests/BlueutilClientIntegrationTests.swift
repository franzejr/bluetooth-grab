import XCTest
@testable import BluetoothGrab

/// Exercises the real `ProcessCommandRunner` against the installed `blueutil`.
/// Skipped automatically when blueutil isn't present (e.g. in CI), so it never
/// turns the suite red on a machine without Bluetooth tooling.
final class BlueutilClientIntegrationTests: XCTestCase {
  private var blueutilAvailable: Bool {
    FileManager.default.isExecutableFile(atPath: BlueutilClient.defaultBlueutilPath())
  }

  func testListsRealPairedDevicesAndReadsTheirState() throws {
    try XCTSkipUnless(blueutilAvailable, "blueutil not installed")

    let client = BlueutilClient(runner: ProcessCommandRunner())
    let devices = try XCTUnwrap(client.pairedDevices(), "--paired should succeed when blueutil is installed")

    // We can't assume any particular device is paired, but if any are, they
    // must parse cleanly: a non-empty address and a resolvable display name.
    // (We deliberately don't assert isConnected matches a separate --is-connected
    // call — a device can change state between the two, which would flake.)
    for device in devices {
      XCTAssertFalse(device.address.isEmpty, "every paired device must have an address")
      XCTAssertFalse(device.displayName.isEmpty)
      // A live state query must at least run without crashing.
      _ = client.isConnected(device.address)
    }
  }
}
