import Foundation
import AppKit

@MainActor
protocol PasteboardProviding: AnyObject {
    var changeCount: Int { get }
    var availableTypes: [NSPasteboard.PasteboardType] { get }
    func monitoredChangeCount() throws -> Int
    func string(forType type: NSPasteboard.PasteboardType) -> String?
    func data(forType type: NSPasteboard.PasteboardType) -> Data?
    func fallbackImageData() -> Data?
    @discardableResult
    func clearContents() -> Int
    @discardableResult
    func setString(_ string: String, forType type: NSPasteboard.PasteboardType) -> Bool
    @discardableResult
    func setData(_ data: Data?, forType type: NSPasteboard.PasteboardType) -> Bool
}

@MainActor
extension PasteboardProviding {
    func monitoredChangeCount() throws -> Int {
        changeCount
    }
}

extension NSPasteboard: PasteboardProviding {
    var availableTypes: [NSPasteboard.PasteboardType] {
        let directTypes = types ?? []
        let itemTypes = pasteboardItems?.flatMap(\.types) ?? []
        return (directTypes + itemTypes).reduce(into: []) { result, type in
            if !result.contains(type) {
                result.append(type)
            }
        }
    }

    func fallbackImageData() -> Data? {
        NSImage(pasteboard: self)?.tiffRepresentation
    }
}

struct ClipboardCaptureSnapshot: Equatable {
    let plainText: String?
    let previewText: String?
    let contentTypes: [ClipboardContentType]
    let unsupportedTypeNames: [String]
    let payloads: [ClipboardPayload]

    var hasNonTextContent: Bool {
        contentTypes.contains { $0 != .plainText } || !unsupportedTypeNames.isEmpty
    }

    var hasSupportedContent: Bool {
        !payloads.isEmpty
    }

    var isPlainTextOnly: Bool {
        !payloads.isEmpty && payloads.allSatisfy { $0.contentType == .plainText }
    }

    var primaryContentType: ClipboardContentType {
        payloads.first?.contentType ?? .plainText
    }

    @MainActor
    static func read(
        from pasteboard: PasteboardProviding,
        metadata: ClipboardPasteboardMetadata? = nil
    ) -> ClipboardCaptureSnapshot {
        let text = pasteboard.string(forType: .string)
        let pasteboardTypes = metadata?.availableTypes ?? pasteboard.availableTypes
        let capturedPayloads = rankedPayloads(from: pasteboard, pasteboardTypes: pasteboardTypes, plainText: text)
        var contentTypes = capturedPayloads.map(\.contentType)

        if let text, !text.isEmpty, !contentTypes.contains(.plainText) {
            contentTypes.insert(.plainText, at: 0)
        }

        let unsupportedTypeNames = pasteboardTypes
            .filter { normalizedContentType(for: $0) == nil }
            .map(\.rawValue)

        return ClipboardCaptureSnapshot(
            plainText: text,
            previewText: previewText(for: capturedPayloads, plainText: text),
            contentTypes: unique(contentTypes),
            unsupportedTypeNames: unsupportedTypeNames,
            payloads: capturedPayloads
        )
    }

    private static func normalizedContentType(for type: NSPasteboard.PasteboardType) -> ClipboardContentType? {
        switch type.rawValue {
        case NSPasteboard.PasteboardType.string.rawValue:
            return .plainText
        case "public.url":
            return .urlText
        case "public.file-url":
            return .fileURL
        case "public.rtf":
            return .rtf
        case "public.html":
            return .html
        case "public.tiff", "public.png", "public.jpeg", "public.heic":
            return .image
        default:
            return nil
        }
    }

