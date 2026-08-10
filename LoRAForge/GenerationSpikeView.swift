/// Phase 8 — Generation spike. THROWAWAY. Delete after answering questions.
///
/// Questions answered from API exploration:
///
/// 1. Does DrawThingsConfiguration expose seed?
///    YES — `seed: Int64?`. nil or <0 auto-generates a random seed at enqueue time.
///    The seed actually used is visible in `GenerationRequest.configuration.seed`.
///    Batch size fixed at 1 means one request = one image = one known seed.
///
/// 2. What does the config JSON look like?
///    DrawThingsConfiguration is a large struct with ~80+ properties: width, height,
///    steps, model, sampler, guidanceScale, seed, loras, controls, strength, hiresFix,
///    refiner, faceRestoration, upscaler, and many more. DTConfigEditorKit provides
///    a JSON editing view for it but is not yet wired into the app.
///
/// 3. What happens on connection failure?
///    The queue auto-pauses (`isPaused = true`), `lastError` is populated with the
///    error string, and `errors` array accumulates `GenerationError` values.
///    `resume()` clears `lastError` and restarts processing.
///    Per-request failures are available via `status(for:)` → `.failed(GenerationError)`.
///    `canRetry(for:)` and `retry(_:)` handle re-submission up to `maxRetries` (default 3).

import SwiftUI
import Combine
import DrawThingsQueue
import DrawThingsClient

struct GenerationSpikeView: View {
    @State private var address = "localhost:7859"
    @State private var prompt = "a cat sitting on a windowsill, oil painting"
    @State private var queue: DrawThingsQueue?
    @State private var resultImage: NSImage?
    @State private var previewImage: NSImage?
    @State private var progressText = "Idle"
    @State private var progressFraction: Double = 0
    @State private var errorText: String?
    @State private var seedUsed: Int64?
    @State private var cancellables = Set<AnyCancellable>()
    @State private var resultTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 16) {
            Text("Generation Spike")
                .font(.title2)

            HStack {
                TextField("Server address", text: $address)
                    .textFieldStyle(.roundedBorder)
                Button(queue == nil ? "Connect" : "Disconnect") {
                    if queue == nil { connect() } else { disconnect() }
                }
            }

            TextField("Prompt", text: $prompt)
                .textFieldStyle(.roundedBorder)

            Button("Generate") { generate() }
                .disabled(queue == nil)

            // Progress
            VStack(spacing: 4) {
                Text(progressText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ProgressView(value: progressFraction)
            }

            // Preview / Result
            HStack(spacing: 16) {
                VStack {
                    Text("Preview").font(.caption)
                    if let previewImage {
                        Image(nsImage: previewImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 200, height: 200)
                    } else {
                        Rectangle().fill(.gray.opacity(0.2))
                            .frame(width: 200, height: 200)
                    }
                }
                VStack {
                    Text("Result").font(.caption)
                    if let resultImage {
                        Image(nsImage: resultImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 200, height: 200)
                    } else {
                        Rectangle().fill(.gray.opacity(0.2))
                            .frame(width: 200, height: 200)
                    }
                }
            }

            if let seedUsed {
                Text("Seed: \(seedUsed)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let errorText {
                Text(errorText)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
        .padding()
        .frame(minWidth: 500, minHeight: 500)
    }

    private func connect() {
        do {
            let q = try DrawThingsQueue(address: address, useTLS: false)
            queue = q

            // Observe progress
            q.$currentProgress
                .receive(on: DispatchQueue.main)
                .sink { progress in
                    if let progress {
                        progressText = "\(progress.stage.description) — \(progress.progressPercentage)%"
                        progressFraction = progress.progressFraction
                        if let preview = progress.previewImage {
                            previewImage = preview
                        }
                    }
                }
                .store(in: &cancellables)

            // Observe errors
            q.$lastError
                .receive(on: DispatchQueue.main)
                .sink { error in
                    errorText = error
                }
                .store(in: &cancellables)

            q.$isPaused
                .receive(on: DispatchQueue.main)
                .sink { paused in
                    if paused {
                        progressText = "Paused (connection issue)"
                    }
                }
                .store(in: &cancellables)

            progressText = "Connected to \(address)"
        } catch {
            errorText = "Connection failed: \(error.localizedDescription)"
        }
    }

    private func disconnect() {
        resultTask?.cancel()
        cancellables.removeAll()
        queue = nil
        progressText = "Disconnected"
    }

    private func generate() {
        guard let queue else { return }

        // Clear previous state
        resultImage = nil
        previewImage = nil
        errorText = nil
        seedUsed = nil
        progressFraction = 0

        // App owns the seed — generate one
        let seed = Int64(Int.random(in: 0...Int(UInt32.max)))

        var config = DrawThingsConfiguration()
        config.seed = seed
        config.batchSize = 1
        config.batchCount = 1

        // Subscribe to results stream BEFORE enqueueing (design requirement)
        resultTask?.cancel()
        resultTask = Task {
            for await result in queue.results {
                resultImage = result.images.first
                seedUsed = result.request.configuration.seed
                progressText = "Done in \(String(format: "%.1f", result.duration))s"
                progressFraction = 1.0
            }
        }

        progressText = "Generating..."
        queue.enqueue(prompt: prompt, negativePrompt: "", configuration: config)
    }
}
