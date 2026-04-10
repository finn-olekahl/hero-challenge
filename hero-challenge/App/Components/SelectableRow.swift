import SwiftUI

/// A reusable selectable list row used in the questionnaire for project, product, and service selection.
/// Shows a title, optional subtitle, optional trailing detail, and a checkmark when selected.
///
/// - Note: `subtitle` and `detail` are hidden when `nil` or empty.
struct SelectableRow<ID: Equatable>: View {
    let title: String
    var subtitle: String? = nil
    var detail: String? = nil
    let itemID: ID
    let selectedID: ID?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.medium))
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if itemID == selectedID {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                }
            }
            .padding()
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(itemID == selectedID ? Color.blue.opacity(0.08) : Color(.secondarySystemBackground))
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}
