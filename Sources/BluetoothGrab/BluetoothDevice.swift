import Foundation

/// A paired Bluetooth peripheral as reported by `blueutil --paired`.
struct BluetoothDevice: Identifiable, Equatable, Sendable {
  let address: String
  let name: String
  var isConnected: Bool

  /// The address uniquely identifies a device across runs, so it's our id.
  var id: String { address }

  /// A human-friendly label. macOS sometimes fails to resolve a friendly name
  /// and reports the address as the name; in that case we show just the address.
  var displayName: String {
    name.isEmpty || name == address ? address : name
  }
}
