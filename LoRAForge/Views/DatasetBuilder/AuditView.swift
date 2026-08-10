import SwiftUI
import SwiftData
import TaggingCore

struct AuditView: View {
    let result: AuditResult
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                denominatorSection
                ForEach(result.categoryReports) { report in
                    categorySection(report)
                }
            }
            .navigationTitle("Audit")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Denominator

    private var denominatorSection: some View {
        Section {
            Text(result.denominatorDescription)
                .font(.headline)
            if result.auditedEntries == 0 {
                Text("No tagged-mode entries with a final image to audit.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Scope")
        } footer: {
            Text("Only tagged-mode entries with a final image are included. Manual and Ollama entries are excluded because their tags do not affect the exported caption.")
        }
    }

    // MARK: - Category

    private func categorySection(_ report: CategoryReport) -> some View {
        Section {
            // Coverage bar
            HStack {
                Text("Coverage")
                Spacer()
                Text("\(Int(report.coveragePercent))%")
                    .monospacedDigit()
                    .foregroundStyle(coverageColor(report))
            }

            ProgressView(value: report.coveragePercent, total: 100)
                .tint(coverageColor(report))

            if report.isPartialCoverage {
                Label("Partial coverage — tagged in some entries but not others",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            // Tag frequencies
            if !report.tagFrequencies.isEmpty {
                ForEach(report.tagFrequencies) { freq in
                    HStack {
                        Text(freq.canonicalString)
                            .font(.callout)
                        Spacer()
                        Text("\(freq.count)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Text("(\(Int(freq.percent))%)")
                            .foregroundStyle(frequencyColor(freq))
                            .monospacedDigit()
                            .frame(width: 50, alignment: .trailing)
                    }
                }
            }
        } header: {
            HStack {
                Text(report.category.name)
                Spacer()
                if report.highThresholdExceeded || report.lowThresholdBelow {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
        } footer: {
            Text("Thresholds: >\(Int(report.category.highThreshold * 100))% high, <\(Int(report.category.lowThreshold * 100))% low")
        }
    }

    private func coverageColor(_ report: CategoryReport) -> Color {
        if report.coveragePercent == 0 || report.coveragePercent == 100 {
            return .secondary // deliberate decision
        }
        return report.isPartialCoverage ? .orange : .primary
    }

    private func frequencyColor(_ freq: TagFrequency) -> Color {
        if freq.aboveHigh { return .red }
        if freq.belowLow { return .orange }
        return .secondary
    }
}
