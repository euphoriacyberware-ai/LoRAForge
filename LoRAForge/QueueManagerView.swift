import SwiftUI
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

                if !generation.pendingJobs.isEmpty {
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
            Group {
                if let preview = generation.currentPreview {
                    Image(decorative: preview, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    progressPlaceholder
                }
            }
            .frame(width: 80, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                if let job = generation.currentJob {
                    Text(generation.entryName(for: job.id) ?? job.name)
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
                ForEach(generation.pendingJobs) { job in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(generation.entryName(for: job.id) ?? job.name)
                                .font(.subheadline)
                                .lineLimit(1)
                            Text(String(job.request.prompt.prefix(60)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Button {
                            generation.cancelRequest(id: job.id)
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

            if !generation.pendingJobs.isEmpty {
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

// MARK: - Progress Detail

private struct ProgressDetailView: View {
    let progress: GenerationProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(progress.stage.description)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let fraction = progress.fractionCompleted {
                ProgressView(value: fraction)
                    .controlSize(.small)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
                    .controlSize(.small)
            }

            Text("\(progress.step ?? 0)/\(progress.totalSteps) steps")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}
