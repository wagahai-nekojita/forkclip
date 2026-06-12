#if canImport(XCTest)
import XCTest
@testable import Forkclip

@MainActor
final class GlobalHotKeyControllerTests: XCTestCase {
    func testRegisterStoresRegisteredStateAndInvokesHandler() {
        let registrar = FakeGlobalHotKeyRegistrar()
        var invocationCount = 0
        let controller = GlobalHotKeyController(registrar: registrar) {
            invocationCount += 1
        }

        controller.register()
        registrar.fire()

        XCTAssertEqual(controller.registrationState, .registered)
        XCTAssertEqual(registrar.registeredHotKeys, [.quickPanelDefault])
        XCTAssertEqual(invocationCount, 1)
    }

    func testRegistrationFailureRecordsStatusWithoutHandler() {
        let registrar = FakeGlobalHotKeyRegistrar()
        registrar.nextResult = .failed(status: -9878)
        var invocationCount = 0
        let controller = GlobalHotKeyController(registrar: registrar) {
            invocationCount += 1
        }

        controller.register()
        registrar.fire()

        XCTAssertEqual(controller.registrationState, .failed(status: -9878))
        XCTAssertEqual(registrar.registeredHotKeys, [.quickPanelDefault])
        XCTAssertEqual(invocationCount, 0)
    }

    func testRegistrationCanRecoverAfterFailure() {
        let registrar = FakeGlobalHotKeyRegistrar()
        registrar.nextResult = .failed(status: -9878)
        let controller = GlobalHotKeyController(registrar: registrar) {}

        controller.register()
        registrar.nextResult = .registered
        controller.register()

        XCTAssertEqual(controller.registrationState, .registered)
        XCTAssertEqual(registrar.registerCallCount, 2)
    }

    func testUnregisterClearsStateAndHandler() {
        let registrar = FakeGlobalHotKeyRegistrar()
        var invocationCount = 0
        let controller = GlobalHotKeyController(registrar: registrar) {
            invocationCount += 1
        }

        controller.register()
        controller.unregister()
        registrar.fire()

        XCTAssertEqual(controller.registrationState, .notRegistered)
        XCTAssertEqual(registrar.unregisterCallCount, 1)
        XCTAssertEqual(invocationCount, 0)
    }

    func testDefaultQuickPanelShortcutIsVisible() {
        XCTAssertEqual(GlobalHotKey.quickPanelDefault.displayName, "Control-Option-Command-V")
    }
}

private final class FakeGlobalHotKeyRegistrar: GlobalHotKeyRegistering {
    var nextResult: GlobalHotKeyRegistrationState = .registered
    var registeredHotKeys: [GlobalHotKey] = []
    var registerCallCount = 0
    var unregisterCallCount = 0
    private var handler: (@MainActor () -> Void)?

    func register(
        _ hotKey: GlobalHotKey,
        handler: @escaping @MainActor () -> Void
    ) -> GlobalHotKeyRegistrationState {
        registerCallCount += 1
        registeredHotKeys.append(hotKey)
        self.handler = nextResult.isRegistered ? handler : nil
        return nextResult
    }

    func unregister() {
        unregisterCallCount += 1
        handler = nil
    }

    @MainActor
    func fire() {
        handler?()
    }
}
#elseif canImport(Testing)
import Testing
@testable import Forkclip

@MainActor
struct GlobalHotKeyControllerTests {
    @Test
    func xctestCoverageSentinelGlobalHotKeyControllerTestsOnMacOS() async throws {
        #expect(true)
    }
}
#endif
