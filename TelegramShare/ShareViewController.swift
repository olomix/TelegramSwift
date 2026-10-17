//
//  ShareViewController.swift
//  TelegramShare
//
//  Created by keepcoder on 04/01/2017.
//  Copyright © 2017 Telegram. All rights reserved.
//

import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import ApiCredentials
import SwiftSignalKit
import ThemeSettings
import OpenSSLEncryption
import Localization
import TelegramSystem
import RLottie
import PasscodeCore
import MacPasscode

class ShareViewController: NSViewController {

    override var nibName: NSNib.Name? {
        return "ShareViewController"
    }
    
    
    
    private var contextValue: AuthorizedApplicationContext?
    private let context = Promise<AuthorizedApplicationContext?>()
    private let contextDisposable = MetaDisposable()
    
    private var passlock: SEPasslockController? = nil
    private var notice: SEUnauthorizedViewController? = nil
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        System.legacyMenu = false
        System.updateScaleFactor(NSScreen.main?.backingScaleFactor ?? 1)
        

        // Checked before touching the group: opening an account manager there
        // would create folders before the app has moved the old data in.
        guard let credentials = ApiEnvironment.storedCredentials else {
            showNotice(L10n.shareExtensionSetupDescription)
            return
        }

        guard let containerUrl = ApiEnvironment.containerURL else {
            return
        }
        initializeAccountManagement()

        let passcodeConfigured = MacPasscodeEnvironment.configureFromBundle(.appExtension, buildPrefix: ApiEnvironment.prefix)

        let rootPath = containerUrl.path
        let accountManager = ShareViewController.openAccountManager(basePath: rootPath + "/accounts-metadata")

        let logger = Logger(rootPath: containerUrl.path, basePath: containerUrl.path + "/logs")
        logger.logToConsole = false
        logger.logToFile = false
        Logger.setSharedLogger(logger)
        
        let themeSemaphore = DispatchSemaphore(value: 0)
        var themeSettings: ThemePaletteSettings = ThemePaletteSettings.defaultTheme
        _ = (themeSettingsView(accountManager: accountManager) |> take(1)).start(next: { settings in
            themeSettings = settings
            themeSemaphore.signal()
        })
        themeSemaphore.wait()
        
        var localization: LocalizationSettings? = nil
        let localizationSemaphore = DispatchSemaphore(value: 0)
        _ = (accountManager.transaction { transaction in
            localization = transaction.getSharedData(SharedDataKeys.localizationSettings)?.get(LocalizationSettings.self)
            localizationSemaphore.signal()
        }).start()
        localizationSemaphore.wait()
        
        if let localization = localization {
            applyShareUILocalization(localization)
        }
        
        telegramUpdateTheme(updateTheme(with: themeSettings), window: nil, animated: false)

        guard passcodeConfigured else {
            showNotice(PasscodeTexts.shareUnavailable)
            return
        }

