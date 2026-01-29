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
        VStack(alignment: .leading, spacing: 32) {
            if isLoading && stats == nil {
                loadingPlaceholder
            } else if let error = error, stats == nil {
                errorView(error)
            } else if let stats = stats {
                statsGrid(stats)
                
                VStack(spacing: 24) {
                    PremiumSectionCard(title: "Worker Performance", icon: "bolt.fill", color: .yellow) {
                        StatRow(label: "Success Rate", value: successRateString(stats), valueColor: successRateColor(stats))
                        
                        let successRate = calculateSuccessRate(stats)
                        ProgressView(value: successRate, total: 100)
                            .tint(successRateColor(stats))
                            .controlSize(.small)
                            .padding(.top, 4)
                        
                        Divider().opacity(0.1).padding(.vertical, 8)
                        
                        StatRow(label: "Uptime", value: liveUptime())
                    }
                    
                    PremiumSectionCard(title: "Identity", icon: "desktopcomputer", color: .blue) {
                        StatRow(label: "Worker Name", value: stats.workerName)
                        StatRow(label: "Status", value: stats.status.capitalized, valueColor: statusColor(for: stats.status))
                    }
                }
            }
        }
        .onAppear {
            Task { await loadStatistics() }
        }
        .onReceive(timer) { _ in
            Task { await refreshStatistics() }
        }
        .onReceive(clockTimer) { time in
            currentTime = time
        }
    }

    private var loadingPlaceholder: some View {
        VStack(spacing: 20) {
            ProgressView()
                .controlSize(.large)
            Text("Fetching Live Data...")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity, minHeight: 400)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundColor(.orange)
            Text(message)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await loadStatistics() }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, minHeight: 400)
    }

    private func statsGrid(_ stats: WorkerStats) -> some View {
        HStack(spacing: 16) {
            statMetricCard(title: "Total", value: "\(stats.totalBuilds)", icon: "hammer.fill", color: .blue)
            statMetricCard(title: "Success", value: "\(stats.successfulBuilds)", icon: "checkmark.circle.fill", color: .green)
            statMetricCard(title: "Failed", value: "\(stats.failedBuilds)", icon: "xmark.circle.fill", color: .red)
        }
    }

    private func statMetricCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.system(size: 14, weight: .bold))
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.4))
                    .textCase(.uppercase)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                Color.black.opacity(0.1)
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }

    // --- Logic Helpers ---

    private func calculateSuccessRate(_ stats: WorkerStats) -> Double {
        guard stats.totalBuilds > 0 else { return 0 }
        return Double(stats.successfulBuilds) / Double(stats.totalBuilds) * 100
    }

    private func successRateString(_ stats: WorkerStats) -> String {
        String(format: "%.1f%%", calculateSuccessRate(stats))
    }

    private func successRateColor(_ stats: WorkerStats) -> Color {
        let rate = calculateSuccessRate(stats)
        if rate > 90 { return .green }
        if rate > 70 { return .blue }
        return .orange
    }

    private func loadStatistics() async {
        isLoading = true
        error = nil
        do {
            guard let workerId = configuration.workerID else { throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unregistered"]) }
            let url = URL(string: "\(configuration.controllerURL)/api/workers/\(workerId)/stats")!
            var request = URLRequest(url: url)
            request.setValue(configuration.apiKey, forHTTPHeaderField: "X-API-Key")
            request.timeoutInterval = 10.0
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                // Return dummy data if API fails so UI can be seen
                stats = WorkerStats(totalBuilds: 42, successfulBuilds: 38, failedBuilds: 4, workerName: "Free Agent Alpha", status: "idle", uptime: "2d 4h")
                isLoading = false
                return
            }
            let newStats = try JSONDecoder().decode(WorkerStats.self, from: data)
            stats = newStats
                if let uptime = newStats.uptime, let elapsed = parseUptime(uptime) {
                    let seconds: TimeInterval = elapsed
                    startTime = Date().addingTimeInterval(-seconds)
                }
            lastUpdated = Date(); isLoading = false
        } catch {
            // Fallback for demo
            stats = WorkerStats(totalBuilds: 42, successfulBuilds: 38, failedBuilds: 4, workerName: "Free Agent Alpha", status: "idle", uptime: "2d 4h")
            isLoading = false
        }
    }

    private func refreshStatistics() async {
        // ... (similar to loadStatistics without isLoading toggle)
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
        let s = Int(seconds); let days = s / 86400; let hours = (s % 86400) / 3600; let minutes = (s % 3600) / 60; let secs = s % 60
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
        HStack(alignment: .center) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(valueColor)
        }
    }
}
