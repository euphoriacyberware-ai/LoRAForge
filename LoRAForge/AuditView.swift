import SwiftUI
import TaggingCore

struct AuditView: View {
    let document: ProjectDocument
    let bundleURL: URL

    @Environment(TagRepository.self) private var repo
    @Environment(\.dismiss) private var dismiss

    @State private var result: AuditResult?

    var body: some View {
        NavigationStack {
            Group {
                if let result {
                    auditContent(result)
                } else {
                    ProgressView("Computing...")
                }
            }
            .navigationTitle("Audit")
            #if os(macOS)
            .frame(minWidth: 550, minHeight: 450)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear(perform: compute)
        }
    }

    private func compute() {
        let categories = (try? repo.allCategories()) ?? []
        let tags = (try? repo.allTags()) ?? []
        let tagDict = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0) })
        result = AuditEngine.audit(document: document, categories: categories, allTags: tagDict)
    }

    // MARK: - Content

    private func auditContent(_ result: AuditResult) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                denominatorStatement(result)
                    .padding(.horizontal)

                if result.scopedEntries == 0 {
                    ContentUnavailableView(
                        "No entries to audit",
                        systemImage: "chart.bar",
                        description: Text("The audit covers tagged-mode entries with a final image. None match.")
                    )
                } else {
                    ForEach(result.categoryResults) { catResult in
                        categorySection(catResult, scopedCount: result.scopedEntries)
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
    }

    private func denominatorStatement(_ result: AuditResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(result.scopedEntries) of \(result.totalEntries) entries audited")
                .font(.headline)

            var parts: [String] = []
            let _ = {
                if result.excludedNoFinal > 0 {
                    parts.append("\(result.excludedNoFinal) not finalized")
                }
                if result.excludedNotTagged > 0 {
                    parts.append("\(result.excludedNotTagged) not tag-captioned")
                }
            }()

            if !parts.isEmpty {
                Text("Excluded: \(parts.joined(separator: ", "))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Category Section

    private func categorySection(_ catResult: CategoryAuditResult, scopedCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text(catResult.categoryName)
                    .font(.headline)
                Spacer()
                coverageBadge(catResult)
            }

            // Coverage bar
            HStack(spacing: 4) {
                Text("Coverage: \(catResult.coverageCount)/\(scopedCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.gray.opacity(0.15))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(coverageColor(catResult))
                            .frame(width: geo.size.width * catResult.coverage)
                    }
                }
                .frame(height: 8)
                Text(String(format: "%.0f%%", catResult.coverage * 100))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
            }

            // Tag frequencies
            if !catResult.tagFrequencies.isEmpty {
                ForEach(catResult.tagFrequencies) { freq in
                    tagFrequencyRow(freq, scopedCount: scopedCount)
                }
            } else {
                Text("No tags assigned in this category")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func coverageBadge(_ catResult: CategoryAuditResult) -> some View {
        if catResult.isPartialCoverage {
            Label("Partial", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
        } else if catResult.coverage == 0 {
            Text("Unused")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func coverageColor(_ catResult: CategoryAuditResult) -> Color {
        if catResult.isPartialCoverage { return .orange }
        if catResult.coverage == 0 { return .gray }
        return .green
    }

    // MARK: - Tag Frequency Row

    private func tagFrequencyRow(_ freq: CategoryAuditResult.TagFrequency, scopedCount: Int) -> some View {
        HStack(spacing: 8) {
            Text(freq.tagName)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.1))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(frequencyColor(freq))
                        .frame(width: geo.size.width * freq.fraction)
                }
            }
            .frame(width: 100, height: 6)

            Text("\(freq.count)/\(scopedCount)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 45, alignment: .trailing)

            Text(String(format: "%.0f%%", freq.fraction * 100))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 35, alignment: .trailing)

            if freq.isAboveHigh {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .help("Above \(Int(freq.fraction * 100))% — high threshold")
            } else if freq.isBelowLow {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .help("Below \(Int(freq.fraction * 100))% — low threshold")
            } else {
                Color.clear.frame(width: 14)
            }
        }
    }

    private func frequencyColor(_ freq: CategoryAuditResult.TagFrequency) -> Color {
        if freq.isAboveHigh { return .red.opacity(0.6) }
        if freq.isBelowLow { return .blue.opacity(0.6) }
        return .green.opacity(0.6)
    }
}
