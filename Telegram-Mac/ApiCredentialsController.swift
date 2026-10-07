import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox
import ApiCredentials

private let _id_api_id = InputDataIdentifier("_id_api_id")
private let _id_api_hash = InputDataIdentifier("_id_api_hash")

private struct ApiCredentialsState: Equatable {
    var apiId: String
    var apiHash: String
    var problems: [ApiCredentialsField: ApiCredentialsFieldProblem]
}

private func fieldError(_ problem: ApiCredentialsFieldProblem?, field: ApiCredentialsField) -> InputDataValueError? {
    guard let problem = problem else {
        return nil
    }
    let description: String
    switch problem {
    case .missing:
        description = strings().apiCredentialsErrorRequired
    case .malformed:
        switch field {
        case .apiId:
            description = strings().apiCredentialsErrorApiIdFormat
        case .apiHash:
            description = strings().apiCredentialsErrorApiHashFormat
        }
    case .rejected:
        description = strings().apiCredentialsErrorRejected
    }
    return InputDataValueError(description: description, target: .data)
}

private func apiCredentialsEntries(state: ApiCredentialsState) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []
    var sectionId: Int32 = 0
    var index: Int32 = 0

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    entries.append(.input(sectionId: sectionId, index: index, value: .string(state.apiId), error: fieldError(state.problems[.apiId], field: .apiId), identifier: _id_api_id, mode: .plain, data: InputDataRowData(viewType: .singleItem, outlinesError: true), placeholder: nil, inputPlaceholder: strings().apiCredentialsApiIdPlaceholder, filter: { $0 }, limit: 12))
    index += 1

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    entries.append(.input(sectionId: sectionId, index: index, value: .string(state.apiHash), error: fieldError(state.problems[.apiHash], field: .apiHash), identifier: _id_api_hash, mode: .plain, data: InputDataRowData(viewType: .singleItem, outlinesError: true), placeholder: nil, inputPlaceholder: strings().apiCredentialsApiHashPlaceholder, filter: { $0 }, limit: 64))
    index += 1

    entries.append(.desc(sectionId: sectionId, index: index, text: .markdown(strings().apiCredentialsHint, linkHandler: { link in
        if let url = URL(string: link) {
            NSWorkspace.shared.open(url)
        }
    }), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
    index += 1

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    return entries
}

/// The api_id / api_hash form. Save checks the values with Telegram, writes
/// them to the credentials file and then calls `onSaved`.
func ApiCredentialsController(accountManager: AccountManager<TelegramAccountManagerTypes>, onSaved: @escaping (ApiCredentialsValues) -> Void) -> InputDataController {
    let stored = ApiEnvironment.storedCredentials
    let initialState = ApiCredentialsState(apiId: stored.map { "\($0.apiId)" } ?? "", apiHash: stored?.apiHash ?? "", problems: [:])

    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((inout ApiCredentialsState) -> Void) -> Void = { f in
        statePromise.set(stateValue.modify { state in
            var state = state
            f(&state)
            return state
        })
    }

    let checkDisposable = MetaDisposable()
    weak var weakController: InputDataController?

    let save: (ApiCredentialsValues) -> Void = { values in
        guard let fileURL = ApiEnvironment.credentialsFileURL else {
            return
        }
        do {
            try ApiCredentialsStore(fileURL: fileURL).save(values)
        } catch {
            alert(for: weakController?.window ?? mainWindow, info: error.localizedDescription)
            return
        }
        onSaved(values)
    }

    var check: ((ApiCredentialsValues) -> Void)!
    check = { values in
        let window = weakController?.window ?? mainWindow
        checkDisposable.set((showModalProgress(signal: ApiCredentialsChecker.check(values, accountManager: accountManager), for: window) |> deliverOnMainQueue).start(next: { result in
            switch result {
            case .accepted:
                save(values)
            case .rejected:
                updateState { $0.problems = ApiCredentialsFieldProblem.rejectedByServer }
            case .unreachable:
                verifyAlert_button(for: window, information: strings().apiCredentialsUnreachableText, ok: strings().apiCredentialsUnreachableTryAgain, option: strings().apiCredentialsUnreachableSaveAnyway, successHandler: { choice in
                    switch choice {
                    case .basic:
                        check(values)
                    case .thrid:
                        save(values)
                    }
                })
            }
        }))
    }

    let controller = InputDataController(dataSignal: statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: apiCredentialsEntries(state: state))
    }, title: strings().apiCredentialsTitle, validateData: { _ in
        let state = stateValue.with { $0 }
        let problems = ApiCredentialsFieldProblem.formatProblems(apiId: state.apiId, apiHash: state.apiHash)
        if !problems.isEmpty {
            updateState { $0.problems = problems }
            var fails: [InputDataIdentifier: InputDataValidationFailAction] = [:]
            if problems[.apiId] != nil {
                fails[_id_api_id] = .shake
            }
            if problems[.apiHash] != nil {
                fails[_id_api_hash] = .shake
            }
            return .fail(.fields(fails))
        }
        if case let .success(values) = ApiCredentialsValues.validate(apiId: state.apiId, apiHash: state.apiHash) {
            check(values)
        }
        return .fail(.none)
    }, updateDatas: { data in
        updateState { state in
            let apiId = data[_id_api_id]?.stringValue ?? ""
            let apiHash = data[_id_api_hash]?.stringValue ?? ""
            if apiId != state.apiId {
                state.problems.removeValue(forKey: .apiId)
            }
            if apiHash != state.apiHash {
                state.problems.removeValue(forKey: .apiHash)
            }
            state.apiId = apiId
            state.apiHash = apiHash
        }
        return .none
    }, afterDisappear: {
        checkDisposable.dispose()
    }, identifier: "api-credentials", doneString: { strings().apiCredentialsSave })

    weakController = controller
    return controller
}

/// Credentials form that cannot be dismissed until values are saved, like
/// `ColdStartPasslockController`.
final class ApiCredentialsBlockingModalController: InputDataModalController {
    override var closable: Bool {
        return false
    }

    override func escapeKeyAction() -> KeyHandlerResult {
        return .invoked
    }
}

func ApiCredentialsBlockingModal(accountManager: AccountManager<TelegramAccountManagerTypes>, onSaved: @escaping (ApiCredentialsValues) -> Void) -> ModalViewController {
    var close: (() -> Void)?
    let controller = ApiCredentialsController(accountManager: accountManager, onSaved: { values in
        close?()
        onSaved(values)
    })
    let modalInteractions = ModalInteractions(acceptTitle: strings().apiCredentialsSave, accept: { [weak controller] in
        controller?.validateInputValues()
    }, singleButton: true)
    let modal = ApiCredentialsBlockingModalController(controller, modalInteractions: modalInteractions, size: NSMakeSize(340, 300))
    close = { [weak modal] in
        modal?.close()
    }
    return modal
}
