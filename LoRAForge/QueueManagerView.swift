import SwiftUI
import Combine
import DrawThingsQueue

struct QueueManagerView: View {
    @Environment(GenerationService.self) private var generation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Generation queue")
                    .font(.headline)
                Spacer()
                if generation.isPaused {
                    Label("Paused", systemImage: "pause.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            if !generation.isConnected {
                Label("Not connected", systemImage: "xmark.circle")
                    .foregroundStyle(.secondary)
                Text("Connect in Settings > Draw Things")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else if generation.pendingCount == 0 && !generation.isProcessing {
                Label("Queue empty", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            } else {
                if generation.isProcessing {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Generating...")
                    }
                }
                if generation.pendingCount > 0 {
                    Text("\(generation.pendingCount) pending")
                        .foregroundStyle(.secondary)
                }
            }

            if let error = generation.lastError {
                Divider()
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .frame(minWidth: 250)
    }
}
