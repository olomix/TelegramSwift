import Foundation
import MtProtoKit
import TelegramCore
import MTProtoRustEngine

/// Supplies the Rust MTProto engine in the app and in app extensions alike.
/// Every other refusal of `RustNetworkEngineFactory` still falls back to MtProtoKit.
struct ExtensionAllowingRustEngineFactory: NetworkEngineFactory {
    private let base = RustNetworkEngineFactory()

    func makeEngine(context: MTContext, isAppExtension: Bool) -> NetworkEngine? {
        // Upstream declines extensions for the iOS notification-service memory
        // budget; the macOS Share extension has no such limit.
        return base.makeEngine(context: context, isAppExtension: false)
    }

    var supportsWebProxy: Bool {
        return base.supportsWebProxy
    }
}
