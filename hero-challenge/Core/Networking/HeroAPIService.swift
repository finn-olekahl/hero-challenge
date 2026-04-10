import Foundation

// MARK: - HERO API Service

/// Central service for all HERO GraphQL API interactions.
final class HeroAPIService: Sendable {
    private let client: GraphQLClient

    init(client: GraphQLClient) {
        self.client = client
    }

    // MARK: - Projects (Aufträge)

    func fetchProjects(search: String? = nil, first: Int = 50) async throws -> [ProjectMatch] {
        var vars: [String: AnyCodable] = ["first": AnyCodable(first)]
        if let search { vars["search"] = AnyCodable(search) }

        let result: ProjectMatchesResponse = try await client.perform(
            query: Queries.projectMatches,
            variables: vars,
            responseType: ProjectMatchesResponse.self
        )
        return result.project_matches
    }

    func fetchProject(id: Int) async throws -> ProjectMatch {
        let result: ProjectMatchResponse = try await client.perform(
            query: Queries.projectMatch,
            variables: ["project_match_id": AnyCodable(id)],
            responseType: ProjectMatchResponse.self
        )
        return result.project_match
    }

    // MARK: - Project Types (Projekttypen / Pipeline)

    func fetchProjectTypes() async throws -> [ProjectType] {
        let result: ProjectTypesResponse = try await client.perform(
            query: Queries.projectTypes,
            responseType: ProjectTypesResponse.self
        )
        return result.project_types
    }

    // MARK: - Supply Products (Artikelstamm)

    func fetchSupplyProducts(search: String? = nil, first: Int = 50) async throws -> [SupplyProductVersion] {
        var vars: [String: AnyCodable] = ["first": AnyCodable(first)]
        if let search { vars["search"] = AnyCodable(search) }

        let result: SupplyProductVersionsResponse = try await client.perform(
            query: Queries.supplyProductVersions,
            variables: vars,
            responseType: SupplyProductVersionsResponse.self
        )
        return result.supply_product_versions
    }

    // MARK: - Supply Services (Leistungstypen)

    func fetchSupplyServices(search: String? = nil, first: Int = 50) async throws -> [SupplyService] {
        var vars: [String: AnyCodable] = ["first": AnyCodable(first)]
        if let search { vars["search"] = AnyCodable(search) }

        let result: SupplyServicesResponse = try await client.perform(
            query: Queries.supplyServices,
            variables: vars,
            responseType: SupplyServicesResponse.self
        )
        return result.supply_services
    }

    // MARK: - Document Creation (Angebot erstellen)

    func createDocument(
        actions: [[String: AnyCodable]],
        projectMatchId: Int,
        documentTypeId: Int
    ) async throws -> DocumentDraft {
        let input: [String: AnyCodable] = [
            "project_match_id": AnyCodable(projectMatchId),
            "document_type_id": AnyCodable(documentTypeId)
        ]

        let result: CreateDocumentResponse = try await client.perform(
            query: Mutations.createDocument,
            variables: [
                "input": AnyCodable(input),
                "actions": AnyCodable(actions)
            ],
            responseType: CreateDocumentResponse.self
        )
        return result.create_document
    }

    // MARK: - Document Types

    func fetchDocumentTypes(baseTypes: [String]? = nil) async throws -> [DocumentType] {
        var vars: [String: AnyCodable] = [:]
        if let baseTypes {
            vars["base_types"] = AnyCodable(baseTypes)
        }

        let result: DocumentTypesResponse = try await client.perform(
            query: Queries.documentTypes,
            variables: vars.isEmpty ? nil : vars,
            responseType: DocumentTypesResponse.self
        )
        return result.document_types
    }

    // MARK: - Contacts

    func fetchContacts(search: String? = nil, first: Int = 50) async throws -> [Contact] {
        var vars: [String: AnyCodable] = ["first": AnyCodable(first)]
        if let search { vars["search"] = AnyCodable(search) }

        let result: ContactsResponse = try await client.perform(
            query: Queries.contacts,
            variables: vars,
            responseType: ContactsResponse.self
        )
        return result.contacts
    }

    // MARK: - File Upload (REST)

    /// Uploads an image via the HERO REST upload endpoint.
    /// Returns the UUID of the uploaded file.
    func uploadImage(_ imageData: Data, filename: String) async throws -> String {
        // The REST upload endpoint is always at /api/external/v9/upload on the same host
        guard var components = URLComponents(url: client.baseURL, resolvingAgainstBaseURL: false) else {
            throw GraphQLError.invalidURL
        }
        components.path = "/api/external/v9/upload"
        guard let uploadURL = components.url else {
            throw GraphQLError.invalidURL
        }

        let boundary = UUID().uuidString
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        // Reuse the token from the GraphQL client
        request.setValue("Bearer \(client.token)", forHTTPHeaderField: "Authorization")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw GraphQLError.httpError(statusCode: http.statusCode, body: "Upload fehlgeschlagen (HTTP \(http.statusCode))")
        }

