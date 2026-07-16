import XCTest
@testable import BluetoothGrab

/// Exercises the real subprocess runner against small system commands — no
/// Bluetooth involved, so these run anywhere including CI.
final class ProcessCommandRunnerTests: XCTestCase {

  func testCapturesStdoutAndExitCode() {
    let runner = ProcessCommandRunner(timeout: 5)
    let result = runner.run("/bin/echo", arguments: ["hello"])
    XCTAssertTrue(result.succeeded)
    XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "hello")
  }

  func testKillsACommandThatExceedsItsTimeout() {
    let runner = ProcessCommandRunner(timeout: 0.5)
    let start = Date()
    let result = runner.run("/bin/sleep", arguments: ["10"])
    let elapsed = Date().timeIntervalSince(start)

    XCTAssertEqual(result.exitCode, CommandResult.timedOutExitCode,
                   "a hung command must be reported as timed out, not succeeded")
    XCTAssertLessThan(elapsed, 4, "the command should be killed near its timeout, not run to completion")
  }

  func testReportsFailureForAMissingExecutable() {
    let runner = ProcessCommandRunner(timeout: 5)
    let result = runner.run("/nonexistent/blueutil", arguments: ["--paired"])
    XCTAssertFalse(result.succeeded)
  }
}
