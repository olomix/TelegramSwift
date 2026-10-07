import Foundation
import SwiftSignalKit
import TelegramCore
import Postbox
import OpenSSLEncryption
import TelegramSystem
import ApiCredentials

func makeNetworkInitializationArguments(apiId: Int32, apiHash: String) -> NetworkInitializationArguments {
    let voipVersions = OngoingCallContext.versions(includeExperimental: true, includeReference: false).map { version, supportsVideo -> CallSessionManagerImplementationVersion in
        CallSessionManagerImplementationVersion(version: version, supportsVideo: supportsVideo)
    }
    let appData: Signal<Data?, NoError> = Signal { subscriber in
        subscriber.putNext(ApiEnvironment.appData)
        subscriber.putCompletion()
        return EmptyDisposable
    } |> runOn(.concurrentBackgroundQueue())

    return NetworkInitializationArguments(apiId: apiId, apiHash: apiHash, languagesCategory: ApiEnvironment.language, appVersion: ApiEnvironment.version, voipMaxLayer: OngoingCallContext.maxLayer, voipVersions: voipVersions, appData: appData, externalRequestVerificationStream: .single([:]), externalRecaptchaRequestVerification: { _, _ in return .complete() }, autolockDeadine: .single(nil), encryptionProvider: OpenSSLEncryptionProvider(), deviceModelName: deviceModelPretty(), useBetaFeatures: false, isICloudEnabled: false)
}

enum ApiCredentialsChecker {
    /// Asks Telegram for a login token with `values`; this has no side effects
    /// on the server (no SMS). Uses `accountManager` only to read the proxy
    /// settings. The throwaway account lives in a temporary folder that is
    /// deleted when the signal completes or is disposed.
    static func check(_ values: ApiCredentialsValues, accountManager: AccountManager<TelegramAccountManagerTypes>) -> Signal<ApiCredentialsCheckResult, NoError> {
        let rootPath = NSTemporaryDirectory() + "api-credentials-check-" + UUID().uuidString
        let networkArguments = makeNetworkInitializationArguments(apiId: values.apiId, apiHash: values.apiHash)

        let outcome: Signal<ApiCredentialsCheckOutcome, NoError> = accountWithId(accountManager: accountManager, networkArguments: networkArguments, id: generateAccountRecordId(), encryptionParameters: makeThrowawayEncryptionParameters(), supplementary: false, isSupportUser: false, rootPath: rootPath, beginWithTestingEnvironment: false, backupData: nil, auxiliaryMethods: telegramAccountAuxiliaryMethods, shouldKeepAutoConnection: false)
        |> mapToSignal { result -> Signal<ApiCredentialsCheckOutcome, NoError> in
            switch result {
            case .upgrading, .authorized:
                return .complete()
            case let .unauthorized(account):
                return TelegramEngineUnauthorized(account: account).auth.exportAuthTransferToken(accountManager: accountManager, otherAccountUserIds: [], syncContacts: false)
                |> map { _ -> ApiCredentialsCheckOutcome in
                    return .token
                }
                |> `catch` { _ -> Signal<ApiCredentialsCheckOutcome, NoError> in
                    return .single(.serverError)
                }
            }
        }
        |> take(1)
        |> timeout(ApiCredentialsCheckOutcome.checkTimeout, queue: .concurrentDefaultQueue(), alternate: .single(.timedOut))

        return outcome
        |> map { $0.result }
        |> afterDisposed {
            Queue.concurrentDefaultQueue().async {
                try? FileManager.default.removeItem(atPath: rootPath)
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