        // Parse the UUID from the response
        let uploadResponse = try JSONDecoder().decode(RESTUploadResponse.self, from: data)
        guard let uuid = uploadResponse.uuid else {
            throw GraphQLError.noData
        }

        print("📤 [Upload] Image uploaded: \(filename) → UUID: \(uuid)")
        return uuid
    }

    /// Links a previously uploaded image to a project or field service job via GraphQL.
    func linkImageToTarget(fileUploadUUID: String, target: String, targetId: Int) async throws -> FileUpload {
        let result: FileUploadResponse = try await client.perform(
            query: Mutations.uploadImage,
            variables: [
                "file_upload_uuid": AnyCodable(fileUploadUUID),
                "target": AnyCodable(target),
                "target_id": AnyCodable(targetId)
            ],
            responseType: FileUploadResponse.self
        )
        return result.upload_image
    }

    // MARK: - Logbook (Bautagebuch)

    /// Adds a logbook entry (Arbeitsbericht / Baustellenbericht) to a project.
    func addLogbookEntry(
        target: String,
        targetId: Int,
        text: String
    ) async throws -> HistoryEntry {
        let entry: [String: AnyCodable] = [
            "target": AnyCodable(target),
            "target_id": AnyCodable(targetId),
            "custom_text": AnyCodable(text)
        ]

        let result: AddLogbookEntryResponse = try await client.perform(
            query: Mutations.addLogbookEntry,
            variables: ["logbook_entry": AnyCodable(entry)],
            responseType: AddLogbookEntryResponse.self
        )
        return result.add_logbook_entry
    }
}

// MARK: - REST Upload Response

private struct RESTUploadResponse: Decodable {
    let uuid: String?
    let filename: String?
}

// MARK: - GraphQL Queries

private enum Queries {
    static let projectMatches = """
    query ProjectMatches($search: String, $first: Int) {
        project_matches(search: $search, first: $first, orderBy: "id") {
            id
            name
            volume
            project_nr
            customer {
                id
                first_name
                last_name
                company_name
            }
            contact {
                id
                first_name
                last_name
            }
            current_project_match_status {
                name
            }
        }
    }
    """

    static let projectMatch = """
    query ProjectMatch($project_match_id: Int) {
        project_match(project_match_id: $project_match_id) {
            id
            name
            volume
            project_nr
            customer {
                id
                first_name
                last_name
                company_name
                address {
                    street
                    city
                    zipcode
                    country {
                        id
                        name
                    }
                }
            }
            contact {
                id
                first_name
                last_name
            }
            current_project_match_status {
                name
            }
        }
    }
    """

    static let projectTypes = """
    query ProjectTypes {
        project_types {
            id
            name
            project_status_steps {
                id
                is_active
                name
            }
        }
    }
    """

    static let supplyProductVersions = """
    query SupplyProductVersions($search: String, $first: Int) {
        supply_product_versions(search: $search, first: $first) {
            product_id
            nr
            base_price
            list_price
            vat_percent
            internal_identifier
            base_data {
                name
                description
                unit_type
                manufacturer
                ean
            }
        }
    }
    """

    static let supplyServices = """
    query SupplyServices($search: String, $first: Int) {
        supply_services(search: $search, first: $first) {
            id
            name
            description
            unit_type
            net_price_per_unit
            vat_percent
            nr
        }
    }
    """

    static let documentTypes = """
    query DocumentTypes($base_types: [String]) {
        document_types(base_types: $base_types) {
            id
            name
            base_type
        }
    }
    """

    static let contacts = """
    query Contacts($search: String, $first: Int) {
        contacts(search: $search, first: $first) {
            id
            first_name
            last_name
            company_name
            email
            phone_mobile
            address {
                street
                city
                zipcode
                country {
                    id
                    name
                }
            }
        }
    }
    """
}

// MARK: - GraphQL Mutations

private enum Mutations {
    static let createDocument = """
    mutation CreateDocument(
        $input: Documents_CreateDocumentInput!,
        $actions: [Documents_DocumentBuilderActionInput!]!
    ) {
        create_document(input: $input, actions: $actions) {
            id
            customer_document_id
            status_code
            nr
        }
    }
    """

    static let uploadImage = """
    mutation UploadImage(
        $file_upload_uuid: String!,
        $target: LinkTargetEnum,
        $target_id: Int!
    ) {
        upload_image(
            file_upload_uuid: $file_upload_uuid,
            target: $target,
            target_id: $target_id
        ) {
            uuid
            url
            filename
        }
    }
    """

    static let addLogbookEntry = """
    mutation AddLogbookEntry($logbook_entry: LogbookEntryInput) {
        add_logbook_entry(logbook_entry: $logbook_entry) {
            id
        }
    }
    """
}
