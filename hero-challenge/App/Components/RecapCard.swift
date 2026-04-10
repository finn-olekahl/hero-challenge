import SwiftUI

// MARK: - Recap Card

/// A horizontal card displaying summary statistics, used during processing/loading screens.
struct RecapCard: View {
    let stats: [RecapStat]
    let accentColor: Color

    var body: some View {
        HStack(spacing: 16) {
            ForEach(Array(stats.enumerated()), id: \.offset) { index, stat in
                if index > 0 {
                    Rectangle()
                        .fill(Color(.separator))
                        .frame(width: 1, height: 36)
                }

                VStack(spacing: 4) {
                    Image(systemName: stat.icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(accentColor)
                    Text(stat.value)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Text(stat.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Recap Stat

/// A single statistic item for use in a `RecapCard`.
struct RecapStat {
    let icon: String
    let value: String
    let label: String
}
