import Foundation

/// A tiny append-only log at ~/.config/bluetooth-grab/last-run.log.
///
/// The app usually runs with no terminal attached (double-clicked), so when a
/// grab fails there's nowhere for output to go. This keeps a durable trail of
/// the meaningful actions — grabs, releases, and command failures — so an
/// intermittent problem can be diagnosed after the fact. Routine background
/// polls are intentionally *not* logged, to keep the file readable.
enum AppLog {
  private static let queue = DispatchQueue(label: "com.franzejr.bluetoothgrab.log")

  private static var fileURL: URL {
    let dir = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".config/bluetooth-grab", isDirectory: true)
    return dir.appendingPathComponent("last-run.log")
  }

  static func log(_ message: String) {
    // Don't pollute the real log file when running under XCTest.
    if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }

    let stamped = "\(timestamp())  \(message)\n"
    queue.async {
      let url = fileURL
      try? FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true
      )
      guard let data = stamped.data(using: .utf8) else { return }
      if let handle = try? FileHandle(forWritingTo: url) {
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
      } else {
        try? data.write(to: url)
      }
    }
  }

  private static func timestamp() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    return formatter.string(from: Date())
  }
}