    @MainActor
    private static func rankedPayloads(
        from pasteboard: PasteboardProviding,
        pasteboardTypes: [NSPasteboard.PasteboardType],
        plainText: String?
    ) -> [ClipboardPayload] {
        var unranked: [ClipboardPayload] = []

        if let imagePayload = imagePayload(from: pasteboard, pasteboardTypes: pasteboardTypes) {
            unranked.append(imagePayload)
        }

        for type in preferredNonImageTypes where pasteboardTypes.contains(type.pasteboardType) {
            guard let data = payloadData(for: type.pasteboardType, from: pasteboard) else { continue }
            unranked.append(ClipboardPayload(
                contentType: type.contentType,
                pasteboardType: type.pasteboardType,
                data: data,
                preview: preview(for: type.contentType, data: data),
                rank: 0
            ))
        }

        if let plainText, !plainText.isEmpty {
            if isLikelyURLText(plainText),
               !unranked.contains(where: { $0.contentType == .urlText }) {
                unranked.append(ClipboardPayload(
                    contentType: .urlText,
                    pasteboardType: .URL,
                    data: Data(plainText.utf8),
                    preview: plainText,
                    rank: 0
                ))
            }
            unranked.append(.plainText(plainText))
        }

        return unranked.enumerated().map { index, payload in
            ClipboardPayload(
                id: payload.id,
                contentType: payload.contentType,
                pasteboardType: payload.pasteboardType,
                data: payload.data,
                preview: payload.preview,
                rank: index
            )
        }
    }

    private static let preferredImageTypes: [NSPasteboard.PasteboardType] = [
        .png,
        .tiff,
        NSPasteboard.PasteboardType(rawValue: "public.jpeg"),
        NSPasteboard.PasteboardType(rawValue: "public.heic")
    ]

    private static let preferredNonImageTypes: [(pasteboardType: NSPasteboard.PasteboardType, contentType: ClipboardContentType)] = [
        (.fileURL, .fileURL),
        (.rtf, .rtf),
        (.html, .html),
        (.URL, .urlText)
    ]

    @MainActor
    private static func imagePayload(
        from pasteboard: PasteboardProviding,
        pasteboardTypes: [NSPasteboard.PasteboardType]
    ) -> ClipboardPayload? {
        let availableImageTypes = preferredImageTypes.filter { pasteboardTypes.contains($0) }
        for type in availableImageTypes {
            guard let data = payloadData(for: type, from: pasteboard) else { continue }
            return ClipboardPayload(
                contentType: .image,
                pasteboardType: type,
                data: data,
                preview: "画像",
                rank: 0
            )
        }

        guard !availableImageTypes.isEmpty,
              let data = pasteboard.fallbackImageData(),
              !data.isEmpty else {
            return nil
        }
        return ClipboardPayload(
            contentType: .image,
            pasteboardType: .tiff,
            data: data,
            preview: "画像",
            rank: 0
        )
    }

    @MainActor
    private static func payloadData(for type: NSPasteboard.PasteboardType, from pasteboard: PasteboardProviding) -> Data? {
        if let data = pasteboard.data(forType: type), !data.isEmpty {
            return data
        }
        guard let string = pasteboard.string(forType: type), !string.isEmpty else {
            return nil
        }
        return Data(string.utf8)
    }

    private static func preview(for contentType: ClipboardContentType, data: Data) -> String {
        switch contentType {
        case .image:
            return "画像"
        case .fileURL:
            guard let value = String(data: data, encoding: .utf8),
                  let url = URL(string: value) else {
                return "ファイル"
            }
            let name = url.lastPathComponent
            return name.isEmpty ? "ファイル" : "ファイル: \(name)"
        case .rtf:
            return "リッチテキスト"
        case .html:
            return "HTML"
        case .urlText:
            return String(data: data, encoding: .utf8) ?? "URL"
        case .plainText:
            return String(data: data, encoding: .utf8) ?? "テキスト"
        case .unknown:
            return "未対応形式"
        }
    }

    private static func previewText(for payloads: [ClipboardPayload], plainText: String?) -> String? {
        if let plainText, !plainText.isEmpty {
            return plainText
        }
        return payloads.first?.preview
    }

    private static func isLikelyURLText(_ text: String) -> Bool {
        guard let url = URL(string: text),
              let scheme = url.scheme?.lowercased() else {
            return false
        }
        return ["http", "https", "ftp", "mailto"].contains(scheme)
    }

    private static func unique(_ contentTypes: [ClipboardContentType]) -> [ClipboardContentType] {
        contentTypes.reduce(into: []) { result, contentType in
            if !result.contains(contentType) {
                result.append(contentType)
            }
        }
    }
}

struct ClipboardPasteboardMetadata: Equatable {
    static let concealedType = NSPasteboard.PasteboardType(rawValue: "org.nspasteboard.ConcealedType")

