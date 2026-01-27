import SwiftUI
import DiagnosticsCore

struct TemplateDownloadView: View {
    let progress: DownloadProgress
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Downloading VM Template")
                .font(.title2)
                .fontWeight(.semibold)

            Spacer()

            // Progress indicator
            if let percent = progress.percentComplete {
                // Circular progress
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 12)
                        .frame(width: 120, height: 120)

                    Circle()
                        .trim(from: 0, to: percent / 100.0)
                        .stroke(Color.orange, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .frame(width: 120, height: 120)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut, value: percent)

                    VStack {
                        Text("\(Int(percent))%")
                            .font(.title)
                            .fontWeight(.bold)
                        Text(statusText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                // Indeterminate progress
                ProgressView()
                    .scaleEffect(2.0)
                    .frame(height: 120)
            }

            // Status message
            Text(progress.message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal)

            Spacer()

            // Dismiss button (only show when complete or failed)
            if progress.status == .complete || progress.status == .failed {
                Button(progress.status == .complete ? "Done" : "Close") {
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(30)
        .frame(width: 400, height: 350)
    }

    private var statusText: String {
        switch progress.status {
        case .idle:
            return "Ready"
        case .downloading:
            return "Downloading"
        case .extracting:
            return "Extracting"
        case .complete:
            return "Complete"
        case .failed:
            return "Failed"
        }
    }
}

#Preview {
    TemplateDownloadView(
        progress: DownloadProgress(
            status: .downloading,
            message: "Downloading layer sha256:abc123...",
            percentComplete: 37.5
        ),
        onDismiss: {}
    )
}
