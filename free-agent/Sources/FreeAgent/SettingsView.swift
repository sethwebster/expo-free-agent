import SwiftUI
import WorkerCore
import DiagnosticsCore

struct SettingsView: View {
    @State private var configuration: WorkerConfiguration
    let onSave: (WorkerConfiguration) -> Void
    let onProgressUpdate: ((DownloadProgress) -> Void)?

    @State private var showingSaveConfirmation = false
    @State private var downloadProgress: DownloadProgress?
    @State private var isCheckingTemplate = false

    init(
        configuration: WorkerConfiguration,
        onSave: @escaping (WorkerConfiguration) -> Void,
        onProgressUpdate: ((DownloadProgress) -> Void)? = nil
    ) {
        _configuration = State(initialValue: configuration)
        self.onSave = onSave
        self.onProgressUpdate = onProgressUpdate
    }

    var body: some View {
        if let progress = downloadProgress {
            // Show download progress overlay
            TemplateDownloadView(progress: progress) {
                downloadProgress = nil
            }
        } else {
            settingsContent
        }
    }

    private var settingsContent: some View {
        content
            .onAppear {
                checkTemplateExists()
            }
    }

    private func checkTemplateExists() {
        guard !isCheckingTemplate else { return }
        isCheckingTemplate = true

        Task {
            let check = TemplateVMCheck(templateImage: "ghcr.io/sethwebster/expo-free-agent-base:0.1.23")

            // Set up progress handler
            await check.setProgressHandler { progress in
                Task { @MainActor in
                    downloadProgress = progress
                    onProgressUpdate?(progress)
                }
            }

            let result = await check.run()

            if result.status == .fail {
                // Template doesn't exist, trigger download
                do {
                    _ = try await check.autoFix()
                } catch {
                    Task { @MainActor in
                        downloadProgress = DownloadProgress(
                            status: .failed,
                            message: "Failed to download template: \(error.localizedDescription)"
                        )
                    }
                }
            }

            isCheckingTemplate = false
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Free Agent Settings")
                .font(.title)
                .padding(.bottom, 10)

            // Controller Configuration
            GroupBox(label: Text("Controller").fontWeight(.semibold)) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Controller URL:")
                            .frame(width: 120, alignment: .trailing)
                        TextField("https://expo-free-agent-controller.projects.sethwebster.com", text: $configuration.controllerURL)
                            .textFieldStyle(.roundedBorder)
                    }

                    HStack {
                        Text("API Key:")
                            .frame(width: 120, alignment: .trailing)
                        SecureField("Enter API key", text: $configuration.apiKey)
                            .textFieldStyle(.roundedBorder)
                    }

                    HStack {
                        Text("Poll Interval:")
                            .frame(width: 120, alignment: .trailing)
                        TextField("30", value: $configuration.pollIntervalSeconds, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        Text("seconds")
                    }
                }
                .padding()
            }

            // Resource Limits
            GroupBox(label: Text("Resource Limits").fontWeight(.semibold)) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Max CPU Usage:")
                            .frame(width: 120, alignment: .trailing)
                        Slider(value: $configuration.maxCPUPercent, in: 10...100, step: 10)
                        Text("\(Int(configuration.maxCPUPercent))%")
                            .frame(width: 40, alignment: .trailing)
                    }

                    HStack {
                        Text("Max Memory:")
                            .frame(width: 120, alignment: .trailing)
                        Slider(value: $configuration.maxMemoryGB, in: 2...16, step: 2)
                        Text("\(Int(configuration.maxMemoryGB)) GB")
                            .frame(width: 60, alignment: .trailing)
                    }

                    HStack {
                        Text("Concurrent Builds:")
                            .frame(width: 120, alignment: .trailing)
                        Stepper(value: $configuration.maxConcurrentBuilds, in: 1...4) {
                            Text("\(configuration.maxConcurrentBuilds)")
                                .frame(width: 30)
                        }
                    }
                }
                .padding()
            }

            // VM Configuration
            GroupBox(label: Text("VM Settings").fontWeight(.semibold)) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("VM Disk Size:")
                            .frame(width: 120, alignment: .trailing)
                        Slider(value: $configuration.vmDiskSizeGB, in: 30...100, step: 10)
                        Text("\(Int(configuration.vmDiskSizeGB)) GB")
                            .frame(width: 60, alignment: .trailing)
                    }

                    Toggle(isOn: $configuration.reuseVMs) {
                        Text("Reuse VMs between builds")
                    }
                    .padding(.leading, 120)

                    Toggle(isOn: $configuration.cleanupAfterBuild) {
                        Text("Cleanup VM after each build")
                    }
                    .padding(.leading, 120)
                }
                .padding()
            }

            // Worker Preferences
            GroupBox(label: Text("Worker Preferences").fontWeight(.semibold)) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: $configuration.autoStart) {
                        Text("Auto-start worker on launch")
                    }

                    Toggle(isOn: $configuration.onlyWhenIdle) {
                        Text("Only run when system is idle")
                    }

                    HStack {
                        Text("Build Timeout:")
                            .frame(width: 120, alignment: .trailing)
                        TextField("120", value: $configuration.buildTimeoutMinutes, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        Text("minutes")
                    }
                }
                .padding()
            }

            Spacer()

            // Action Buttons
            HStack {
                Button("Reset to Defaults") {
                    configuration = WorkerConfiguration.default
                }

                Spacer()

                Button("Cancel") {
                    NSApp.keyWindow?.close()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    onSave(configuration)
                    showingSaveConfirmation = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        showingSaveConfirmation = false
                        NSApp.keyWindow?.close()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 10)

            if showingSaveConfirmation {
                Text("✓ Settings saved successfully")
                    .foregroundColor(.green)
                    .font(.caption)
            }
        }
        .padding(20)
        .frame(width: 500, height: 600)
    }
}

#Preview {
    SettingsView(configuration: .default, onSave: { _ in })
}
