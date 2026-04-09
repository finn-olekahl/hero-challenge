import Foundation

// MARK: - API Response Wrappers

struct ProjectMatchesResponse: Decodable {
    let project_matches: [ProjectMatch]
}

struct ProjectMatchResponse: Decodable {
    let project_match: ProjectMatch
}

struct SupplyProductVersionsResponse: Decodable {
    let supply_product_versions: [SupplyProductVersion]
}

struct SupplyServicesResponse: Decodable {
    let supply_services: [SupplyService]
}

struct CreateDocumentResponse: Decodable {
    let create_document: DocumentDraft
}

struct DocumentTypesResponse: Decodable {
    let document_types: [DocumentType]
}

struct ContactsResponse: Decodable {
    let contacts: [Contact]
}

// MARK: - Domain Models

struct ProjectMatch: Codable, Identifiable, Hashable {
    let id: Int
    let title: String?
    let status: Int?
    let customer: Customer?

    var displayName: String {
        if let title, !title.isEmpty { return title }
        if let customer { return customer.displayName }
        return "Projekt #\(id)"
    }
}

struct Customer: Codable, Identifiable, Hashable {
    let id: Int
    let name: String?
    let first_name: String?
    let last_name: String?
    let company_name: String?

    var displayName: String {
        if let name, !name.isEmpty { return name }
        let parts = [first_name, last_name].compactMap { $0 }.filter { !$0.isEmpty }
        if !parts.isEmpty { return parts.joined(separator: " ") }
        if let company_name, !company_name.isEmpty { return company_name }
        return "Kontakt #\(id)"
    }
}

typealias Contact = Customer

struct SupplyProductVersion: Codable, Identifiable, Hashable {
    let id: Int
    let name: String?
    let description: String?
    let unit: String?
    let price_net: Double?
    let product_id: String?

    var displayName: String {
        name ?? "Produkt #\(id)"
    }
}

struct SupplyService: Codable, Identifiable, Hashable {
    let id: Int
    let name: String?
    let description: String?
    let unit: String?
    let price_net: Double?

    var displayName: String {
        name ?? "Leistung #\(id)"
    }
}

struct DocumentDraft: Codable {
    let id: Int?
    let status: Int?
}

struct DocumentType: Codable, Identifiable, Hashable {
    let id: Int
    let name: String?
    let base_type: String?
}
