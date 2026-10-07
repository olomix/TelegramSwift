import Foundation

public enum ApiCredentialsField: CaseIterable {
    case apiId
    case apiHash
}

public struct ApiCredentialsFormatError: Error, Equatable {
    public let invalidFields: Set<ApiCredentialsField>
}

/// The api_id / api_hash pair from my.telegram.org.
public struct ApiCredentialsValues: Codable, Equatable {
    public let apiId: Int32
    public let apiHash: String

    public init(apiId: Int32, apiHash: String) {
        self.apiId = apiId
        self.apiHash = apiHash
    }

    /// Parses user input. Whitespace around either value is ignored and the
    /// hash is normalized to lower case. Fails with every malformed field.
    public static func validate(apiId: String, apiHash: String) -> Result<ApiCredentialsValues, ApiCredentialsFormatError> {
        let id = parseApiId(apiId)
        let hash = parseApiHash(apiHash)
        guard let id = id, let hash = hash else {
            var invalid = Set<ApiCredentialsField>()
            if id == nil {
                invalid.insert(.apiId)
            }
            if hash == nil {
                invalid.insert(.apiHash)
            }
            return .failure(ApiCredentialsFormatError(invalidFields: invalid))
        }
        return .success(ApiCredentialsValues(apiId: id, apiHash: hash))
    }

    private static func parseApiId(_ input: String) -> Int32? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.allSatisfy({ $0.isASCII && $0.isNumber }), let id = Int32(trimmed), id > 0 else {
            return nil
        }
        return id
    }

    private static func parseApiHash(_ input: String) -> String? {
        let hash = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard hash.count == 32, hash.allSatisfy({ $0.isHexDigit && $0.isASCII }) else {
            return nil
        }
        return hash
    }
}
