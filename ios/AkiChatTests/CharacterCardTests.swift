import XCTest
import UIKit
import zlib
@testable import AkiChat

final class CharacterCardTests: XCTestCase {
    static func fixture(version: Int = 2, name: String = "璃月") throws -> Data {
        try JSONSerialization.data(withJSONObject: ["spec": "chara_card_v\(version)", "spec_version": "\(version).0", "data": [
            "name": name, "description": "{{char}} 是远行的魔法师", "personality": "耐心", "scenario": "古塔", "first_mes": "欢迎，{{user}}，我是{{char}}。", "mes_example": "<START>\n{{user}}: 你好\n{{char}}: 欢迎。",
            "alternate_greetings": ["{{user}}，我们在森林相遇。"], "system_prompt": "{{original}}\n扮演 {{char}}", "post_history_instructions": "保持{{char}}的口吻，回应{{user}}。",
            "creator_notes": "AUTHOR_NOT_SENT", "tags": ["魔法", "冒险"], "creator": "CREATOR_NOT_SENT", "character_version": "9.0", "extensions": ["unknown-extension": ["code": "DO_NOT_EXECUTE"]],
            "nickname": "小璃", "assets": [["type": "icon", "uri": "https://never-download.invalid/a.png"]], "group_only_greetings": ["群聊设定"],
            "character_book": ["name": "古塔", "token_budget": 100, "entries": [
                ["keys": [], "content": "常驻塔楼", "constant": true, "enabled": true, "insertion_order": 1, "position": "before_char"],
                ["keys": ["森林"], "content": "森林传说", "enabled": true, "insertion_order": 2],
                ["keys": ["森林"], "content": "禁用内容", "enabled": false],
                ["keys": ["森林"], "content": "复杂规则", "enabled": true, "extensions": ["probability": 5]]
            ]]
        ]], options: [.sortedKeys])
    }
    static func png() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).pngData { context in
            UIColor.systemBlue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
    }
    static func word(_ value: UInt32) -> Data { Data([UInt8((value >> 24) & 255), UInt8((value >> 16) & 255), UInt8((value >> 8) & 255), UInt8(value & 255)]) }
    static func chunk(_ type: String, _ payload: Data) -> Data {
        let bytes = Data(type.utf8) + payload
        let crc = bytes.withUnsafeBytes { crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt(bytes.count)) }
        return word(UInt32(payload.count)) + bytes + word(UInt32(crc))
    }
    static func compressed(_ input: Data) -> Data {
        var result = Data(count: Int(compressBound(uLong(input.count)))), size = uLongf(result.count)
        let code = result.withUnsafeMutableBytes { out in input.withUnsafeBytes { raw in
            compress2(out.bindMemory(to: Bytef.self).baseAddress, &size, raw.bindMemory(to: Bytef.self).baseAddress, uLong(input.count), Z_BEST_COMPRESSION)
        } }
        precondition(code == Z_OK); result.count = Int(size); return result
    }
    static func embedded(_ chunks: [Data]) -> Data {
        var source = png(); source.insert(contentsOf: chunks.reduce(Data(), +), at: source.count - 12); return source
    }
    func testV2V3JSONAndUnknownDataArePreserved() throws {
        for version in [2, 3] {
            let raw = try Self.fixture(version: version), value = try CharacterCardParser.parse(raw)
            XCTAssertEqual(value.record.rawJSON, raw); XCTAssertEqual(value.record.fields.name, "璃月")
            XCTAssertEqual(value.record.fields.alternateGreetings.count, 1)
            XCTAssertEqual(value.record.fields.creatorNotes, "AUTHOR_NOT_SENT")
            XCTAssertEqual(value.record.fields.book?.entries.count, 4)
            XCTAssertTrue(String(decoding: value.record.rawJSON, as: UTF8.self).contains("never-download.invalid"))
            try CharacterCardParser.validate(value.record)
        }
        for raw in ["{\"name\":\"not a card\"}", "{\"spec\":\"chara_card_v2\",\"spec_version\":\"2.0\",\"data\":{\"name\":\"incomplete\"}}"] {
            XCTAssertThrowsError(try CharacterCardParser.parse(Data(raw.utf8)))
        }
    }
    func testV2V3PNGPrefersValidV3AndDecodesAvatar() throws {
        let v2 = Self.chunk("tEXt", Data("chara\0".utf8) + (try Self.fixture()).base64EncodedData())
        let v3 = Self.chunk("tEXt", Data("ccv3\0".utf8) + (try Self.fixture(version: 3, name: "V3角色")).base64EncodedData())
        for chunks in [[v2], [v3], [v2, v3], [v3, v2]] {
            let png = Self.embedded(chunks), parsed = try CharacterCardParser.parse(png)
            XCTAssertEqual(parsed.record.spec, chunks.count == 1 && chunks[0] == v2 ? "chara_card_v2" : "chara_card_v3")
            XCTAssertNotNil(UIImage(data: try XCTUnwrap(parsed.record.avatarJPEG)))
            XCTAssertEqual(parsed.originalPNG, png)
        }
        let invalid = Self.chunk("tEXt", Data("ccv3\0not-valid-json".utf8))
        let fallback = try CharacterCardParser.parse(Self.embedded([v2, invalid]))
        XCTAssertEqual(fallback.record.spec, "chara_card_v2"); XCTAssertFalse(fallback.warnings.isEmpty)
    }
    func testZTXtAndITXtCompressionRules() throws {
        let json = try Self.fixture(version: 3), payload = json.base64EncodedData()
        let values = [Self.chunk("zTXt", Data("ccv3\0".utf8) + Data([0]) + Self.compressed(payload)),
                      Self.chunk("iTXt", Data("ccv3\0".utf8) + Data([0, 0, 0, 0]) + payload),
                      Self.chunk("iTXt", Data("ccv3\0".utf8) + Data([1, 0, 0, 0]) + Self.compressed(payload))]
        for value in values { XCTAssertEqual(try CharacterCardParser.parse(Self.embedded([value])).record.spec, "chara_card_v3") }
        let invalidMethod = Self.chunk("zTXt", Data("ccv3\0".utf8) + Data([1]) + Self.compressed(payload))
        XCTAssertThrowsError(try CharacterCardParser.parse(Self.embedded([invalidMethod])))
    }
    func testPNGCorruptionAndResourceLimits() throws {
        XCTAssertThrowsError(try CharacterCardParser.parse(Self.png())) { XCTAssertTrue($0.localizedDescription.contains("没有角色信息")) }
        let card = Self.chunk("tEXt", Data("chara\0".utf8) + (try Self.fixture()).base64EncodedData())
        var corrupt = Self.embedded([card]); corrupt[corrupt.count - 1] ^= 1
        XCTAssertThrowsError(try CharacterCardParser.parse(corrupt))
        var truncated = Self.embedded([card]); truncated.removeLast(8)
        XCTAssertThrowsError(try CharacterCardParser.parse(truncated))
        let maliciousLength = CharacterCardParser.pngSignature + Self.word(UInt32.max) + Data("IHDR".utf8)
        XCTAssertThrowsError(try CharacterCardParser.parse(maliciousLength))
        let bomb = Self.chunk("zTXt", Data("chara\0".utf8) + Data([0]) + Self.compressed(Data(repeating: 65, count: 2 * 1024 * 1024)))
        XCTAssertThrowsError(try CharacterCardParser.parse(Self.embedded([bomb])))
        XCTAssertThrowsError(try CharacterCardParser.parse(Data(repeating: 65, count: CharacterCardParser.fileLimit + 1)))
        XCTAssertThrowsError(try CharacterCardParser.object(Data((String(repeating: "[", count: 40) + String(repeating: "]", count: 40)).utf8)))
    }
    func testVariablesAreOnePassAndBounded() {
        XCTAssertEqual(CharacterPrompt.render("{{char}}/{{USER}}/{{original}}", character: "璃月", user: "旅行者", original: "原提示"), "璃月/旅行者/原提示")
        XCTAssertEqual(CharacterPrompt.render("{{user}}", character: "X", user: "{{char}}"), "{{char}}")
        XCTAssertEqual(CharacterPrompt.render(String(repeating: "{{original}}", count: 1000), character: "x", user: "y", original: String(repeating: "z", count: 65536)), CharacterPrompt.limitMarker)
    }
    func testOrdinaryPromptIsNotSubjectToCharacterExpansionGuard() throws {
        var settings = AppSettings(); settings.systemPrompt = CharacterPrompt.limitMarker
        let c = Conversation(providerID: Provider.deepSeek.id, messages: [Message(role: .user, content: "hello")])
        let request = try RequestBuilder.make(provider: .deepSeek, key: "mock", conversation: c, settings: settings, stream: false)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertTrue((messages.first?["content"] as? String)?.contains(CharacterPrompt.limitMarker) == true)
    }
    func testArchiveRejectsNonJPEGAvatarAndMismatchedRoleIdentity() throws {
        var card = try CharacterCardParser.json(Self.fixture())
        card.avatarJPEG = Self.png()
        XCTAssertThrowsError(try CharacterCardParser.validate(card))
        card.avatarJPEG = nil
        var c = Conversation(providerID: Provider.deepSeek.id)
        c.character = CharacterBinding(characterID: UUID(), snapshot: card)
        XCTAssertThrowsError(try ExportService.decode(ExportService.json([c])))
    }
    func testWorldbookOnlySupportedEnabledMatchingEntriesWithinBudget() throws {
        let card = try CharacterCardParser.json(Self.fixture())
        XCTAssertEqual(CharacterPrompt.activated(card, messages: []).ids, [0])
        let active = CharacterPrompt.activated(card, messages: [Message(role: .user, content: "走进森林")])
        XCTAssertEqual(active.ids, [0, 1]); XCTAssertTrue(active.before.contains("常驻塔楼")); XCTAssertTrue(active.after.contains("森林传说"))
        XCTAssertFalse(active.after.contains("复杂规则")); XCTAssertFalse(active.after.contains("禁用内容"))
        var limited = card; limited.fields.book?.budget = 0
        XCTAssertTrue(CharacterPrompt.activated(limited, messages: []).ids.isEmpty)
    }
    func testRolePromptGreetingAndTrailingInstructionsReachActualRequestOnlyForBoundConversation() throws {
        let card = try CharacterCardParser.json(Self.fixture())
        var settings = AppSettings(); settings.options.roleplayUserName = "阿秋"
        var c = Conversation(providerID: Provider.deepSeek.id)
        let greeting = Message(role: .assistant, content: "本地开场白")
        c.messages = [greeting, Message(role: .user, content: "森林在哪里？")]
        c.character = CharacterBinding(characterID: card.id, snapshot: card, greetingMessageID: greeting.id)
        for var p in [Provider.deepSeek, Provider.workBuddy, Provider.openAI] {
            p.baseURL = "https://mock.invalid/v1"; p.modelID = "model"; p.options.supportsSystem = p.kind != .openAI
            let request = try RequestBuilder.make(provider: p, key: "mock", conversation: c, settings: settings, stream: false)
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
            let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
            let serialized = String(decoding: try JSONSerialization.data(withJSONObject: messages), as: UTF8.self)
            XCTAssertTrue(serialized.contains("璃月")); XCTAssertTrue(serialized.contains("阿秋")); XCTAssertTrue(serialized.contains("森林传说"))
            XCTAssertTrue(serialized.contains("<START>")); XCTAssertFalse(serialized.contains("AUTHOR_NOT_SENT")); XCTAssertFalse(serialized.contains("CREATOR_NOT_SENT"))
            XCTAssertEqual(messages.filter { $0["content"] as? String == "本地开场白" }.count, 1)
            XCTAssertTrue((messages.last?["content"] as? String)?.contains("历史后续写") == true)
            XCTAssertFalse(c.messages.last!.content.contains("历史后续写"))
        }
        let otherCard = try CharacterCardParser.json(Self.fixture(name: "另一角色"))
        var other = c; other.character = CharacterBinding(characterID: otherCard.id, snapshot: otherCard)
        XCTAssertFalse(PromptResolver.effective(provider: .deepSeek, conversation: other, settings: settings).contains("角色名称：璃月"))
        c.character = nil
        XCTAssertFalse(PromptResolver.effective(provider: .deepSeek, conversation: c, settings: settings).contains("远行的魔法师"))
        XCTAssertEqual(settings.systemPrompt, AppSettings().systemPrompt)
    }
    func testOpeningDoesNotCountAsUserTurnAndDropsWithTrimmedHistory() throws {
        let card = try CharacterCardParser.json(Self.fixture())
        let opening = Message(role: .assistant, content: "opening")
        var c = Conversation(providerID: Provider.deepSeek.id, messages: [opening])
        c.character = CharacterBinding(characterID: card.id, snapshot: card, greetingMessageID: opening.id)
        for i in 0..<12 { c.messages += [Message(role: .user, content: "q\(i)"), Message(role: .assistant, content: "a\(i)")] }
        XCTAssertEqual(ContextManager.turns(c.messages).count, 12)
        c.options.context.strategy = .full
        XCTAssertEqual(try ContextManager.plan(provider: .deepSeek, conversation: c, settings: AppSettings(), tools: false).messages.first?.id, opening.id)
        c.options.context.strategy = .window; c.options.context.recentTurns = 8
        let plan = try ContextManager.plan(provider: .deepSeek, conversation: c, settings: AppSettings(), tools: false)
        XCTAssertFalse(plan.messages.contains { $0.id == opening.id }); XCTAssertEqual(plan.messages.filter { $0.role == .user }.count, 8)
    }
    func testLibraryPersistenceDeletionSnapshotsAndOldArchiveCompatibility() throws {
        let db = RecordingDatabase(), store = AppStore(database: db)
        let ordinaryID = store.current!.id, providerID = store.providers[0].id
        let imported = try CharacterCardParser.parse(Self.fixture())
        let saved = expectation(description: "save role")
        store.saveCharacter(imported) { result in if case .failure = result { XCTFail("Save failed") }; saved.fulfill() }
        wait(for: [saved], timeout: 3)
        try store.newCharacterConversation(store.characters[0], greeting: 1, providerID: providerID, modelID: store.providers[0].modelID)
        XCTAssertEqual(store.messages.count, 1); XCTAssertTrue(store.messages[0].content.contains("旅行者"))
        XCTAssertTrue(store.messages[0].content.contains("森林")); XCTAssertFalse(store.isGenerating)
        let roleID = store.current!.id
        let flush = expectation(description: "persist")
        store.flushPersistence { flush.fulfill() }; wait(for: [flush], timeout: 3)
        let restarted = AppStore(database: db)
        XCTAssertEqual(restarted.characters.count, 1); XCTAssertEqual(restarted.providers[0].id, providerID)
        restarted.deleteCharacter(imported.record.id)
        XCTAssertNotNil(restarted.current?.character); XCTAssertEqual(restarted.messages.count, 1)
        let exported = try ExportService.json(restarted.exportConversations())
        let decoded = try ExportService.decode(exported)
        XCTAssertEqual(decoded.first(where: { $0.id == roleID })?.character?.snapshot.rawJSON, imported.record.rawJSON)
        XCTAssertNil(decoded.first(where: { $0.id == ordinaryID })?.character)
        restarted.selectConversation(ordinaryID); XCTAssertNil(restarted.current?.character)
    }
    func testOriginalPNGFileImportAndAssetStorageAreLossless() throws {
        let png = Self.embedded([Self.chunk("tEXt", Data("chara\0".utf8) + (try Self.fixture()).base64EncodedData())])
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        try png.write(to: file); defer { try? FileManager.default.removeItem(at: file) }
        let done = expectation(description: "file import and save")
        let store = AppStore(database: RecordingDatabase())
        var asset: URL?
        CharacterImportService.load(file) { result in
            do {
                let value = try result.get()
                XCTAssertEqual(value.originalPNG, png)
                store.saveCharacter(value) { saved in
                    do {
                        let id = try saved.get()
                        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                        asset = support.appendingPathComponent("CharacterAssets/" + id.uuidString + ".png")
                        XCTAssertEqual(try Data(contentsOf: asset!), png)
                        XCTAssertEqual(store.characters.first?.originalPNGAssetID, id)
                    } catch { XCTFail(error.localizedDescription) }
                    done.fulfill()
                }
            } catch { XCTFail(error.localizedDescription); done.fulfill() }
        }
        wait(for: [done], timeout: 5)
        if let asset = asset { try? FileManager.default.removeItem(at: asset) }
    }
    func testStoreSendAfterModelSwitchRetainsRoleAndUsesActualProvider() throws {
        let db = RecordingDatabase()
        var second = Provider.openAI; second.modelID = "second-model"; second.baseURL = "https://role-mock.invalid/v1"; second.apiKeyReference = UUID().uuidString
        try KeychainStore.write("mock-role-key", reference: second.apiKeyReference)
        defer { try? KeychainStore.delete(second.apiKeyReference) }
        let first = Provider.deepSeek
        try db.save([first, second], key: "providers.v1")
        let sent = expectation(description: "actual store request")
        let store = AppStore(database: db, senderFactory: {
            ScriptedSender { request, completion in
                XCTAssertEqual(request.url?.absoluteString, "https://role-mock.invalid/v1/chat/completions")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer mock-role-key")
                let body = try! JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
                XCTAssertEqual(body["model"] as? String, "second-model")
                let text = String(decoding: request.httpBody!, as: UTF8.self)
                XCTAssertTrue(text.contains("璃月")); XCTAssertTrue(text.contains("森林传说"))
                var reply = ChatSnapshot(); reply.content = "角色回复"
                DispatchQueue.main.async { completion(.success(reply)); sent.fulfill() }
            }
        })
        let card = try CharacterCardParser.json(Self.fixture())
        try store.newCharacterConversation(card, greeting: 0, providerID: first.id, modelID: first.modelID)
        store.selectModel(providerID: second.id, modelID: second.modelID)
        XCTAssertEqual(store.current?.character?.characterID, card.id)
        store.setDraft("走进森林"); store.send(); wait(for: [sent], timeout: 3)
        XCTAssertEqual(store.messages.last?.content, "角色回复")
    }
}
