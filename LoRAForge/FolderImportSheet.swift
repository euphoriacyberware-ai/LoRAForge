import SwiftUI

/// Identifies a pending folder import so it can drive `.sheet(item:)`.
struct FolderImportRequest: Identifiable {
    let id = UUID()
    let url: URL
    /// Whether `startAccessingSecurityScopedResource` succeeded, so the stop can be matched.
    let isScoped: Bool
}

/// Scans a folder, confirms what was found, then imports it.
///
/// The confirm step earns its place: the import is not undoable and can append hundreds of
/// entries, and it is the one place to say that subfolders were ignored before committing.
struct FolderImportSheet: View {
    let request: FolderImportRequest
    let bundleURL: URL
    let onComplete: (FolderImporter.Summary) -> Void

    @Environment(\.dismiss) private var dismiss

    private enum Phase {
        case scanning
        case confirm(FolderImporter.ScanResult)
        case importing
        case report(FolderImporter.Summary)
    }

    @State private var phase: Phase = .scanning
    @State private var completed = 0
    @State private var total = 0
    /// The detached ingest task. Held directly because `Task.detached` does not inherit
    /// cancellation from the task that spawned it — cancelling the awaiting task would
    /// leave the import running.
    @State private var ingestTask: Task<FolderImporter.Summary, Never>?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Import folder")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar { toolbarContent }
        }
        .frame(minWidth: 440, minHeight: 320)
        .task { await scan() }
        .onDisappear { ingestTask?.cancel() }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .scanning:
            centered {
                ProgressView()
                Text("Scanning \(request.url.lastPathComponent)\u{2026}")
                    .foregroundStyle(.secondary)
            }

        case .confirm(let scan):
            confirmView(scan)

        case .importing:
            centered {
                ProgressView(value: Double(completed), total: Double(max(total, 1)))
                    .frame(maxWidth: 260)
                Text("Importing \(completed) of \(total)\u{2026}")
                    .foregroundStyle(.secondary)
            }

        case .report(let summary):
            reportView(summary)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            switch phase {
            case .confirm(let scan):
                Button("Import") { startImport(scan) }
                    .disabled(scan.candidates.isEmpty)
            case .report:
                Button("Done") { dismiss() }
            default:
                EmptyView()
            }
        }
        ToolbarItem(placement: .cancellationAction) {
            switch phase {
            case .importing:
                Button("Cancel") { ingestTask?.cancel() }
            case .report:
                EmptyView()
            default:
                Button("Cancel") { dismiss() }
            }
        }
    }

    // MARK: - Phases

    private func centered<V: View>(@ViewBuilder _ body: () -> V) -> some View {
        VStack(spacing: 16) { body() }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
    }

    @ViewBuilder
    private func confirmView(_ scan: FolderImporter.ScanResult) -> some View {
        Form {
            if scan.candidates.isEmpty {
                Section {
                    Label("No images found in that folder.", systemImage: "questionmark.folder")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Found") {
                    LabeledContent("Images") { Text("\(scan.candidates.count)") }
                    LabeledContent("With captions") { Text("\(scan.captionCount)") }
                }
                Section {
                    Text("Each image becomes a new entry, ranked final. "
                         + "A sidecar .txt becomes that entry's manual caption.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if scan.subfoldersIgnored > 0 || scan.orphanSidecars > 0 {
                Section("Ignored") {
                    if scan.subfoldersIgnored > 0 {
                        Label(
                            "\(scan.subfoldersIgnored) subfolder\(scan.subfoldersIgnored == 1 ? "" : "s") — only the top level is imported",
                            systemImage: "folder"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    if scan.orphanSidecars > 0 {
                        Label(
                            "\(scan.orphanSidecars) caption file\(scan.orphanSidecars == 1 ? "" : "s") with no matching image",
                            systemImage: "doc.text"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func reportView(_ summary: FolderImporter.Summary) -> some View {
        Form {
            if summary.wasCancelled {
                Section {
                    Label("Import cancelled. Nothing was added.", systemImage: "xmark.circle")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Imported") {
                    LabeledContent("Entries created") { Text("\(summary.items.count)") }
                    LabeledContent("Captions imported") { Text("\(summary.captionCount)") }
                }
            }

            if !summary.skipped.isEmpty {
                Section("Skipped (\(summary.skipped.count))") {
                    ForEach(Array(summary.skipped.enumerated()), id: \.offset) { _, file in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.name)
                            Text(file.reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Work

    private func scan() async {
        let folder = request.url
        // Detached, not just nonisolated: with SWIFT_APPROACHABLE_CONCURRENCY a nonisolated
        // async function awaited from here would run on the main actor.
        let result = await Task.detached(priority: .userInitiated) {
            FolderImporter.scan(folder: folder)
        }.value
        phase = .confirm(result)
    }

    private func startImport(_ scan: FolderImporter.ScanResult) {
        total = scan.candidates.count
        completed = 0
        phase = .importing

        let candidates = scan.candidates
        let imagesDir = bundleURL.appending(path: "images")

        let work = Task.detached(priority: .userInitiated) {
            await FolderImporter.ingest(candidates, into: imagesDir) { done in
                completed = done
            }
        }
        ingestTask = work

        Task {
            let summary = await work.value
            if !summary.wasCancelled && !summary.items.isEmpty {
                onComplete(summary)
            }
            phase = .report(summary)
        }
    }
}
