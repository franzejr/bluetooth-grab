import SwiftUI

@main
struct BluetoothGrabApp: App {
  var body: some Scene {
    WindowGroup("Bluetooth Grab") {
      ContentView()
    }
    .windowResizability(.contentSize)
    .commands {
      // A single-window utility; drop the New Window / tabbing noise.
      CommandGroup(replacing: .newItem) {}
    }
  }
}
