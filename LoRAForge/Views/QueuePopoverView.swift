import SwiftUI
import DrawThingsQueue

struct QueuePopoverView: View {
    @ObservedObject var generationService: GenerationService
    @ObservedObject var queue: DrawThingsQueue

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            connectionErrorBanner
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    currentRequestSection
                    pendingSection
                    completedSection
                    errorsSection
                }
            }
        }
        .frame(width: 340, height: 420)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Text("Generation Queue")
                .font(.headline)

            Spacer()

            if queue.isPaused && queue.lastError == nil {
                Button {
                    queue.resume()
                } label: {
                    Label("Resume", systemImage: "play.fill")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            } else if !queue.isPaused && queue.isProcessing {
                Button {
                    queue.pause()
                } label: {
                    Label("Pause", systemImage: "pause.fill")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }

            if !queue.pendingRequests.isEmpty || queue.isProcessing {
                Button("Cancel All") {
                    generationService.stop()
                }
                .font(.caption)
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
            }
        }
        .padding(12)
    }

    // MARK: - Connection Error Banner

    @ViewBuilder
    private var connectionErrorBanner: some View {
        if let error = queue.lastError {
            VStack(alignment: .leading, spacing: 6) {
                Label("Connection Lost", systemImage: "wifi.exclamationmark")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)

                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Button {
                    queue.resume()
                } label: {
                    Label("Reconnect", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.1))

            Divider()
        }
    }

    // MARK: - Current Request

    @ViewBuilder
    private var currentRequestSection: some View {
        if let current = queue.currentRequest {
            let mapping = generationService.requestMappings[current.id]
            let progress = queue.currentProgress

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Generating", systemImage: "play.circle.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.blue)
                    Spacer()
                    if let progress, progress.totalSteps > 0 {
                        Text("\(progress.progressPercentage)%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(alignment: .top, spacing: 10) {
                    if let preview = generationService.previewImage {
                        Image(nsImage: preview)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.quaternary)
                            .frame(width: 80, height: 80)
                            .overlay {
                                ProgressView()
                                    .controlSize(.small)
                            }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(requestLabel(for: mapping, name: current.name))
                            .font(.caption.bold())
                        Text(current.prompt)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)

                        if let progress, progress.totalSteps > 0 {
                            ProgressView(value: progress.progressFraction)
                                .progressViewStyle(.linear)
                            Text("Step \(progress.currentStep)/\(progress.totalSteps)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        } else if let stage = generationService.generationStage {
                            Text(stage)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .padding(12)

            Divider()
        }
    }

    // MARK: - Pending

    @ViewBuilder
    private var pendingSection: some View {
        if !queue.pendingRequests.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Label("Pending (\(queue.pendingRequests.count))", systemImage: "clock")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 2)

                ForEach(queue.pendingRequests) { request in
                    let mapping = generationService.requestMappings[request.id]

                    HStack {
                        Image(systemName: "line.3.horizontal")
                            .font(.caption2)
                            .foregroundStyle(.quaternary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(requestLabel(for: mapping, name: request.name))
                                .font(.caption.bold())
                            Text(request.prompt)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button {
                            generationService.cancelRequest(id: request.id)
                        } label: {
                            Image(systemName: "xmark.circle")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Cancel this request")
                    }
                    .padding(.vertical, 3)
                }
                .onMove { source, destination in
                    queue.moveRequests(from: source, to: destination)
                }
            }
            .padding(12)

            Divider()
        }
    }

    // MARK: - Completed

    @ViewBuilder
    private var completedSection: some View {
        let completed = generationService.currentImageIndex
        let total = generationService.totalImages

        if completed > 0 {
            VStack(alignment: .leading, spacing: 4) {
                Label("Completed (\(completed)/\(total))", systemImage: "checkmark.circle")
                    .font(.caption.bold())
                    .foregroundStyle(.green)

                ProgressView(value: generationService.progressFraction)
                    .progressViewStyle(.linear)
            }
            .padding(12)

            Divider()
        }
    }

    // MARK: - Errors

    @ViewBuilder
    private var errorsSection: some View {
        if !queue.errors.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label("Errors (\(queue.errors.count))", systemImage: "exclamationmark.triangle")
                        .font(.caption.bold())
                        .foregroundStyle(.red)
                    Spacer()
                    Button("Clear") {
                        queue.clearErrors()
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }

                ForEach(queue.errors) { error in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(error.request.name)
                                .font(.caption.bold())
                            Text(error.underlyingError.localizedDescription)
                                .font(.caption2)
                                .foregroundStyle(.red)
                                .lineLimit(2)
                        }
                        Spacer()
                        if queue.canRetry(for: error.id) {
                            Button {
                                queue.retry(error.id)
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .foregroundStyle(.blue)
                            }
                            .buttonStyle(.plain)
                            .help("Retry (\(queue.retryCount(for: error.id))/\(queue.maxRetries))")
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(12)
        }
    }

    // MARK: - Helpers

    private func requestLabel(for mapping: GenerationService.RequestMapping?, name: String) -> String {
        if let mapping {
            return "Prompt \(mapping.promptDisplayNumber) — image \(mapping.imageNumber + 1)/\(mapping.totalForPrompt)"
        }
        return name
    }
}
