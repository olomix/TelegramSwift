import Foundation
import SwiftSignalKit
import TelegramCore
import Postbox
import ApiCredentials
import TelegramApi
import MtProtoKit

enum ApiCredentialsChecker {
    /// Offline and FLOOD_WAIT are retried silently by the network layer, so
    /// they surface only as no answer within this time.
    private static let answerTimeout: TimeInterval = 15

    private static let checksFolder = NSTemporaryDirectory() + "api-credentials-check"

    /// Asks Telegram for a login token with `values`; this has no side effects
    /// on the server (no SMS). Uses `accountManager` only to read shared
    /// settings (proxy, localization). The throwaway account lives in a
    /// temporary folder that is deleted when the signal completes or is
    /// disposed.
    static func check(_ values: ApiCredentialsValues, accountManager: AccountManager<TelegramAccountManagerTypes>) -> Signal<ApiCredentialsCheckResult, NoError> {
        removeStaleCheckFolders()
        let rootPath = checksFolder + "/" + UUID().uuidString
        let networkArguments = makeNetworkInitializationArguments(values)

        return accountWithId(accountManager: accountManager, networkArguments: networkArguments, id: generateAccountRecordId(), encryptionParameters: makeThrowawayEncryptionParameters(), supplementary: false, isSupportUser: false, rootPath: rootPath, beginWithTestingEnvironment: false, backupData: nil, auxiliaryMethods: telegramAccountAuxiliaryMethods, shouldKeepAutoConnection: false)
        |> mapToSignal { result -> Signal<ApiCredentialsCheckResult, NoError> in
            switch result {
            case .upgrading, .authorized:
                return .complete()
            case let .unauthorized(account):
                // A new account's network stays paused until it is told to connect.
                account.shouldBeServiceTaskMaster.set(.single(.now))
                // Any answer, even a DC migration, means the values were accepted.
                return account.network.request(Api.functions.auth.exportLoginToken(apiId: values.apiId, apiHash: values.apiHash, exceptIds: []))
                |> map { _ -> ApiCredentialsCheckResult in
                    return .accepted
                }
                |> `catch` { error -> Signal<ApiCredentialsCheckResult, NoError> in
                    return .single(ApiCredentialsCheckResult(serverError: error.errorDescription))
                }
                // Holds the account until the request ends, then stops its connection.
                |> afterDisposed {
                    account.shouldBeServiceTaskMaster.set(.single(.never))
                }
            }
        }
        |> take(1)
        |> timeout(answerTimeout, queue: .concurrentDefaultQueue(), alternate: .single(.unreachable))
        |> afterDisposed {
            Queue.concurrentDefaultQueue().async {
                try? FileManager.default.removeItem(atPath: rootPath)
            }
        }
    }

    /// The released account's database can recreate its folder after the
    /// removal above, so leftovers from earlier checks are swept here.
    private static func removeStaleCheckFolders() {
        let fileManager = FileManager.default
        guard let names = try? fileManager.contentsOfDirectory(atPath: checksFolder) else {
            return
        }
        for name in names {
            let path = checksFolder + "/" + name
            let created = (try? fileManager.attributesOfItem(atPath: path))?[.creationDate] as? Date
            if let created = created, created.timeIntervalSinceNow < -2 * answerTimeout {
                try? fileManager.removeItem(atPath: path)
            }
        }
    }

    private static func makeThrowawayEncryptionParameters() -> ValueBoxEncryptionParameters {
        return ValueBoxEncryptionParameters(forceEncryptionIfNoSet: false, key: ValueBoxEncryptionParameters.Key(data: randomData(count: 32))!, salt: ValueBoxEncryptionParameters.Salt(data: randomData(count: 16))!)
    }

    private static func randomData(count: Int) -> Data {
        var data = Data(count: count)
        _ = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }
        return data
    }
}
