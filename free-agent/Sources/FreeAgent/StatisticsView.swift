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
        VStack(spacing: 0) {
            // Header with logo
            VStack(spacing: 16) {
                if let logoURL = Bundle.resources.url(forResource: "expo-free-agent-logo-white", withExtension: "png"),
                   let nsImage = NSImage(contentsOf: logoURL) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 80)
                } else {
                    Text("Free Agent")
                        .font(.system(size: 32, weight: .bold))
                }

                Text("Build Worker Statistics")
                    .font(.headline)
                    .foregroundColor(.secondary)

                if let lastUpdated = lastUpdated {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text("Live • Updated \(timeAgo(from: lastUpdated))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.top, 32)
            .padding(.bottom, 24)

            Divider()

            // Statistics content
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Loading statistics...")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = error {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(.orange)
                    Text("Failed to load statistics")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let stats = stats {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Worker Info
                        GroupBox {
                            VStack(alignment: .leading, spacing: 8) {
                                StatRow(label: "Name", value: stats.workerName)
                                StatRow(
                                    label: "Status",
                                    value: stats.status.capitalized,
                                    valueColor: statusColor(for: stats.status)
                                )
                                StatRow(label: "Uptime", value: liveUptime())
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                        } label: {
                            Label("Worker Information", systemImage: "desktopcomputer")
                                .font(.system(size: 14, weight: .semibold))
                        }

                        // Build Statistics
                        GroupBox {
                            VStack(alignment: .leading, spacing: 8) {
                                StatRow(label: "Total Builds", value: "\(stats.totalBuilds)")
                                StatRow(label: "Successful", value: "\(stats.successfulBuilds)", valueColor: .green)
                                StatRow(label: "Failed", value: "\(stats.failedBuilds)", valueColor: stats.failedBuilds > 0 ? .red : .secondary)

                                if stats.totalBuilds > 0 {
                                    Divider()
                                        .padding(.vertical, 4)
                                    let successRate = Double(stats.successfulBuilds) / Double(stats.totalBuilds) * 100
                                    StatRow(label: "Success Rate", value: String(format: "%.1f%%", successRate))
                                }
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                        } label: {
                            Label("Build Statistics", systemImage: "hammer")
                                .font(.system(size: 14, weight: .semibold))
                        }

                        // Configuration
                        GroupBox {
                            VStack(alignment: .leading, spacing: 8) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Controller URL")
                                        .font(.system(size: 13))
                                        .foregroundColor(.secondary)
                                    Text(configuration.controllerURL)
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundColor(.primary)
                                        .lineLimit(2)
                                }
                                .padding(.vertical, 2)

                                Divider()
                                    .padding(.vertical, 4)

                                StatRow(label: "Max Concurrent Builds", value: "\(configuration.maxConcurrentBuilds)")
                                StatRow(label: "Auto-start", value: configuration.autoStart ? "Enabled" : "Disabled")
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                        } label: {
                            Label("Configuration", systemImage: "gearshape")
                                .font(.system(size: 14, weight: .semibold))
                        }
                    }
                    .padding(24)
                }
            }
        }
        .frame(width: 500, height: 600)
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

    private func loadStatistics() async {
        isLoading = true
        error = nil

        do {
            // Fetch worker stats from controller
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
                // Endpoint doesn't exist yet - show placeholder data
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

                // Calculate start time from uptime
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
        // Silently refresh without showing loading state
        do {
            guard let workerId = configuration.workerID else {
                return
            }

            let url = URL(string: "\(configuration.controllerURL)/api/workers/\(workerId)/stats")!
            var request = URLRequest(url: url)
            request.setValue(configuration.apiKey, forHTTPHeaderField: "X-API-Key")
            request.timeoutInterval = 10.0

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return
            }

            let newStats = try JSONDecoder().decode(WorkerStats.self, from: data)
            stats = newStats

            // Recalculate start time from uptime
            if let uptime = newStats.uptime, let elapsed = parseUptime(uptime) {
                startTime = Date().addingTimeInterval(-elapsed)
            }

            lastUpdated = Date()
            error = nil
        } catch {
            // Silently fail - keep showing last known good stats
        }
    }

    private func timeAgo(from date: Date) -> String {
        let seconds = Int(currentTime.timeIntervalSince(date))
        if seconds < 5 {
            return "just now"
        } else if seconds < 60 {
            return "\(seconds)s ago"
        } else if seconds < 3600 {
            let minutes = seconds / 60
            return "\(minutes)m ago"
        } else {
            let hours = seconds / 3600
            return "\(hours)h ago"
        }
    }

    private func parseUptime(_ uptime: String) -> TimeInterval? {
        // Parse uptime strings like "1m 23s", "38s", "2h 15m"
        let components = uptime.split(separator: " ")
        var totalSeconds: TimeInterval = 0

        for component in components {
            let str = String(component)
            if str.hasSuffix("d") {
                let days = Double(str.dropLast()) ?? 0
                totalSeconds += days * 86400
            } else if str.hasSuffix("h") {
                let hours = Double(str.dropLast()) ?? 0
                totalSeconds += hours * 3600
            } else if str.hasSuffix("m") {
                let minutes = Double(str.dropLast()) ?? 0
                totalSeconds += minutes * 60
            } else if str.hasSuffix("s") {
                let seconds = Double(str.dropLast()) ?? 0
                totalSeconds += seconds
            }
        }

        return totalSeconds > 0 ? totalSeconds : nil
    }

    private func liveUptime() -> String {
        guard let start = startTime else {
            return stats?.uptime ?? "—"
        }

        let elapsed = currentTime.timeIntervalSince(start)
        return formatDuration(elapsed)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        let days = s / 86400
        let hours = (s % 86400) / 3600
        let minutes = (s % 3600) / 60
        let secs = s % 60

        if days > 0 {
            return String(format: "%dd %dh %dm", days, hours, minutes)
        } else if hours > 0 {
            return String(format: "%dh %dm %ds", hours, minutes, secs)
        } else if minutes > 0 {
            return String(format: "%dm %ds", minutes, secs)
        } else {
            return String(format: "%ds", secs)
        }
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

struct StatRow: View {
    let label: String
    let value: String
    var valueColor: Color = .primary

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(valueColor)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    StatisticsView(configuration: WorkerConfiguration.load())
}
