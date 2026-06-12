import SwiftUI

struct StatsView: View {
    let stats: WhiskerStats

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    allTimeSection
                    perSessionSection
                    if !stats.perEngineBreakdown.isEmpty {
                        byEngineSection
                    }
                }
                .padding()
            }
            .background(WhiskerTheme.appBackground.ignoresSafeArea())
            .navigationTitle("stats")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Sections

    private var allTimeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("All Time")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                StatCard(value: formatWords(stats.totalWords), label: "words")
                StatCard(value: WhiskerStats.formatAudioDuration(stats.totalAudioSeconds), label: "audio")
                StatCard(value: "\(stats.totalTranscriptions)", label: "transcriptions")
                StatCard(value: formatTimeSaved(stats.totalWords), label: "time saved", prefix: "~")
            }
        }
    }

    private var perSessionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Per Session")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                StatCard(value: formatDuration(stats.averageDurationSeconds), label: "average")
                StatCard(value: formatWords(Int(stats.averageWordsPerSession.rounded())), label: "avg words")
            }
            StatCard(value: formatDuration(stats.longestSessionSeconds), label: "longest session")
                .frame(maxWidth: .infinity)
        }
    }

    private var byEngineSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("By Engine")
            VStack(spacing: 6) {
                ForEach(stats.perEngineBreakdown, id: \.engine) { item in
                    HStack {
                        Text(item.engine)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(WhiskerTheme.deepOcean)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Spacer()
                        Text("\(item.count) sessions")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.trailing, 4)
                        Text(formatWords(item.words) + " words")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(WhiskerTheme.pacific)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(WhiskerTheme.foam, in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(WhiskerTheme.pacific.opacity(0.15), lineWidth: 1)
                    }
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.secondary)
            .tracking(0.5)
    }

    // MARK: - Formatting

    private func formatWords(_ count: Int) -> String {
        count.formatted(.number)
    }

    private func formatDuration(_ seconds: Double) -> String {
        if seconds >= 60 {
            let m = Int(seconds) / 60
            let s = Int(seconds) % 60
            return String(format: "%d:%02d", m, s)
        } else {
            return String(format: "%.0fs", seconds)
        }
    }

    private func formatTimeSaved(_ words: Int) -> String {
        let minutes = Double(words) / 40.0
        if minutes >= 60 {
            return String(format: "%.1f hrs", minutes / 60)
        } else {
            return String(format: "%.0f min", minutes)
        }
    }
}

// MARK: - StatCard

private struct StatCard: View {
    let value: String
    let label: String
    var prefix: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(prefix + value)
                .font(.title2.weight(.bold))
                .foregroundStyle(WhiskerTheme.deepOcean)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(WhiskerTheme.foam, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(WhiskerTheme.pacific.opacity(0.15), lineWidth: 1)
        }
    }
}
