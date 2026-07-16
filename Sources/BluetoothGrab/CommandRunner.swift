import Foundation

/// The outcome of running an external command: its exit status and captured
/// standard output. `blueutil` signals success/failure through its exit code
/// (0 = ok) and returns query results on stdout, so both matter.
struct CommandResult {
  let exitCode: Int32
  let stdout: String

  var succeeded: Bool { exitCode == 0 }

  /// Exit code we report when a command is killed for exceeding its timeout —
  /// mirrors GNU `timeout`, which the old shell script relied on.
  static let timedOutExitCode: Int32 = 124
}

/// Runs an external executable. Abstracted behind a protocol so `BlueutilClient`
/// can be driven by a fake in tests — no real Bluetooth hardware required.
protocol CommandRunner: Sendable {
  func run(_ executable: String, arguments: [String]) -> CommandResult
}

/// A mutable holder filled from a background reader thread. Guarded by the
/// process's own synchronization (we only read it after the reader signals).
private final class DataBox: @unchecked Sendable {
  private let lock = NSLock()
  private var value = Data()
  func set(_ data: Data) { lock.lock(); value = data; lock.unlock() }
  func get() -> Data { lock.lock(); defer { lock.unlock() }; return value }
}

/// The production runner: launches the executable as a subprocess, captures its
/// stdout, and enforces a hard timeout.
///
/// The timeout is essential: re-pairing a device that's stuck on another host
/// can make `blueutil` block forever, and without a ceiling the operation's
/// Task never returns and the device's toggle would spin permanently. Both
/// pipes are drained on background threads so a chatty child can't deadlock
/// against a full pipe buffer while we wait.
struct ProcessCommandRunner: CommandRunner {
  let timeout: TimeInterval

  init(timeout: TimeInterval = 25) {
    self.timeout = timeout
  }

  func run(_ executable: String, arguments: [String]) -> CommandResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments

    let outPipe = Pipe()
    let errPipe = Pipe()
    process.standardOutput = outPipe
    process.standardError = errPipe

    let exited = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in exited.signal() }

    do {
      try process.run()
    } catch {
      return CommandResult(exitCode: 127, stdout: "")
    }

    let (outData, outDone) = drain(outPipe)
    let (_, errDone) = drain(errPipe)  // drained to avoid a full-buffer deadlock

    if exited.wait(timeout: .now() + timeout) == .timedOut {
      process.terminate()
      if exited.wait(timeout: .now() + 2) == .timedOut {
        kill(process.processIdentifier, SIGKILL)
        exited.wait()
      }
      outDone.wait(); errDone.wait()
      return CommandResult(exitCode: CommandResult.timedOutExitCode, stdout: "")
    }

    outDone.wait(); errDone.wait()
    let stdout = String(data: outData.get(), encoding: .utf8) ?? ""
    return CommandResult(exitCode: process.terminationStatus, stdout: stdout)
  }

  /// Read a pipe to EOF on a background thread, signalling when finished.
  private func drain(_ pipe: Pipe) -> (DataBox, DispatchSemaphore) {
    let box = DataBox()
    let done = DispatchSemaphore(value: 0)
    DispatchQueue.global().async {
      box.set(pipe.fileHandleForReading.readDataToEndOfFile())
      done.signal()
    }
    return (box, done)
  }
}