    let availableTypes: [NSPasteboard.PasteboardType]

    var hasConcealedContent: Bool {
        availableTypes.contains(Self.concealedType)
    }

    var concealedTypeNames: [String] {
        availableTypes
            .filter { $0 == Self.concealedType }
            .map(\.rawValue)
    }

    @MainActor
    static func read(from pasteboard: PasteboardProviding) -> ClipboardPasteboardMetadata {
        ClipboardPasteboardMetadata(availableTypes: pasteboard.availableTypes)
    }
}

@MainActor
protocol FrontmostApplicationProviding {
    func frontmostBundleIdentifier() -> String?
}

struct WorkspaceFrontmostApplicationProvider: FrontmostApplicationProviding {
    func frontmostBundleIdentifier() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }
}

enum ClipboardMonitorState: Equatable, Sendable {
    case unchecked
    case stopped
    case starting
    case monitoring
    case failed(String)
}

@MainActor
protocol ClipboardMonitorSchedule {
    func invalidate()
}

@MainActor
protocol ClipboardMonitorScheduling {
    func scheduleRepeating(every interval: TimeInterval, onTick: @escaping @MainActor () -> Void) throws -> ClipboardMonitorSchedule
}

@MainActor
private final class TimerClipboardMonitorSchedule: ClipboardMonitorSchedule {
    private let timer: Timer

    init(timer: Timer) {
        self.timer = timer
    }

    func invalidate() {
        timer.invalidate()
    }
}

@MainActor
struct RunLoopClipboardMonitorScheduler: ClipboardMonitorScheduling {
    func scheduleRepeating(every interval: TimeInterval, onTick: @escaping @MainActor () -> Void) throws -> ClipboardMonitorSchedule {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            Task { @MainActor in
                onTick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        return TimerClipboardMonitorSchedule(timer: timer)
    }
}

@MainActor
final class ClipboardMonitor {
    private let pasteboard: PasteboardProviding
    private let pollInterval: TimeInterval
    private let scheduler: ClipboardMonitorScheduling
    private let onChange: @MainActor (Int) -> Void
    private var schedule: ClipboardMonitorSchedule?

    private(set) var state: ClipboardMonitorState = .stopped
    private(set) var lastObservedChangeCount: Int

    init(
        pasteboard: PasteboardProviding,
        pollInterval: TimeInterval = 0.5,
        scheduler: ClipboardMonitorScheduling = RunLoopClipboardMonitorScheduler(),
        onChange: @escaping @MainActor (Int) -> Void
    ) {
        self.pasteboard = pasteboard
        self.pollInterval = pollInterval
        self.scheduler = scheduler
        self.onChange = onChange
        self.lastObservedChangeCount = pasteboard.changeCount
    }

    func start() {
        guard schedule == nil else {
            AppLogger.app.debug("Clipboard monitor start ignored because it is already running.")
            return
        }

        state = .starting
        AppLogger.app.notice("Clipboard monitor start requested.")

        do {
            schedule = try scheduler.scheduleRepeating(every: pollInterval) { [weak self] in
                self?.pollPasteboard()
            }
            state = .monitoring
            AppLogger.app.notice("Clipboard monitor started.")
        } catch {
            markFailure("Unable to schedule clipboard polling: \(error.localizedDescription)")
        }
    }

    func stop() {
        schedule?.invalidate()
        schedule = nil
        state = .stopped
        AppLogger.app.notice("Clipboard monitor stopped.")
    }

    func pollPasteboard() {
        let changeCount: Int
        do {
            changeCount = try pasteboard.monitoredChangeCount()
        } catch {
            markFailure("Unable to read pasteboard change count: \(error.localizedDescription)")
            return
        }

        guard changeCount != lastObservedChangeCount else { return }

        lastObservedChangeCount = changeCount
        AppLogger.app.debug("Clipboard change observed: \(changeCount, privacy: .public)")
        onChange(changeCount)
    }

    func markFailure(_ message: String) {
        schedule?.invalidate()
        schedule = nil
        state = .failed(message)
        AppLogger.app.error("Clipboard monitor failed: \(message, privacy: .public)")
    }
}
