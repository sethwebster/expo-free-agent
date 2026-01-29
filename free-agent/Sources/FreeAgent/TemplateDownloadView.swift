import SwiftUI
import DiagnosticsCore

struct TemplateDownloadView: View {
    let progress: DownloadProgress
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 32) {
                        VStack(spacing: 16) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.orange.gradient.opacity(0.1))
                                    .frame(width: 80, height: 80)
                                
                                Image(systemName: "box.panel.fill")
                                    .font(.system(size: 32, weight: .semibold))
                                    .foregroundColor(.orange)
                            }
                            
                            VStack(spacing: 4) {
                                Text("Virtual Machine Setup")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                Text("Preparing your build environment")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.top, 24)

                        // Progress indicator
                        if let percent = progress.percentComplete {
                            circularProgress(percent: percent)
                        } else {
                            VStack(spacing: 20) {
                                ProgressView()
                                    .controlSize(.large)
                                Text("Initializing connection...")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(height: 160)
                        }

                        // Status Card
                        PremiumSectionCard(title: "Current Status", icon: "terminal.fill", color: .gray) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(progress.message)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.primary)
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.primary.opacity(0.04))
                                    .cornerRadius(8)
                                
                                if progress.status == .downloading || progress.status == .extracting {
                                    HStack {
                                        Image(systemName: "info.circle")
                                            .foregroundColor(.secondary)
                                        Text("This only happens on the first run")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.top, 4)
                                }
                            }
                        }
                    }
                    .padding(24)
                }

                Divider()

                footerView
            }
        }
        .frame(width: 450, height: 600)
    }

    private func circularProgress(percent: Double) -> some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.05), lineWidth: 12)
                .frame(width: 140, height: 140)

            Circle()
                .trim(from: 0, to: percent / 100.0)
                .stroke(
                    LinearGradient(
                        colors: [.orange, .yellow],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .frame(width: 140, height: 140)
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: percent)

            VStack(spacing: 2) {
                Text("\(Int(percent))%")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                Text(statusText)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
            }
        }
    }

    private var footerView: some View {
        HStack {
            if progress.status == .downloading || progress.status == .extracting {
                Label("Running in background", systemImage: "background")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if progress.status == .complete || progress.status == .failed {
                Button(progress.status == .complete ? "Get Started" : "Close") {
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(progress.status == .complete ? .blue : .red)
            } else {
                Button("Continue in Background") {
                    onDismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
    }

    private var statusText: String {
        switch progress.status {
        case .idle: return "Ready"
        case .downloading: return "Downloading"
        case .extracting: return "Extracting"
        case .complete: return "Complete"
        case .failed: return "Failed"
        }
    }
}

#Preview {
    TemplateDownloadView(
        progress: DownloadProgress(
            status: .downloading,
            message: "Fetching base image layers from GitHub Container Registry...",
            percentComplete: 64.2
        ),
        onDismiss: {}
    )
}
