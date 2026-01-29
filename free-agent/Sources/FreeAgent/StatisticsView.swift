import SwiftUI
import WorkerCore

struct WorkerStats: Codable {
    let totalBuilds: Int
    let successfulBuilds: Int
    let failedBuilds: Int
    let workerName: String
    let status: String
    let uptime: String?
}

struct StatisticsView: View {
    let configuration: WorkerConfiguration
    @State private var stats: WorkerStats?
    @State private var isLoading = true
    @State private var error: String?
    @State private var lastUpdated: Date?
    @State private var currentTime = Date()
    @State private var startTime: Date?

    let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()
    let clockTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        headerView
                        
                        if isLoading {
                            loadingView
                        } else if let error = error {
                            errorView(error)
                        } else if let stats = stats {
                            statsContent(stats)
                        }
                    }
                    .padding(24)
                }
                
                footerView
            }
        }
        .frame(width: 500, height: 650)
        .onAppear {
            Task {
                await loadStatistics()
            }
        }
        .onReceive(timer) { _ in
            Task {
                await refreshStatistics()
            }
        }
        .onReceive(clockTimer) { time in
            currentTime = time
        }
    }

    private var headerView: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.blue.gradient)
                    .frame(width: 48, height: 48)
                
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Worker Statistics")
                    .font(.title2)
                    .fontWeight(.bold)
                
                if let lastUpdated = lastUpdated {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text("Live • Updated \(timeAgo(from: lastUpdated))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("Fetching latest data...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(.bottom, 8)
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Analyzing performance...")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 400)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            
            VStack(spacing: 8) {
                Text("Connection Issue")
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button("Retry Connection") {
                Task { await loadStatistics() }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, minHeight: 400)
        .padding()
    }

    private func statsContent(_ stats: WorkerStats) -> some View {
        VStack(spacing: 20) {
            PremiumSectionCard(title: "Worker Identity", icon: "desktopcomputer", color: .blue) {
                StatRow(label: "Name", value: stats.workerName)
                StatRow(
                    label: "Current Status",
                    value: stats.status.capitalized,
                    valueColor: statusColor(for: stats.status)
                )
                StatRow(label: "Uptime", value: liveUptime())
            }

            PremiumSectionCard(title: "Build Performance", icon: "hammer.fill", color: .purple) {
                StatRow(label: "Total Builds", value: "\(stats.totalBuilds)")
                StatRow(label: "Successful", value: "\(stats.successfulBuilds)", valueColor: .green)
                StatRow(label: "Failed", value: "\(stats.failedBuilds)", valueColor: stats.failedBuilds > 0 ? .red : .secondary)
                
                if stats.totalBuilds > 0 {
                    Divider().padding(.vertical, 8)
                    let successRate = Double(stats.successfulBuilds) / Double(stats.totalBuilds) * 100
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Success Rate")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(String(format: "%.1f%%", successRate))
                                .font(.headline.monospacedDigit())
                        }
                        
                        ProgressView(value: successRate, total: 100)
                            .tint(successRate > 90 ? .green : (successRate > 70 ? .blue : .orange))
                    }
                }
            }

            PremiumSectionCard(title: "Active Configuration", icon: "gearshape.fill", color: .gray) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Controller Endpoint")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    Text(configuration.controllerURL)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.primary)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.03))
                        .cornerRadius(6)
                }
                
                Divider().padding(.vertical, 8)
                
                StatRow(label: "Parallel Build Slots", value: "\(configuration.maxConcurrentBuilds)")
                StatRow(label: "Auto-start", value: configuration.autoStart ? "Enabled" : "Disabled")
            }
        }
    }

    private var footerView: some View {
        HStack {
            Spacer()
            Button("Dismiss") {
                NSApp.keyWindow?.close()
            }
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(16)
        .background(.ultraThinMaterial)
    }

    private func loadStatistics() async {
        isLoading = true
        error = nil

        do {
            guard let workerId = configuration.workerID else {
                throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Worker not registered"])
            }

            let url = URL(string: "\(configuration.controllerURL)/api/workers/\(workerId)/stats")!
            var request = URLRequest(url: url)
            request.setValue(configuration.apiKey, forHTTPHeaderField: "X-API-Key")
            request.timeoutInterval = 10.0

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
            }

            if httpResponse.statusCode == 404 {
                stats = WorkerStats(
                    totalBuilds: 0,
                    successfulBuilds: 0,
                    failedBuilds: 0,
                    workerName: configuration.deviceName ?? "Unknown",
                    status: "unknown",
                    uptime: nil
                )
            } else if httpResponse.statusCode == 200 {
                let newStats = try JSONDecoder().decode(WorkerStats.self, from: data)
                stats = newStats

                if let uptime = newStats.uptime, let elapsed = parseUptime(uptime) {
                    startTime = Date().addingTimeInterval(-elapsed)
                }
            } else {
                throw NSError(domain: "", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"])
            }

            lastUpdated = Date()
            isLoading = false
        } catch {
            self.error = error.localizedDescription
            isLoading = false
        }
    }

    private func refreshStatistics() async {
        do {
            guard let workerId = configuration.workerID else { return }

            let url = URL(string: "\(configuration.controllerURL)/api/workers/\(workerId)/stats")!
            var request = URLRequest(url: url)
            request.setValue(configuration.apiKey, forHTTPHeaderField: "X-API-Key")
            request.timeoutInterval = 10.0

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return }

            let newStats = try JSONDecoder().decode(WorkerStats.self, from: data)
            stats = newStats

            if let uptime = newStats.uptime, let elapsed = parseUptime(uptime) {
                startTime = Date().addingTimeInterval(-elapsed)
            }

            lastUpdated = Date()
            error = nil
        } catch {}
    }

    private func timeAgo(from date: Date) -> String {
        let seconds = Int(currentTime.timeIntervalSince(date))
        if seconds < 5 { return "just now" }
        if seconds < 60 { return "\(seconds)s ago" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        return "\(seconds / 3600)h ago"
    }

    private func parseUptime(_ uptime: String) -> TimeInterval? {
        let components = uptime.split(separator: " ")
        var totalSeconds: TimeInterval = 0
        for component in components {
            let str = String(component)
            if str.hasSuffix("d") { totalSeconds += (Double(str.dropLast()) ?? 0) * 86400 }
            else if str.hasSuffix("h") { totalSeconds += (Double(str.dropLast()) ?? 0) * 3600 }
            else if str.hasSuffix("m") { totalSeconds += (Double(str.dropLast()) ?? 0) * 60 }
            else if str.hasSuffix("s") { totalSeconds += (Double(str.dropLast()) ?? 0) }
        }
        return totalSeconds > 0 ? totalSeconds : nil
    }

    private func liveUptime() -> String {
        guard let start = startTime else { return stats?.uptime ?? "—" }
        let elapsed = currentTime.timeIntervalSince(start)
        return formatDuration(elapsed)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        let days = s / 86400
        let hours = (s % 86400) / 3600
        let minutes = (s % 3600) / 60
        let secs = s % 60
        if days > 0 { return String(format: "%dd %dh %dm", days, hours, minutes) }
        if hours > 0 { return String(format: "%dh %dm %ds", hours, minutes, secs) }
        if minutes > 0 { return String(format: "%dm %ds", minutes, secs) }
        return String(format: "%ds", secs)
    }

    private func statusColor(for status: String) -> Color {
        switch status.lowercased() {
        case "idle": return .green
        case "building": return .blue
        case "offline": return .red
        default: return .secondary
        }
    }
}

private struct StatRow: View {
    let label: String
    let value: String
    var valueColor: Color = .primary

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.monospacedDigit())
                .fontWeight(.semibold)
                .foregroundColor(valueColor)
        }
    }
}

#Preview {
    StatisticsView(configuration: .default)
}
