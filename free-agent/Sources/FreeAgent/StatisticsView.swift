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

    var body: some View {
        VStack(spacing: 0) {
            // Header with logo
            VStack(spacing: 16) {
                if let logoPath = Bundle.main.path(forResource: "expo-free-agent-logo-white", ofType: "png"),
                   let nsImage = NSImage(contentsOfFile: logoPath) {
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
                    VStack(alignment: .leading, spacing: 24) {
                        // Worker Info
                        GroupBox(label: Label("Worker Information", systemImage: "desktopcomputer")) {
                            VStack(alignment: .leading, spacing: 12) {
                                StatRow(label: "Name", value: stats.workerName)
                                StatRow(label: "Status", value: stats.status.capitalized, valueColor: stats.status == "running" ? .green : .secondary)
                                if let uptime = stats.uptime {
                                    StatRow(label: "Uptime", value: uptime)
                                }
                            }
                            .padding(.vertical, 8)
                        }

                        // Build Statistics
                        GroupBox(label: Label("Build Statistics", systemImage: "hammer")) {
                            VStack(alignment: .leading, spacing: 12) {
                                StatRow(label: "Total Builds", value: "\(stats.totalBuilds)")
                                StatRow(label: "Successful", value: "\(stats.successfulBuilds)", valueColor: .green)
                                StatRow(label: "Failed", value: "\(stats.failedBuilds)", valueColor: stats.failedBuilds > 0 ? .red : .secondary)

                                if stats.totalBuilds > 0 {
                                    let successRate = Double(stats.successfulBuilds) / Double(stats.totalBuilds) * 100
                                    StatRow(label: "Success Rate", value: String(format: "%.1f%%", successRate))
                                }
                            }
                            .padding(.vertical, 8)
                        }

                        // Configuration
                        GroupBox(label: Label("Configuration", systemImage: "gearshape")) {
                            VStack(alignment: .leading, spacing: 12) {
                                StatRow(label: "Controller URL", value: configuration.controllerURL)
                                StatRow(label: "Max Concurrent Builds", value: "\(configuration.maxConcurrentBuilds)")
                                StatRow(label: "Auto-start", value: configuration.autoStart ? "Enabled" : "Disabled")
                            }
                            .padding(.vertical, 8)
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
                stats = try JSONDecoder().decode(WorkerStats.self, from: data)
            } else {
                throw NSError(domain: "", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"])
            }

            isLoading = false
        } catch {
            self.error = error.localizedDescription
            isLoading = false
        }
    }
}

struct StatRow: View {
    let label: String
    let value: String
    var valueColor: Color = .primary

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .foregroundColor(valueColor)
        }
    }
}

#Preview {
    StatisticsView(configuration: WorkerConfiguration.load())
}
