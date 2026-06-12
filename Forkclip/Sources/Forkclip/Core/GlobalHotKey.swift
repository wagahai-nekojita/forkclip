import Carbon
import Combine
import Foundation

struct GlobalHotKey: Equatable {
    static let quickPanelDefault = GlobalHotKey(
        keyCode: UInt32(kVK_ANSI_V),
        modifiers: UInt32(cmdKey | optionKey | controlKey),
        signature: 0x46434B48,
        id: 1,
        displayName: "Control-Option-Command-V"
    )

    let keyCode: UInt32
    let modifiers: UInt32
    let signature: OSType
    let id: UInt32
    let displayName: String
}

enum GlobalHotKeyRegistrationState: Equatable {
    case notRegistered
    case registered
    case failed(status: OSStatus)

    var isRegistered: Bool {
        if case .registered = self {
            return true
        }
        return false
    }
}

protocol GlobalHotKeyRegistering: AnyObject {
    func register(
        _ hotKey: GlobalHotKey,
        handler: @escaping @MainActor () -> Void
    ) -> GlobalHotKeyRegistrationState
    func unregister()
}

@MainActor
final class GlobalHotKeyController: ObservableObject {
    @Published private(set) var registrationState: GlobalHotKeyRegistrationState = .notRegistered

    let hotKey: GlobalHotKey
    private let registrar: GlobalHotKeyRegistering
    private let handler: @MainActor () -> Void

    init(
        hotKey: GlobalHotKey = .quickPanelDefault,
        registrar: GlobalHotKeyRegistering = CarbonGlobalHotKeyRegistrar(),
        handler: @escaping @MainActor () -> Void
    ) {
        self.hotKey = hotKey
        self.registrar = registrar
        self.handler = handler
    }

    func register() {
        registrationState = registrar.register(hotKey) { [weak self] in
            self?.handler()
        }

        switch registrationState {
        case .registered:
            AppLogger.app.notice("Global hotkey registered: \(self.hotKey.displayName, privacy: .public)")
        case .failed(let status):
            AppLogger.app.error("Global hotkey registration failed with OSStatus \(status, privacy: .public)")
        case .notRegistered:
            AppLogger.app.notice("Global hotkey not registered.")
        }
    }

    func unregister() {
        registrar.unregister()
        registrationState = .notRegistered
    }
}

final class CarbonGlobalHotKeyRegistrar: GlobalHotKeyRegistering {
    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private var registeredHotKeyID: EventHotKeyID?
    private var handler: (@MainActor () -> Void)?

    func register(
        _ hotKey: GlobalHotKey,
        handler: @escaping @MainActor () -> Void
    ) -> GlobalHotKeyRegistrationState {
        unregister()

        self.handler = handler
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            carbonGlobalHotKeyHandler,
            1,
            &eventSpec,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &eventHandlerRef
        )
        guard installStatus == noErr else {
            unregister()
            return .failed(status: installStatus)
        }

        let hotKeyID = EventHotKeyID(signature: hotKey.signature, id: hotKey.id)
        var registeredRef: EventHotKeyRef?
        let registerStatus = RegisterEventHotKey(
            hotKey.keyCode,
            hotKey.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &registeredRef
        )
        guard registerStatus == noErr else {
            unregister()
            return .failed(status: registerStatus)
        }

        registeredHotKeyID = hotKeyID
        hotKeyRef = registeredRef
        return .registered
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }

        registeredHotKeyID = nil
        handler = nil
    }

    fileprivate func handleEvent(_ event: EventRef?) -> OSStatus {
        guard let event,
              let registeredHotKeyID else {
            return noErr
        }

        var eventHotKeyID = EventHotKeyID()
        let status = withUnsafeMutablePointer(to: &eventHotKeyID) { pointer in
            GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                UnsafeMutableRawPointer(pointer)
            )
        }
        guard status == noErr else {
            return status
        }

        guard eventHotKeyID.signature == registeredHotKeyID.signature,
              eventHotKeyID.id == registeredHotKeyID.id else {
            return noErr
        }

        let handler = self.handler
        Task { @MainActor in
            handler?()
        }
        return noErr
    }

    deinit {
        unregister()
    }
}

private let carbonGlobalHotKeyHandler: EventHandlerUPP = { _, event, userData in
    guard let userData else {
        return noErr
    }

    let registrar = Unmanaged<CarbonGlobalHotKeyRegistrar>
        .fromOpaque(userData)
        .takeUnretainedValue()
    return registrar.handleEvent(event)
}
