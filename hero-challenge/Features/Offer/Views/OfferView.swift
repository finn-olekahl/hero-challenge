import SwiftUI

/// Final screen showing offer summary and creation status.
struct OfferView: View {
    var controller: OfferController
    var onDone: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    headerSection

                    // Summary
                    summarySection

                    // Services
                    servicesSection

                    // Materials
                    materialsSection

                    // Status / Action
                    actionSection
                }
                .padding()
            }
            .navigationTitle("Angebot erstellen")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: controller.isCompleted ? "checkmark.seal.fill" : "doc.text.fill")
                .font(.system(size: 48))
                .foregroundStyle(controller.isCompleted ? .green : .blue)

            Text(controller.isCompleted ? "Angebot erstellt" : "Angebot wird vorbereitet")
                .font(.title2.weight(.semibold))
        }
        .padding(.top)
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Zusammenfassung")
                .font(.headline)

            summaryRow(icon: "folder", label: "Projekt", value: controller.offerSummary.projectName)
            summaryRow(icon: "wrench.and.screwdriver", label: "Leistungen", value: "\(controller.offerSummary.serviceCount)")
            summaryRow(icon: "shippingbox", label: "Materialien", value: "\(controller.offerSummary.materialCount)")
            summaryRow(icon: "doc.text", label: "Positionen gesamt", value: "\(controller.offerSummary.totalPositions)")
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func summaryRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.body.weight(.medium))
        }
    }

    private var servicesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Leistungen")
                .font(.headline)

            ForEach(controller.answers.billingMethods, id: \.service.id) { entry in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.service.name)
                            .font(.body.weight(.medium))
                        Text(billingMethodText(entry.method))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let qty = entry.service.suggestedQuantity {
                        Text(String(format: "%.1f %@", qty, entry.service.suggestedUnit ?? ""))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var materialsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Materialien")
                .font(.headline)

            ForEach(controller.answers.selectedProducts, id: \.material.id) { entry in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.product?.displayName ?? entry.material.category)
                            .font(.body.weight(.medium))
                        Text(entry.material.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let qty = entry.material.suggestedQuantity {
                        Text(String(format: "%.1f %@", qty, entry.material.suggestedUnit ?? ""))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var actionSection: some View {
        VStack(spacing: 12) {
            if let error = controller.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            if controller.isCompleted {
                Button(action: onDone) {
                    Text("Fertig")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .foregroundStyle(.white)
                        .background(Color.green)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            } else {
                Button {
                    Task { await controller.createOffer() }
                } label: {
                    if controller.isCreating {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else {
                        Text("Angebot via API anlegen")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .foregroundStyle(.white)
                            .background(Color.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
                .disabled(controller.isCreating)
            }
        }
    }

    // MARK: - Helpers

    private func billingMethodText(_ method: BillingMethod) -> String {
        switch method {
        case .unselected: return "Nicht festgelegt"
        case .hourly(let hours): return "\(String(format: "%.1f", hours)) Stunden"
        case .serviceType(let service): return service?.displayName ?? "Leistungstyp"
        }
    }
}
