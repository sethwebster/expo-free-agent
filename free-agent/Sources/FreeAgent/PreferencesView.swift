import SwiftUI
import WorkerCore
import DiagnosticsCore

struct PreferencesView: View {
    @State private var configuration: WorkerConfiguration
    @State private var initialConfiguration: WorkerConfiguration
    let onSave: (WorkerConfiguration) -> Void
    @Binding var downloadProgress: DownloadProgress?

    @State private var showingSaveConfirmation = false
    @State private var selectedTab: Tab = .statistics

    private var hasChanges: Bool {
        configuration != initialConfiguration
    }

    enum Tab: String, CaseIterable, Identifiable {
        case statistics = "Statistics"
        case controller = "Controller"
        case resources = "Resources"
        case vm = "VM Settings"
        case worker = "Worker"

        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .statistics: return "chart.bar.fill"
            case .controller: return "link"
            case .resources: return "cpu"
            case .vm: return "shippingbox"
            case .worker: return "gearshape"
            }
        }
        
        var color: Color {
            switch self {
            case .statistics: return .blue
            case .controller: return .cyan
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
        _initialConfiguration = State(initialValue: configuration)
        _downloadProgress = downloadProgress
        self.onSave = onSave
    }

    @State private var connectionStatus: ConnectionStatus = .idle

    enum ConnectionStatus: Equatable {
        case idle
        case checking
        case success
        case failed(String)
    }

    var body: some View {
        NavigationSplitView {
            ZStack {
                VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
                    .ignoresSafeArea()
                
                List(Tab.allCases, selection: $selectedTab) { tab in
                    HStack(spacing: 12) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 20)
                            .foregroundColor(selectedTab == tab ? .primary : tab.color.opacity(0.8))
                        
                        Text(tab.rawValue)
                            .font(.system(size: 13, weight: .medium))
                    }
                    .padding(.vertical, 4)
                    .tag(tab)
                }
                .listStyle(.sidebar)
            }
            .navigationTitle("Preferences")
        } detail: {
            ZStack {
                // Main Window Glass
                VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 32) {
                            headerView
                 
                            if let progress = downloadProgress, progress.status != .idle && progress.status != .complete {
                                downloadProgressView(progress)
                                    .transition(.move(edge: .top).combined(with: .opacity))
                            }

                            switch selectedTab {
                            case .statistics:
                                StatisticsView(configuration: configuration)
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
                        .padding(40)
                    }

                    footerView
                }
            }
        }
        .frame(minWidth: 800, minHeight: 600)
    }

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                Image(systemName: selectedTab.icon)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(selectedTab.color)

                Text(selectedTab.rawValue)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.primary)
            }

            Text(descriptionForTab(selectedTab))
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .padding(.bottom, 12)
    }

    private func descriptionForTab(_ tab: Tab) -> String {
        switch tab {
        case .statistics: return "Real-time worker performance and build history"
        case .controller: return "Connection and authentication settings"
        case .resources: return "Hardware limits for build processes"
        case .vm: return "Virtual machine lifecycle and disk settings"
        case .worker: return "General worker behavior and timeouts"
        }
    }

    private func downloadProgressView(_ progress: DownloadProgress) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: progress.status == .failed ? "exclamationmark.triangle.fill" : "arrow.down.circle.fill")
                    .foregroundColor(progress.status == .failed ? .red : .orange)
                
                Text(progress.status == .failed ? "Initialization Failed" : "Installing Requirements")
                    .font(.system(size: 14, weight: .bold))
                
                Spacer()
                
                if let percent = progress.percentComplete {
                    Text("\(Int(percent))%")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                }
            }
            
            Text(progress.message)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            
            if let percent = progress.percentComplete {
                ProgressView(value: percent, total: 100.0)
                    .progressViewStyle(.linear)
                    .tint(.orange)
            }
        }
        .padding(20)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .withinWindow).clipShape(RoundedRectangle(cornerRadius: 12)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.3), lineWidth: 1))
    }

    private var controllerSection: some View {
        PremiumSectionCard(title: "Connection Details", icon: "network", color: .cyan) {
            PremiumTextField(label: "Controller URL", text: $configuration.controllerURL, placeholder: "https://...") {
                testConnectionButton
            }

            HStack(alignment: .bottom, spacing: 12) {
                PremiumTextField(label: "Poll Interval", text: Binding(
                    get: { String(configuration.pollIntervalSeconds) },
                    set: { configuration.pollIntervalSeconds = Int($0) ?? 30 }
                ), placeholder: "30")
                .frame(width: 80)
                
                Text("seconds")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .padding(.bottom, 10)
                
                Spacer()
            }
        }
    }

    private var testConnectionButton: some View {
        Button(action: testConnection) {
            HStack(spacing: 6) {
                switch connectionStatus {
                case .idle:
                    Text("Test")
                        .font(.system(size: 11, weight: .bold))
                case .checking:
                    ProgressView()
                        .controlSize(.mini)
                case .success:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                case .failed:
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.red)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.1))
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .disabled(connectionStatus == .checking)
        .help(connectionStatusHelpText)
    }

    private var connectionStatusHelpText: String {
        switch connectionStatus {
        case .idle: return "Test connection to controller"
        case .checking: return "Checking..."
        case .success: return "Connection successful"
        case .failed(let error): return "Connection failed: \(error)"
        }
    }

    private func testConnection() {
        Task {
            await MainActor.run { connectionStatus = .checking }
            
            guard let url = URL(string: configuration.controllerURL) else {
                await MainActor.run { connectionStatus = .failed("Invalid URL") }
                return
            }
            
            var request = URLRequest(url: url.appendingPathComponent("api/health"))
            request.timeoutInterval = 5.0
            
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) {
                    await MainActor.run { connectionStatus = .success }
                } else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                    await MainActor.run { connectionStatus = .failed("HTTP \(code)") }
                }
            } catch {
                await MainActor.run { connectionStatus = .failed(error.localizedDescription) }
            }
            
            // Reset to idle after 3 seconds if not idle
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run { 
                if case .success = connectionStatus { 
                    connectionStatus = .idle 
                } else if case .failed = connectionStatus {
                    connectionStatus = .idle
                }
            }
        }
    }

    private var resourcesSection: some View {
        PremiumSectionCard(title: "Hardware Limits", icon: "cpu", color: .purple) {
            PremiumSlider(label: "Max CPU Usage", value: $configuration.maxCPUPercent, range: 10...100, step: 10, unit: "%", icon: "cpu")
            Divider().opacity(0.1).padding(.vertical, 4)
            PremiumSlider(label: "Max Memory", value: $configuration.maxMemoryGB, range: 2...16, step: 2, unit: " GB", icon: "memorychip")
            Divider().opacity(0.1).padding(.vertical, 4)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Concurrent Builds")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)

                HStack {
                    Image(systemName: "square.3.layers.3d")
                        .foregroundColor(.purple)

                    Stepper(value: $configuration.maxConcurrentBuilds, in: 1...4) {
                        Text("\(configuration.maxConcurrentBuilds) Parallel Builds")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.primary)
                    }
                }
                .padding(12)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(10)
            }
        }
    }

    private var vmSection: some View {
        PremiumSectionCard(title: "Storage & Lifecycle", icon: "shippingbox", color: .orange) {
            PremiumSlider(label: "VM Disk Size", value: $configuration.vmDiskSizeGB, range: 30...100, step: 10, unit: " GB", icon: "internaldrive")
            
            Divider().opacity(0.1).padding(.vertical, 8)
            
            VStack(spacing: 16) {
                PremiumToggle(label: "Reuse VMs", isOn: $configuration.reuseVMs, description: "Keep VM state between builds")
                PremiumToggle(label: "Cleanup after build", isOn: $configuration.cleanupAfterBuild, description: "Delete VM immediately after task")
            }
        }
    }

    private var workerSection: some View {
        PremiumSectionCard(title: "Worker Behavior", icon: "bolt.fill", color: .yellow) {
            VStack(spacing: 16) {
                PremiumToggle(label: "Auto-start on launch", isOn: $configuration.autoStart)
                PremiumToggle(label: "Only run when system is idle", isOn: $configuration.onlyWhenIdle, description: "Pause if user activity is detected")
            }
            
            Divider().opacity(0.1).padding(.vertical, 8)
            
            HStack(alignment: .bottom, spacing: 12) {
                PremiumTextField(label: "Build Timeout", text: Binding(
                    get: { String(configuration.buildTimeoutMinutes) },
                    set: { configuration.buildTimeoutMinutes = Int($0) ?? 120 }
                ), placeholder: "120")
                .frame(width: 80)
                
                Text("minutes")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .padding(.bottom, 10)
                
                Spacer()
            }
        }
    }

    private var footerView: some View {
        HStack(spacing: 16) {
            if selectedTab == .statistics {
                Spacer()
                Button("Close") {
                    NSApp.keyWindow?.close()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.blue.gradient)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .foregroundColor(.white)
                .fontWeight(.bold)
            } else {
                if showingSaveConfirmation {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Settings Saved")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .transition(.scale.combined(with: .opacity))
                }

                Spacer()
                
                if hasChanges {
                    Button("Reset to Defaults") {
                        withAnimation(.spring()) {
                            configuration = WorkerConfiguration.default
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))

                    Button("Cancel") {
                        NSApp.keyWindow?.close()
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(VisualEffectView(material: .hudWindow, blendingMode: .withinWindow).clipShape(RoundedRectangle(cornerRadius: 8)))
                    .keyboardShortcut(.cancelAction)

                    Button("Save Changes") {
                        save()
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(selectedTab.color.gradient)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .foregroundColor(.white)
                    .fontWeight(.bold)
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("Close") {
                        NSApp.keyWindow?.close()
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(VisualEffectView(material: .hudWindow, blendingMode: .withinWindow).clipShape(RoundedRectangle(cornerRadius: 10)))
                    .foregroundColor(.white)
                    .fontWeight(.bold)
                }
            }
        }
        .padding(32)
        .background(VisualEffectView(material: .headerView, blendingMode: .withinWindow))
    }

    private func save() {
        onSave(configuration)
        withAnimation(.spring()) {
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
