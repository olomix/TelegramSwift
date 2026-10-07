import Foundation

/// Why a field on the credentials screen is marked as wrong.
public enum ApiCredentialsFieldProblem: Equatable {
    case missing
    case malformed
    case rejected

    /// Problems found without asking the server; empty when both values parse.
    public static func formatProblems(apiId: String, apiHash: String) -> [ApiCredentialsField: ApiCredentialsFieldProblem] {
        guard case let .failure(error) = ApiCredentialsValues.validate(apiId: apiId, apiHash: apiHash) else {
            return [:]
        }
        let inputs: [ApiCredentialsField: String] = [.apiId: apiId, .apiHash: apiHash]
        var problems: [ApiCredentialsField: ApiCredentialsFieldProblem] = [:]
        for field in error.invalidFields {
            let isBlank = inputs[field]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
            problems[field] = isBlank ? .missing : .malformed
        }
        return problems
    }

    /// The server cannot tell which value is wrong, so both fields are marked.
    public static let rejectedByServer: [ApiCredentialsField: ApiCredentialsFieldProblem] = [.apiId: .rejected, .apiHash: .rejected]
}
