import SwiftUI
import Combine
import DrawThingsQueue
import DrawThingsClient

struct QueueManagerView: View {
    @Environment(GenerationService.self) private var generation

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding()

            if !generation.isConnected {
                disconnectedView
                    .padding(.horizontal)
                    .padding(.bottom)
            } else if !generation.isProcessing && generation.pendingCount == 0 {
                emptyView
                    .padding(.horizontal)
                    .padding(.bottom)
            } else {
                if generation.isProcessing {
                    activeJobView
                    Divider()
                }

                if !generation.pendingRequests.isEmpty {
                    pendingList
                }

                bottomBar
            }

            if let error = generation.lastError {
                Divider()
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding()
            }
        }
        .frame(minWidth: 280, maxWidth: 320)
    }

    // MARK: - Header

    private var header: some View {
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
    }

    // MARK: - Disconnected / Empty

    private var disconnectedView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Not connected", systemImage: "xmark.circle")
                .foregroundStyle(.secondary)
            Text("Connect in Settings > Draw Things")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var emptyView: some View {
        Label("Queue empty", systemImage: "checkmark.circle")
            .foregroundStyle(.secondary)
    }

    // MARK: - Active Job

    private var activeJobView: some View {
        HStack(alignment: .top, spacing: 10) {
            if let progress = generation.currentProgress {
                ProgressPreviewImage(progress: progress)
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                progressPlaceholder
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            VStack(alignment: .leading, spacing: 4) {
                if let request = generation.currentRequest {
                    Text(generation.entryName(for: request.id) ?? request.name)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(2)
                }

                if let progress = generation.currentProgress {
                    ProgressDetailView(progress: progress)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .padding()
    }

    private var progressPlaceholder: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.15))
            .overlay {
                ProgressView()
                    .controlSize(.small)
            }
    }

    // MARK: - Pending List

    private var pendingList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(generation.pendingRequests) { request in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(generation.entryName(for: request.id) ?? request.name)
                                .font(.subheadline)
                                .lineLimit(1)
                            Text(String(request.prompt.prefix(60)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Button {
                            generation.cancelRequest(id: request.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Cancel")
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 6)

                    Divider()
                        .padding(.leading)
                }
            }
        }
        .frame(maxHeight: 200)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            Button {
                generation.togglePause()
            } label: {
                Label(
                    generation.isPaused ? "Resume" : "Pause",
                    systemImage: generation.isPaused ? "play.fill" : "pause.fill"
                )
            }
            .buttonStyle(.borderless)

            Spacer()

            if !generation.pendingRequests.isEmpty {
                Button("Clear pending", role: .destructive) {
                    generation.clearPending()
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
        .padding()
    }
}

// MARK: - Progress Child Views
// These use @ObservedObject to react to @Published changes on GenerationProgress.

private struct ProgressPreviewImage: View {
    @ObservedObject var progress: GenerationProgress

    var body: some View {
        if let preview = progress.previewImage {
            #if os(macOS)
            Image(nsImage: preview)
                .resizable()
                .aspectRatio(contentMode: .fill)
            #else
            Image(uiImage: preview)
                .resizable()
                .aspectRatio(contentMode: .fill)
            #endif
        } else {
            Rectangle()
                .fill(Color.gray.opacity(0.15))
                .overlay {
                    ProgressView()
                        .controlSize(.small)
                }
        }
    }
}

private struct ProgressDetailView: View {
    @ObservedObject var progress: GenerationProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(progress.stage.description)
                .font(.caption)
                .foregroundStyle(.secondary)

            ProgressView(value: progress.progressFraction)
                .controlSize(.small)

            Text("\(progress.currentStep)/\(progress.totalSteps) steps")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}