        let unlock = ReadOnlyUnlock(directory: containerUrl, credentials: CoreLaunchCredentialStore())
        do {
            switch try unlock.state() {
            case .ready(needsPasscode: false):
                launchExtension(accountManager: accountManager, databaseKey: try unlock.unlock(code: nil), credentials: credentials)
            case .ready(needsPasscode: true):
                showPasslock(unlock: unlock, accountManager: accountManager, credentials: credentials)
            case .needsAppLaunch:
                showNotice(PasscodeTexts.shareFinishUpdate)
            case .credentialLost:
                showNotice(PasscodeTexts.shareUnavailable)
            }
        } catch {
            Logger.shared.log("Share", "local data unlock failed: \(error)")
            showNotice(PasscodeTexts.shareUnavailable)
        }
    }

    // MARK: Passcode

    /// Key derivation is slow on purpose; keep it off the main thread.
    private static let passcodeQueue = Queue(name: "com.korthane.telex.share.passcode")

    private static func openAccountManager(basePath: String) -> AccountManager<TelegramAccountManagerTypes> {
        return AccountManager<TelegramAccountManagerTypes>(basePath: basePath, isTemporary: false, isReadOnly: true, useCaches: true, removeDatabaseOnError: true, accessChallenge: AccountManagerAccessChallenge(
            prepare: { _ in
                let _ = try PasscodeEnvironment.shared.sharedAccessGroup()
                PasscodeCredentialStore.shared.configureLock(directory: basePath)
            },
            // The app owns the stored state; a differing answer here would
            // make the account manager rewrite it.
            resolve: { current, _ in
                return current
            },
            finishInitialization: {}
        ))
    }

    private func showPasslock(unlock: ReadOnlyUnlock, accountManager: AccountManager<TelegramAccountManagerTypes>, credentials: ApiCredentialsValues) {
        self.passlock = SEPasslockController(checkNextValue: { [weak self] passcode, completion in
            ShareViewController.passcodeQueue.async {
                let result = Result { try unlock.unlock(code: passcode) }
                Queue.mainQueue().async {
                    guard let self else {
                        return
                    }
                    switch result {
                    case let .success(databaseKey):
                        self.launchExtension(accountManager: accountManager, databaseKey: databaseKey, credentials: credentials)
                    case let .failure(error):
                        if case ReadOnlyUnlockError.needsAppLaunch = error {
                            self.showNotice(PasscodeTexts.shareFinishUpdate)
                            return
                        }
                        switch PasscodeCheckFailure(error) {
                        case .invalidCode:
                            completion(nil)
                        case let .cooldown(seconds):
                            completion(PasscodeTexts.cooldown(seconds: seconds))
                        case .unavailable:
                            Logger.shared.log("Share", "passcode check failed: \(error)")
                            self.showNotice(PasscodeTexts.shareUnavailable)
                        }
                    }
                }
            }
        }, cancelImpl: { [weak self] in
            self?.cancelRequest()
        })

        self.passlock!.view.frame = self.view.bounds
        self.view.addSubview(self.passlock!.view)
    }

    private func showNotice(_ text: String) {
        if let passlock = self.passlock {
            passlock.view.removeFromSuperview()
            self.passlock = nil
        }
        let controller = SEUnauthorizedViewController(description: text, cancelImpl: { [weak self] in
            self?.cancelRequest()
        })
        controller.view.frame = self.view.bounds
        self.view.addSubview(controller.view)
        self.notice = controller
    }

    private func cancelRequest() {
        let cancelError = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError, userInfo: nil)
        self.extensionContext?.cancelRequest(withError: cancelError)
    }

    private func launchExtension(accountManager: AccountManager<TelegramAccountManagerTypes>, databaseKey: DatabaseKey, credentials: ApiCredentialsValues) {
        let encryptionParameters = ValueBoxEncryptionParameters(databaseKey: databaseKey)

        let extensionContext = self.extensionContext!

        let containerUrl = ApiEnvironment.containerURL!
        
        let rootPath = containerUrl.path

        let appData: Signal<Data?, NoError> = Signal { subscriber in
            subscriber.putNext(ApiEnvironment.appData)
            subscriber.putCompletion()
            return EmptyDisposable
        } |> runOn(.concurrentBackgroundQueue())
        
        var useBetaFeatures: Bool = false
        #if BETA || DEBUG
        useBetaFeatures = false
        #endif
        
        let networkArguments = NetworkInitializationArguments(apiId: credentials.apiId, apiHash: credentials.apiHash, languagesCategory: ApiEnvironment.language, appVersion: ApiEnvironment.version, voipMaxLayer: 90, voipVersions: [], appData: appData, externalRequestVerificationStream: .single([:]), externalRecaptchaRequestVerification: { _, _ in return .complete() }, autolockDeadine: .single(nil), encryptionProvider: OpenSSLEncryptionProvider(), deviceModelName: deviceModelPretty(), useBetaFeatures: useBetaFeatures, isICloudEnabled: false, networkEngineFactory: ExtensionAllowingRustEngineFactory())
        
        let sharedContext = SharedAccountContext(accountManager: accountManager, networkArguments: networkArguments, rootPath: rootPath, encryptionParameters: encryptionParameters, displayUpgradeProgress: { _ in })
        
      

        
        let rawAccounts = sharedContext.activeAccounts
            |> map { _, accounts, _ -> [Account] in
                return accounts.map({ $0.1 })
        }
        let _ = (sharedAccountInfos(accountManager: sharedContext.accountManager, accounts: rawAccounts)
            |> deliverOn(Queue())).start(next: { infos in
                storeAccountsData(rootPath: rootPath, accounts: infos)
            })
        
        
        
        let readyDisposable = MetaDisposable()
        _ = (self.context.get() |> mapToSignal { context -> Signal<AuthorizedApplicationContext?, NoError> in
            return .single(context)
            
            } |> deliverOnMainQueue).start(next: { context in
                assert(Queue.mainQueue().isCurrent())
                
                if let context = context {
                    context.rootController.view.frame = self.view.bounds
                    
                    readyDisposable.set((context.rootController.ready.get() |> take(1)).start(next: { [weak context] _ in
                        guard let context = context else { return }
                        if let contextValue = self.contextValue {
                            performSubviewRemoval(contextValue.rootController.view, animated: false)
                        }
                        let hasPrevious = self.contextValue != nil
                        self.contextValue = context
                        if let passlock = self.passlock, passlock.isLoaded() {
                            performSubviewRemoval(passlock.view, animated: true)
                            self.passlock = nil
                        }
                        self.view.addSubview(context.rootController.view, positioned: .below, relativeTo: self.view.subviews.first)
                        if hasPrevious {
                            context.rootController.view.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                        }
                        
                    }))
                }
            })
        
        
        self.context.set(sharedContext.activeAccounts
            |> map { primary, _, _ -> Account? in
                return primary
            }
            |> distinctUntilChanged(isEqual: { lhs, rhs in
                if lhs !== rhs {
                    return false
                }
                return true
            })
            |> map { account in
                if let account = account {
                    let context = AccountContext(sharedContext: sharedContext, window: Window(contentRect: NSZeroRect, styleMask: [], backing: NSWindow.BackingStoreType.buffered, defer: true), account: account)
                    return AuthorizedApplicationContext(context: context, shareContext: extensionContext)
                    
                } else {
                    return nil
                }
            })
    }

}

