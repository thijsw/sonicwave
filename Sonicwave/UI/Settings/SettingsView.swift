import SwiftUI

/// Native Settings (Preferences) window: server connection, authentication,
/// and transcoding. See docs/02-opensubsonic-api.md and docs/04-ui-ux.md.
struct SettingsView: View {
    var body: some View {
        TabView {
            ConnectionSettingsView()
                .tabItem { Label("Connection", systemImage: "network") }
            PlaybackSettingsView()
                .tabItem { Label("Playback", systemImage: "play.circle") }
        }
        .frame(width: 480)
    }
}

private struct ConnectionSettingsView: View {
    @Environment(ConnectionModel.self) private var connection

    var body: some View {
        @Bindable var connection = connection
        Form {
            Section("Server") {
                TextField("Server Address", text: $connection.serverAddress,
                          prompt: Text("https://music.example.com"))
                    .textContentType(.URL)
            }

            Section("Authentication") {
                Picker("Method", selection: $connection.authMethod) {
                    Text("Password (token)").tag(ServerCredentials.AuthMethod.tokenSalt)
                    Text("API Key").tag(ServerCredentials.AuthMethod.apiKey)
                }
                TextField("Username", text: $connection.username)
                SecureField(connection.authMethod == .apiKey ? "API Key" : "Password",
                            text: $connection.secret)
            }

            Section {
                HStack {
                    Button("Test Connection") {
                        Task { await connection.testConnection() }
                    }
                    Button("Save & Connect") {
                        Task { await connection.saveAndConnect() }
                    }
                    .buttonStyle(.borderedProminent)
                    Spacer()
                    if connection.isConfigured {
                        Button("Disconnect", role: .destructive) { connection.disconnect() }
                    }
                }
                statusRow
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    @ViewBuilder
    private var statusRow: some View {
        switch connection.state {
        case .unconfigured:
            EmptyView()
        case .connecting:
            HStack { ProgressView().controlSize(.small); Text("Connecting…") }
        case let .connected(info):
            Label("Connected to \(info.type ?? "server") \(info.serverVersion ?? "")",
                  systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }
}

private struct PlaybackSettingsView: View {
    @Environment(ConnectionModel.self) private var connection
    @Environment(AppModel.self) private var app
    @State private var devices: [AudioDevice] = []
    @AppStorage("outputDeviceUID") private var outputDeviceUID = ""

    var body: some View {
        @Bindable var connection = connection
        Form {
            Section("Output") {
                Picker("Output Device", selection: $outputDeviceUID) {
                    Text("System Default").tag("")
                    ForEach(devices) { device in
                        Text(device.name).tag(device.uid)
                    }
                }
                .onChange(of: outputDeviceUID) {
                    let uid = outputDeviceUID.isEmpty ? nil : outputDeviceUID
                    Task { await app.playback.setOutputDevice(uid: uid) }
                }
            }
            Section("Streaming") {
                Toggle("Transcode on the server", isOn: $connection.transcodeEnabled)
                    .onChange(of: connection.transcodeEnabled) { connection.persistTranscodePrefs() }
                if connection.transcodeEnabled {
                    Picker("Format", selection: $connection.transcodeFormat) {
                        Text("MP3").tag("mp3")
                        Text("Opus").tag("opus")
                        Text("AAC").tag("aac")
                    }
                    .onChange(of: connection.transcodeFormat) { connection.persistTranscodePrefs() }
                    Picker("Max Bitrate", selection: $connection.transcodeMaxBitRate) {
                        Text("128 kbps").tag(128)
                        Text("192 kbps").tag(192)
                        Text("256 kbps").tag(256)
                        Text("320 kbps").tag(320)
                    }
                    .onChange(of: connection.transcodeMaxBitRate) { connection.persistTranscodePrefs() }
                } else {
                    Text("Streaming original files.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .task { devices = AudioOutputDevices.all() }
    }
}
