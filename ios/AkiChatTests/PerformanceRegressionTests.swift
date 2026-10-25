import XCTest
import Combine
import SwiftUI
@testable import AkiChat

final class PerformanceRegressionTests: XCTestCase {
    private func history(_ count: Int) -> [Message] {
        (0..<count).map { Message(role: $0.isMultiple(of: 2) ? .user : .assistant, content: "消息 \($0) · **Markdown**\n\n```swift\nlet value = \($0)\n```", state: .complete) }
    }
    func testHundredAndFiveHundredRowsKeepIdentityDuringStreaming() {
        for count in [100, 500] {
            let presentation = ChatPresentation()
            var messages = history(count)
            messages.append(Message(role: .assistant, content: "", state: .generating))
            presentation.select(UUID(), messages: messages)
            let original = presentation.rows
            var historyChanges = 0, activeChanges = 0, listChanges = 0
            let subscriptions = original.dropLast().map { $0.objectWillChange.sink { historyChanges += 1 } }
            let active = original.last!.objectWillChange.sink { activeChanges += 1 }
            let list = presentation.objectWillChange.sink { listChanges += 1 }
            for i in 1...100 { messages[messages.count - 1].content += "\(i) "; presentation.receive(messages) }
            XCTAssertEqual(historyChanges, 0); XCTAssertEqual(listChanges, 0); XCTAssertEqual(activeChanges, 100)
            XCTAssertTrue(zip(original, presentation.rows).allSatisfy { $0 === $1 })
            withExtendedLifetime((subscriptions, active, list)) {}
        }
    }
    func testTypingDoesNotPublishWholeHistoryAndBackgroundSavesDraft() throws {
        let db = try LocalDatabase(inMemory: true)
        let c = Conversation(providerID: Provider.deepSeek.id, messages: history(500))
        try db.save([c], key: "conversations.v1")
        let store = AppStore(database: db)
        var wholeStoreChanges = 0
        let sink = store.objectWillChange.sink { wholeStoreChanges += 1 }
        for i in 0..<100 { store.setDraft("draft \(i)") }
        XCTAssertEqual(wholeStoreChanges, 0); XCTAssertEqual(store.draft, "draft 99")
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        let saved = expectation(for: NSPredicate { _, _ in
            (try? db.load("conversations.v1", as: [Conversation].self))?.first?.draft == "draft 99"
        }, evaluatedWith: nil)
        wait(for: [saved], timeout: 3)
        let reloaded = AppStore(database: db)
        XCTAssertEqual(reloaded.draft, "draft 99"); XCTAssertEqual(reloaded.messages, c.messages)
        withExtendedLifetime(sink) {}
    }
    func testDraftSurvivesSessionChangeAndDeletingAnotherSession() throws {
        let store = AppStore(database: try LocalDatabase(inMemory: true))
        let first = try XCTUnwrap(store.selectedID)
        store.setDraft("first draft"); store.newConversation()
        let second = try XCTUnwrap(store.selectedID)
        store.setDraft("second draft"); store.selectConversation(first)
        XCTAssertEqual(store.draft, "first draft")
        store.setDraft("latest first draft"); store.deleteConversation(second)
        XCTAssertEqual(store.draft, "latest first draft")
        XCTAssertEqual(store.exportConversations().first?.draft, "latest first draft")
    }
    func testStreamCheckpointsAndCancellationPreserveLatestContent() throws {
        let db = try LocalDatabase(inMemory: true)
        var p = Provider.deepSeek; p.apiKeyReference = UUID().uuidString
        try KeychainStore.write("mock", reference: p.apiKeyReference)
        defer { try? KeychainStore.delete(p.apiKeyReference) }
        try db.save([p], key: "providers.v1")
        try db.save([Conversation(providerID: p.id, messages: history(100))], key: "conversations.v1")
        let sender = PerformanceSender()
        let store = AppStore(database: db, senderFactory: { sender })
        store.setDraft("go"); store.send()
        XCTAssertTrue(store.isGenerating)
        var storeChanges = 0
        let sink = store.objectWillChange.sink { storeChanges += 1 }
        for i in 0..<100 { sender.update?(ChatSnapshot(content: "last \(i)")) }
        XCTAssertLessThan(storeChanges, 20)
        XCTAssertEqual(store.chat.rows.last?.message.content, "last 99")
        store.stop()
        XCTAssertEqual(store.messages.last?.content, "last 99"); XCTAssertEqual(store.messages.last?.state, .stopped)
        XCTAssertEqual(store.messages.count, 102)
        let saved = expectation(for: NSPredicate { _, _ in
            (try? db.load("conversations.v1", as: [Conversation].self))?.first?.messages.last?.content == "last 99"
        }, evaluatedWith: nil)
        wait(for: [saved], timeout: 3); withExtendedLifetime(sink) {}
    }
    func testMarkdownParsesOffMainAndDiscardsObsoleteResult() {
        let document = MarkdownDocument(parser: { source in
            XCTAssertFalse(Thread.isMainThread)
            return MarkdownParser.blocks(source)
        })
        let done = expectation(description: "latest document")
        let text = "new " + UUID().uuidString
        let sink = document.$blocks.dropFirst().sink { blocks in if blocks.first?.text == text { done.fulfill() } }
        document.load(String(repeating: "old\n\n", count: 20000), cacheResult: false)
        document.load(text, cacheResult: false)
        wait(for: [done], timeout: 3); XCTAssertEqual(document.blocks.first?.text, text)
        withExtendedLifetime(sink) {}
    }
    func testScrollFollowingPausesDuringHistoryReading() {
        let scroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 414, height: 600))
        scroll.contentSize = CGSize(width: 414, height: 2000)
        let follow = ScrollFollowController(); follow.attach(scroll); follow.pause()
        scroll.contentOffset.y = 600; scroll.contentSize.height = 2300
        let paused = expectation(description: "paused after layout")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { paused.fulfill() }
        wait(for: [paused], timeout: 1); XCTAssertEqual(scroll.contentOffset.y, 600, accuracy: 1)
        follow.resume()
        let resumed = expectation(description: "following after request")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { resumed.fulfill() }
        wait(for: [resumed], timeout: 1)
        XCTAssertEqual(scroll.contentOffset.y, 1700, accuracy: 1); follow.detach()
        XCTAssertTrue(ScrollFollowController.nearBottom(offset: 1670, content: 2300, viewport: 600, bottomInset: 0))
        XCTAssertFalse(ScrollFollowController.nearBottom(offset: 600, content: 2300, viewport: 600, bottomInset: 0))
    }
    func testLegacyNamingKeepsProviderIdentityAndOtherModels() throws {
        var p = Provider.deepSeek; p.name = ProviderNaming.legacyFlashName; p.displayName = ProviderNaming.legacyFlashName
        let db = try LocalDatabase(inMemory: true); try db.save([p], key: "providers.v1")
        let store = AppStore(database: db)
        XCTAssertEqual(store.providerName, "DeepSeek"); XCTAssertEqual(store.selectedModelLabel, "deepseek-flash")
        XCTAssertEqual(store.providers[0].id, p.id); XCTAssertEqual(store.providers[0].apiKeyReference, p.apiKeyReference)
        let remote = try ModelDiscovery.parse(Data("{\"data\":[{\"id\":\"deepseek-flash\"},{\"id\":\"deepseek-v4-pro\"}]}".utf8), provider: p)
        XCTAssertTrue(remote[0].apply(to: p).supportsThinking)
        XCTAssertTrue(remote[0].apply(to: p).supportsVision)
        XCTAssertFalse(remote[1].apply(to: p).supportsThinking)
        let disabled = try ModelDiscovery.parse(Data("{\"data\":[{\"id\":\"deepseek-flash\",\"supports_reasoning\":false,\"supports_vision\":false,\"supports_tool_calls\":false}]}".utf8), provider: p)
        XCTAssertFalse(disabled[0].apply(to: p).supportsThinking)
        XCTAssertFalse(disabled[0].apply(to: p).supportsVision)
        XCTAssertFalse(disabled[0].apply(to: p).options.supportsTools)
        for model in remote { store.saveModel(model, providerID: p.id) }
        store.selectModel(providerID: p.id, modelID: "deepseek-v4-pro")
        let request = try RequestBuilder.make(provider: XCTUnwrap(store.provider), key: "mock", conversation: XCTUnwrap(store.current), settings: store.settings, stream: true)
        let body = try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any]
        XCTAssertEqual(body?["model"] as? String, "deepseek-v4-pro")
        XCTAssertEqual(store.providerName, "DeepSeek"); XCTAssertEqual(store.selectedModelLabel, "deepseek-v4-pro")
        store.newConversation()
        XCTAssertEqual(store.providerName, "DeepSeek"); XCTAssertEqual(store.selectedModelLabel, "deepseek-v4-pro")
    }
    func testMeasureFiveHundredMessageStreamPresentation() {
        let base = history(500) + [Message(role: .assistant, content: "", state: .generating)]
        measure {
            let presentation = ChatPresentation(); var messages = base
            presentation.select(UUID(), messages: messages)
            for i in 0..<200 { messages[messages.count - 1].content = "tick \(i)"; presentation.receive(messages) }
        }
    }
    func testThumbnailDownsamplesAndReleasesOffscreenImage() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 400)).image { context in
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 600, height: 400))
        }
        let data = try XCTUnwrap(image.jpegData(compressionQuality: 0.7))
        let attachment = Attachment(jpeg: data, width: 600, height: 400)
        let loader = ThumbnailLoader()
        let loaded = expectation(description: "downsampled image")
        let sink = loader.$image.dropFirst().sink { image in if image != nil { loaded.fulfill() } }
        loader.load(attachment, maxPixel: 120)
        wait(for: [loaded], timeout: 3)
        XCTAssertLessThanOrEqual(loader.image?.cgImage?.width ?? 1000, 120)
        loader.release(); XCTAssertNil(loader.image)
        withExtendedLifetime(sink) {}
    }
    func testMeasureLongMarkdownParsing() {
        let source = "# Long document\n\n```swift\n" + (0..<5000).map { "let codeLine\($0) = \($0)" }.joined(separator: "\n") + "\n```"
        measure { XCTAssertEqual(MarkdownParser.blocks(source).count, 2) }
    }
}

private final class PerformanceSender: ChatRequestSending {
    var update: ((ChatSnapshot) -> Void)?
    func send(_ request: URLRequest, stream: Bool, onUpdate: @escaping (ChatSnapshot) -> Void, completion: @escaping (Result<ChatSnapshot, Error>) -> Void) { update = onUpdate }
    func cancel() {}
}
