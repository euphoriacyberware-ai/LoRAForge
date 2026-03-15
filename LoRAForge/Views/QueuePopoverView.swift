import SwiftUI
import DrawThingsQueue

struct QueuePopoverView: View {
    @ObservedObject var generationService: GenerationService
    @ObservedObject var queue: DrawThingsQueue

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    currentRequestSection
                    pendingSection
                    completedSection
                    errorsSection
                }
            }
        }
        .frame(width: 320, height: 400)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Generation Queue")
                .font(.headline)
            Spacer()
            if !queue.pendingRequests.isEmpty {
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

    // MARK: - Current Request

    @ViewBuilder
    private var currentRequestSection: some View {
        if let current = queue.currentRequest {
            let mapping = generationService.requestMappings[current.id]

            VStack(alignment: .leading, spacing: 8) {
                Label("Generating", systemImage: "play.circle.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.blue)

                HStack(alignment: .top, spacing: 10) {
                    // Preview image
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
                        Text(promptLabel(for: mapping, request: current))
                            .font(.caption.bold())
                        Text(current.prompt)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                        if let stage = generationService.generationStage {
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
                        VStack(alignment: .leading, spacing: 2) {
                            Text(promptLabel(for: mapping, request: request))
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
                Label("Errors (\(queue.errors.count))", systemImage: "exclamationmark.triangle")
                    .font(.caption.bold())
                    .foregroundStyle(.red)

                ForEach(queue.errors) { error in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(error.request.prompt)
                            .font(.caption)
                            .lineLimit(1)
                        Text(error.underlyingError.localizedDescription)
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(12)
        }
    }

    // MARK: - Helpers

    private func promptLabel(for mapping: GenerationService.RequestMapping?, request: GenerationRequest) -> String {
        guard let mapping else {
            return "Image"
        }
        return "Prompt \(mapping.promptDisplayNumber) — image \(mapping.imageNumber + 1)/\(mapping.totalForPrompt)"
    }
}
