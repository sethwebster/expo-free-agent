import SwiftUI
import WorkerCore
import DiagnosticsCore

struct PreferencesView: View {
    @State private var configuration: WorkerConfiguration
    let onSave: (WorkerConfiguration) -> Void
    @Binding var downloadProgress: DownloadProgress?

    @State private var showingSaveConfirmation = false
    @State private var selectedTab: Tab = .controller

    enum Tab: String, CaseIterable, Identifiable {
        case controller = "Controller"
        case resources = "Resources"
        case vm = "VM Settings"
        case worker = "Worker"

        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .controller: return "link"
            case .resources: return "cpu"
            case .vm: return "shippingbox"
            case .worker: return "gearshape"
            }
        }
        
        var color: Color {
            switch self {
            case .controller: return .blue
            case .resources: return .purple
            case .vm: return .orange
            case .worker: return .gray
            }
        }
    }

    init(
        configuration: WorkerConfiguration,
        downloadProgress: Binding<DownloadProgress?>,
        onSave: @escaping (WorkerConfiguration) -> Void
    ) {
        _configuration = State(initialValue: configuration)
        _downloadProgress = downloadProgress
        self.onSave = onSave
    }

    var body: some View {
        NavigationSplitView {
            List(Tab.allCases, id: \.self, selection: $selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
            }
            .listStyle(.sidebar)
            .navigationTitle("Preferences")
        } detail: {
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            headerView
                 
                            // VM Template Download Progress
                            if let progress = downloadProgress, progress.status != .idle && progress.status != .complete {
                                downloadProgressView(progress)
                                    .transition(.move(edge: .top).combined(with: .opacity))
                            }

                            switch selectedTab {
                            case .controller:
                                controllerSection
                            case .resources:
                                resourcesSection
                            case .vm:
                                vmSection
                            case .worker:
                                workerSection
                            }
                        }
                        .padding(24)
                    }

                    Divider()

                    footerView
                }
            }
        }
        .frame(minWidth: 750, minHeight: 550)
        .animation(.spring(), value: selectedTab)
    }

    private var headerView: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selectedTab.color.gradient)
                    .frame(width: 48, height: 48)
                
                Image(systemName: selectedTab.icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(selectedTab.rawValue)
                    .font(.title2)
                    .fontWeight(.bold)
                Text(descriptionForTab(selectedTab))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.bottom, 8)
    }

    private func descriptionForTab(_ tab: Tab) -> String {
        switch tab {
        case .controller: return "Connection and authentication settings"
        case .resources: return "Hardware limits for build processes"
        case .vm: return "Virtual machine lifecycle and disk settings"
        case .worker: return "General worker behavior and timeouts"
        }
    }

    private func downloadProgressView(_ progress: DownloadProgress) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: progress.status == .failed ? "exclamationmark.triangle.fill" : "arrow.down.circle.fill")
                    .foregroundColor(progress.status == .failed ? .red : .orange)
                    .font(.title3)
                
                Text(progress.status == .failed ? "Initialization Failed" : "Installing Requirements")
                    .font(.headline)
                
                Spacer()
                
                if let percent = progress.percentComplete {
                    Text("\(Int(percent))%")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                }
            }
            
            Text(progress.message)
                .font(.caption)
                .foregroundColor(.secondary)
            
            if let percent = progress.percentComplete {
                ProgressView(value: percent, total: 100.0)
                    .progressViewStyle(.linear)
                    .tint(.orange)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(progress.status == .failed ? Color.red.opacity(0.05) : Color.orange.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(progress.status == .failed ? Color.red.opacity(0.2) : Color.orange.opacity(0.2), lineWidth: 1)
        )
    }

    private var controllerSection: some View {
        PremiumSectionCard(title: "Connection Details", icon: "network", color: .blue) {
            PremiumTextField(label: "Controller URL", text: $configuration.controllerURL, placeholder: "https://...")
            PremiumTextField(label: "API Key", text: $configuration.apiKey, placeholder: "Your secret key", isSecure: true)
            
            HStack(alignment: .bottom) {
                PremiumTextField(label: "Poll Interval", text: Binding(
                    get: { String(configuration.pollIntervalSeconds) },
                    set: { configuration.pollIntervalSeconds = Int($0) ?? 30 }
                ), placeholder: "30")
                .frame(width: 80)
                
                Text("seconds")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 8)
                
                Spacer()
            }
        }
    }

    private var resourcesSection: some View {
        PremiumSectionCard(title: "Hardware Limits", icon: "cpu", color: .purple) {
            PremiumSlider(label: "Max CPU Usage", value: $configuration.maxCPUPercent, range: 10...100, step: 10, unit: "%", icon: "cpu")
            Divider().padding(.vertical, 4)
            PremiumSlider(label: "Max Memory", value: $configuration.maxMemoryGB, range: 2...16, step: 2, unit: " GB", icon: "memorychip")
            Divider().padding(.vertical, 4)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Concurrent Builds")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                HStack {
                    Image(systemName: "square.3.layers.3d")
                        .foregroundColor(.secondary)
                    Stepper(value: $configuration.maxConcurrentBuilds, in: 1...4) {
                        Text("\(configuration.maxConcurrentBuilds) Parallel Builds")
                            .fontWeight(.medium)
                    }
                }
            }
        }
    }

    private var vmSection: some View {
        PremiumSectionCard(title: "Storage & Lifecycle", icon: "shippingbox", color: .orange) {
            PremiumSlider(label: "VM Disk Size", value: $configuration.vmDiskSizeGB, range: 30...100, step: 10, unit: " GB", icon: "internaldrive")
            
            Divider().padding(.vertical, 8)
            
            PremiumToggle(label: "Reuse VMs", isOn: $configuration.reuseVMs, description: "Faster builds by keeping VM state")
            PremiumToggle(label: "Cleanup after build", isOn: $configuration.cleanupAfterBuild, description: "Free up disk space immediately")
        }
    }

    private var workerSection: some View {
        PremiumSectionCard(title: "Worker Behavior", icon: "bolt.fill", color: .yellow) {
            PremiumToggle(label: "Auto-start on launch", isOn: $configuration.autoStart)
            PremiumToggle(label: "Only run when system is idle", isOn: $configuration.onlyWhenIdle, description: "Pause work if user is active")
            
            Divider().padding(.vertical, 8)
            
            HStack(alignment: .bottom) {
                PremiumTextField(label: "Build Timeout", text: Binding(
                    get: { String(configuration.buildTimeoutMinutes) },
                    set: { configuration.buildTimeoutMinutes = Int($0) ?? 120 }
                ), placeholder: "120")
                .frame(width: 80)
                
                Text("minutes")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 8)
                
                Spacer()
            }
        }
    }

    private var footerView: some View {
        HStack(spacing: 16) {
            if showingSaveConfirmation {
                Label("Saved", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.subheadline)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }

            Spacer()
            
            Button("Reset to Defaults") {
                configuration = WorkerConfiguration.default
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .font(.subheadline)

            Button("Cancel") {
                NSApp.keyWindow?.close()
            }
            .keyboardShortcut(.cancelAction)
            .controlSize(.large)

            Button("Save Changes") {
                save()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .tint(selectedTab.color)
        }
        .padding(16)
        .background(.ultraThinMaterial)
    }

    private func save() {
        onSave(configuration)
        withAnimation {
            showingSaveConfirmation = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                showingSaveConfirmation = false
            }
            NSApp.keyWindow?.close()
        }
    }
}

#Preview {
    PreferencesView(
        configuration: .default,
        downloadProgress: .constant(nil),
        onSave: { _ in }
    )
}
