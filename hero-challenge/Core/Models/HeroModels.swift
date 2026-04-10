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

struct ProjectTypesResponse: Decodable {
    let project_types: [ProjectType]
}

// MARK: - Domain Models

struct ProjectMatch: Codable, Identifiable, Hashable {
    let id: Int
    let name: String?
    let volume: Double?
    let project_nr: String?
    let customer: Customer?
    let contact: Contact?
    let current_project_match_status: ProjectMatchStatus?

    var displayName: String {
        if let name, !name.isEmpty { return name }
        if let customer { return customer.displayName }
        return "Projekt #\(id)"
    }
}

struct ProjectMatchStatus: Codable, Hashable {
    let name: String?
}

struct Customer: Codable, Identifiable, Hashable {
    let id: Int
    let first_name: String?
    let last_name: String?
    let company_name: String?
    let email: String?
    let phone_home: String?
    let phone_mobile: String?
    let address: Address?

    var displayName: String {
        if let company_name, !company_name.isEmpty { return company_name }
        let parts = [first_name, last_name].compactMap { $0 }.filter { !$0.isEmpty }
        if !parts.isEmpty { return parts.joined(separator: " ") }
        return "Kontakt #\(id)"
    }
}

typealias Contact = Customer

struct Address: Codable, Hashable {
    let street: String?
    let city: String?
    let zipcode: String?
    let country: Country?

    var displayString: String {
        [street, [zipcode, city].compactMap { $0 }.joined(separator: " ")]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

struct Country: Codable, Hashable {
    let id: Int?
    let name: String?
}

struct SupplyProductVersion: Codable, Identifiable, Hashable {
    let product_id: String?
    let nr: String?
    let base_price: Double?
    let list_price: Double?
    let vat_percent: Double?
    let internal_identifier: String?
    let base_data: SupplyProductBaseData?

    /// API returns `id: null` for product versions — use product_id as stable identifier
    var id: String { product_id ?? nr ?? UUID().uuidString }

    var displayName: String {
        base_data?.name ?? nr ?? "Produkt"
    }

    var unit: String? { base_data?.unit_type }
    var price_net: Double? { base_price }

    private enum CodingKeys: String, CodingKey {
        case product_id, nr, base_price, list_price, vat_percent, internal_identifier, base_data
    }
}

struct SupplyProductBaseData: Codable, Hashable {
    let name: String?
    let description: String?
    let unit_type: String?
    let manufacturer: String?
    let ean: String?
}

struct SupplyService: Codable, Identifiable, Hashable {
    let id: Int
    let name: String?
    let description: String?
    let unit_type: String?
    let net_price_per_unit: Double?
    let vat_percent: Double?
    let nr: String?

    var displayName: String {
        name ?? "Leistung #\(id)"
    }
}

struct DocumentDraft: Codable {
    let id: Int?
    let customer_document_id: Int?
    let status_code: Int?
    let nr: String?
}

struct DocumentType: Codable, Identifiable, Hashable {
    let id: Int
    let name: String?
    let base_type: String?
}

struct ProjectType: Codable, Identifiable, Hashable {
    let id: Int
    let name: String?
    let project_status_steps: [ProjectStatusStep]?
}

struct ProjectStatusStep: Codable, Identifiable, Hashable {
    let id: Int
    let is_active: Bool?
    let name: String?
}

// MARK: - File Upload

struct FileUpload: Codable {
    let uuid: String?
    let url: String?
    let filename: String?
}

struct FileUploadResponse: Decodable {
    let upload_image: FileUpload
}

// MARK: - Logbook / History

struct HistoryEntry: Codable {
    let id: Int?
}

struct AddLogbookEntryResponse: Decodable {
    let add_logbook_entry: HistoryEntry
}
