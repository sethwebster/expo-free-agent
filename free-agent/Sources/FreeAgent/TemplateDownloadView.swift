import SwiftUI
import DiagnosticsCore

struct TemplateDownloadView: View {
    let progress: DownloadProgress
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            // Background Glass
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()
            
            // Dark Tint
            Color.black.opacity(0.3)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 40) {
                        VStack(spacing: 16) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(Color.orange.gradient.opacity(0.15))
                                    .frame(width: 80, height: 80)
                                
                                Image(systemName: "box.panel.fill")
                                    .font(.system(size: 32, weight: .bold))
                                    .foregroundColor(.orange)
                            }
                            
                            VStack(spacing: 4) {
                                Text("Building Environment")
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundColor(.white)
                                Text("Preparing your dedicated build virtual machine")
                                    .font(.system(size: 14))
                                    .foregroundColor(.white.opacity(0.5))
                            }
                        }
                        .padding(.top, 24)

                        // Glassy Progress Area
                        if let percent = progress.percentComplete {
                            circularProgress(percent: percent)
                        } else {
                            VStack(spacing: 20) {
                                ProgressView()
                                    .controlSize(.large)
                                Text("Initializing connection...")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white.opacity(0.4))
                            }
                            .frame(height: 160)
                        }

                        // Detailed Status Panel
                        PremiumSectionCard(title: "Installation Status", icon: "terminal.fill", color: .gray) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(progress.message)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.8))
                                    .padding(14)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.black.opacity(0.3))
                                    .cornerRadius(10)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                    )
                                
                                if progress.status == .downloading || progress.status == .extracting {
                                    Label("First-time setup only", systemImage: "info.circle")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.white.opacity(0.4))
                                        .padding(.top, 4)
                                }
                            }
                        }
                    }
                    .padding(40)
                }

                Divider().opacity(0.1)

                footerView
            }
        }
        .frame(width: 480, height: 650)
    }

    private func circularProgress(percent: Double) -> some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.05), lineWidth: 14)
                .frame(width: 160, height: 160)

            Circle()
                .trim(from: 0, to: percent / 100.0)
                .stroke(
                    LinearGradient(
                        colors: [.orange, .yellow],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )
                .frame(width: 160, height: 160)
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: percent)

            VStack(spacing: 2) {
                Text("\(Int(percent))%")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(statusText)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white.opacity(0.5))
                    .textCase(.uppercase)
            }
        }
    }

    private var footerView: some View {
        HStack {
            if progress.status == .downloading || progress.status == .extracting {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Running in background")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            
            Spacer()
            
            if progress.status == .complete || progress.status == .failed {
                Button(progress.status == .complete ? "Launch Worker" : "Close") {
                    onDismiss()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(progress.status == .complete ? Color.blue.gradient : Color.red.gradient)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .foregroundColor(.white)
                .fontWeight(.bold)
            } else {
                Button("Background") {
                    onDismiss()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(VisualEffectView(material: .hudWindow, blendingMode: .withinWindow).clipShape(RoundedRectangle(cornerRadius: 8)))
                .foregroundColor(.white)
            }
        }
        .padding(32)
        .background(VisualEffectView(material: .headerView, blendingMode: .withinWindow))
    }

    private var statusText: String {
        switch progress.status {
        case .idle: return "Ready"
        case .downloading: return "Loading"
        case .extracting: return "Setup"
        case .complete: return "Ready"
        case .failed: return "Failed"
        }
    }
}

#Preview {
    TemplateDownloadView(
        progress: DownloadProgress(
            status: .downloading,
            message: "Fetching VM image layers from GitHub Container Registry...",
            percentComplete: 64.2
        ),
        onDismiss: {}
    )
}
