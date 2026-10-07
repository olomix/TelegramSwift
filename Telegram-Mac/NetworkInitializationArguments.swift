import Foundation
import SwiftSignalKit
import TelegramCore
import OpenSSLEncryption
import TelegramSystem
import ApiCredentials

func makeNetworkInitializationArguments(_ credentials: ApiCredentialsValues) -> NetworkInitializationArguments {
    let voipVersions = OngoingCallContext.versions(includeExperimental: true, includeReference: false).map { version, supportsVideo -> CallSessionManagerImplementationVersion in
        CallSessionManagerImplementationVersion(version: version, supportsVideo: supportsVideo)
    }
    let appData: Signal<Data?, NoError> = Signal { subscriber in
        subscriber.putNext(ApiEnvironment.appData)
        subscriber.putCompletion()
        return EmptyDisposable
    } |> runOn(.concurrentBackgroundQueue())

    return NetworkInitializationArguments(apiId: credentials.apiId, apiHash: credentials.apiHash, languagesCategory: ApiEnvironment.language, appVersion: ApiEnvironment.version, voipMaxLayer: OngoingCallContext.maxLayer, voipVersions: voipVersions, appData: appData, externalRequestVerificationStream: .single([:]), externalRecaptchaRequestVerification: { _, _ in return .complete() }, autolockDeadine: .single(nil), encryptionProvider: OpenSSLEncryptionProvider(), deviceModelName: deviceModelPretty(), useBetaFeatures: false, isICloudEnabled: false)
}
