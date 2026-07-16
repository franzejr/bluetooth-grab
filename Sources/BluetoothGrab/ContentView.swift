import SwiftUI

/// The main window: one row per paired device with a grab/release toggle.
struct ContentView: View {
  @StateObject private var model = DeviceListViewModel()

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Divider()

      if model.blueutilMissing {
        missingBlueutil
      } else if model.devices.isEmpty {
        emptyState
      } else {
        deviceList
      }

      Divider()
      statusBar
    }
    .frame(width: 380, height: 440)
    .onAppear { model.start() }
    .onDisappear { model.stop() }
    .confirmationDialog(
      "Release this device?",
      isPresented: releaseConfirmationBinding,
      titleVisibility: .visible
    ) {
      Button("Release", role: .destructive) { model.confirmRelease() }
      Button("Cancel", role: .cancel) { model.cancelRelease() }
    } message: {
      Text("\(model.pendingRelease?.displayName ?? "This device") looks like the one you're using. Releasing it disconnects it from this Mac.")
    }
    .confirmationDialog(
      "Reset pairing?",
      isPresented: resetConfirmationBinding,
      titleVisibility: .visible
    ) {
      Button("Reset pairing", role: .destructive) { model.confirmReset() }
      Button("Cancel", role: .cancel) { model.cancelReset() }
    } message: {
      Text("This removes \(model.pendingReset?.displayName ?? "the device")'s pairing from this Mac and re-pairs it. Use it only when a normal grab won't connect. The device must be in pairing mode — flick its power switch off/on first.")
    }
  }

  private var header: some View {
    HStack {
      Label("Bluetooth Grab", systemImage: "dot.radiowaves.left.and.right")
        .font(.headline)
      Spacer()
      Button {
        Task { await model.refresh() }
      } label: {
        Image(systemName: "arrow.clockwise")
      }
      .buttonStyle(.borderless)
      .help("Refresh")
    }
    .padding(12)
  }

  private var deviceList: some View {
    ScrollView {
      VStack(spacing: 0) {
        ForEach(model.devices) { device in
          DeviceRow(model: model, device: device)
          Divider()
        }
      }
    }
  }

  private var emptyState: some View {
    centered("No paired Bluetooth devices.\nPair a device in System Settings first.")
  }

  private var missingBlueutil: some View {
    centered("blueutil isn't installed.\n\nInstall it with:\nbrew install blueutil")
  }

  private func centered(_ text: String) -> some View {
    Text(text)
      .multilineTextAlignment(.center)
      .foregroundStyle(.secondary)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .padding()
  }

  private var statusBar: some View {
    Text(model.status ?? "Toggle a device on to grab it onto this Mac.")
      .font(.callout)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(12)
  }

  /// The confirmation dialog is shown iff a release is pending. Dismissing via
  /// the escape key routes through `cancelRelease`.
  private var releaseConfirmationBinding: Binding<Bool> {
    Binding(
      get: { model.pendingRelease != nil },
      set: { if !$0 { model.cancelRelease() } }
    )
  }

  private var resetConfirmationBinding: Binding<Bool> {
    Binding(
      get: { model.pendingReset != nil },
      set: { if !$0 { model.cancelReset() } }
    )
  }
}

/// A single device row: name, address, and its toggle (or a spinner when busy).
/// Holds the view model so its toggle binding stays on the main actor without a
/// cross-actor closure hop.
struct DeviceRow: View {
  @ObservedObject var model: DeviceListViewModel
  let device: BluetoothDevice

  var body: some View {
    let isBusy = model.isBusy(device)
    HStack {
      VStack(alignment: .leading, spacing: 2) {
        Text(device.displayName)
        Text(device.address)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      if isBusy {
        ProgressView().controlSize(.small)
      }
      Menu {
        Button("Reset pairing…") { model.requestReset(device) }
      } label: {
        Image(systemName: "ellipsis.circle")
      }
      .menuStyle(.borderlessButton)
      .menuIndicator(.hidden)
      .fixedSize()
      .disabled(isBusy)
      .help("More actions")
      Toggle("", isOn: Binding(
        get: { model.isOn(device) },
        set: { model.setConnected(device, to: $0) }
      ))
      .labelsHidden()
      .toggleStyle(.switch)
      .disabled(isBusy)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
  }
}
