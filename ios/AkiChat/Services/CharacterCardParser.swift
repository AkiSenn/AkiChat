import Foundation
import UIKit
import ImageIO
import zlib

/// Independent implementation of the public CCv2/CCv3 formats; no frontend source reused.
enum CharacterCardParser {
    static let fileLimit = 16 * 1024 * 1024
    static let jsonLimit = 512 * 1024
    static let pngSignature = Data([137, 80, 78, 71, 13, 10, 26, 10])
    static func parse(_ data: Data) throws -> CharacterImport {
        guard data.count <= fileLimit else { throw CharacterImportError.limit("文件最多 16 MiB") }
        if data.starts(with: pngSignature) { return try png(data) }
        return CharacterImport(record: try json(data))
    }
    static func object(_ data: Data) throws -> [String: Any] {
        guard data.count <= jsonLimit else { throw CharacterImportError.limit("JSON 或解压内容最多 512 KiB") }
        var depth = 0, nodes = 0, quoted = false, escaped = false
        for byte in data {
            if quoted {
                if escaped { escaped = false }
                else if byte == 92 { escaped = true }
                else if byte == 34 { quoted = false }
            } else if byte == 34 { quoted = true }
            else if byte == 123 || byte == 91 {
                depth += 1; nodes += 1
                guard depth <= 32, nodes <= 20000 else { throw CharacterImportError.limit("JSON 嵌套最多 32 层") }
            } else if byte == 125 || byte == 93 { depth -= 1 }
        }
        guard depth == 0, !quoted else { throw CharacterImportError.corrupt }
        do {
            guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw CharacterImportError.invalid }
            return value
        } catch let error as CharacterImportError { throw error }
        catch { throw CharacterImportError.corrupt }
    }
    static func json(_ data: Data) throws -> CharacterRecord {
        let root = try object(data)
        guard let spec = root["spec"] as? String, let version = root["spec_version"] as? String,
              (spec == "chara_card_v2" && version == "2.0") || (spec == "chara_card_v3" && version == "3.0") else { throw CharacterImportError.unsupported }
        guard let value = root["data"] as? [String: Any] else { throw CharacterImportError.invalid }
        func text(_ key: String, required: Bool = false) throws -> String {
            if value[key] == nil && !required { return "" }
            guard let text = value[key] as? String else { throw CharacterImportError.invalid }
            guard text.utf8.count <= 65536 else { throw CharacterImportError.limit("单项文字最多 64 KiB") }
            return text
        }
        let name = try text("name", required: true).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 100 else { throw CharacterImportError.invalid }
        var book: CharacterBook?
        if let raw = value["character_book"], !(raw is NSNull) {
            guard let raw = raw as? [String: Any], let rows = raw["entries"] as? [[String: Any]] else { throw CharacterImportError.invalid }
            guard rows.count <= 256 else { throw CharacterImportError.limit("世界书最多 256 条") }
            let entries = try rows.enumerated().map { index, row -> LoreEntry in
                guard let content = row["content"] as? String, content.utf8.count <= 8192 else { throw CharacterImportError.limit("世界书单条最多 8 KiB") }
                let keys = try strings(row["keys"], count: 8, length: 128)
                let secondary = try strings(row["secondary_keys"], count: 8, length: 128)
                let position = row["position"] as? String ?? "after_char"
                let ext = row["extensions"] as? [String: Any] ?? [:]
                // Advanced decorators/extensions are preserved in rawJSON, never silently executed.
                let supported = ext.isEmpty && row["use_regex"] as? Bool != true && !content.contains("@@") &&
                    row["priority"] == nil && ["before_char", "after_char"].contains(position) && !keys.contains { $0.hasPrefix("/") && $0.dropFirst().contains("/") }
                for flag in ["enabled", "constant", "selective", "case_sensitive"] where row[flag] != nil {
                    guard let value = row[flag], CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID() else { throw CharacterImportError.invalid }
                }
                return LoreEntry(id: index, keys: keys, secondaryKeys: secondary, content: content,
                    enabled: row["enabled"] as? Bool ?? true, constant: row["constant"] as? Bool ?? false,
                    selective: row["selective"] as? Bool ?? false, caseSensitive: row["case_sensitive"] as? Bool ?? false,
                    order: row["insertion_order"] as? Int ?? index, position: position, supported: supported)
            }
            book = CharacterBook(name: raw["name"] as? String ?? "世界书", entries: entries,
                rawJSON: try JSONSerialization.data(withJSONObject: raw, options: [.sortedKeys]),
                budget: min(1024, max(0, raw["token_budget"] as? Int ?? 1024)), scanDepth: min(12, max(1, raw["scan_depth"] as? Int ?? 6)))
        }
        guard value["extensions"] == nil || value["extensions"] is [String: Any] else { throw CharacterImportError.invalid }
        let fields = try CharacterFields(name: name, description: text("description", required: true), personality: text("personality", required: true),
            scenario: text("scenario", required: true), firstMessage: text("first_mes", required: true), examples: text("mes_example", required: true),
            alternateGreetings: strings(value["alternate_greetings"], count: 64, length: 16384), systemPrompt: text("system_prompt"), postHistory: text("post_history_instructions"),
            creatorNotes: text("creator_notes"), tags: strings(value["tags"], count: 64, length: 128), creator: text("creator"), version: text("character_version"),
            extensionsJSON: JSONSerialization.data(withJSONObject: value["extensions"] as? [String: Any] ?? [:], options: [.sortedKeys]), book: book)
        return CharacterRecord(spec: spec, fields: fields, rawJSON: data)
    }
    private static func strings(_ input: Any?, count: Int, length: Int) throws -> [String] {
        guard let input = input else { return [] }
        guard let values = input as? [String] else { throw CharacterImportError.invalid }
        guard values.count <= count, values.allSatisfy({ $0.utf8.count <= length }) else { throw CharacterImportError.limit("文字列表超过数量或长度上限") }
        return values
    }
    static func validate(_ record: CharacterRecord) throws {
        let parsed = try json(record.rawJSON)
        guard parsed.fields == record.fields, parsed.spec == record.spec else { throw CharacterImportError.invalid }
        if let avatar = record.avatarJPEG {
            guard avatar.count <= 128 * 1024, avatar.starts(with: Data([255, 216, 255])), let source = CGImageSourceCreateWithData(avatar as CFData, nil),
                  let info = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let w = info[kCGImagePropertyPixelWidth] as? Int, let h = info[kCGImagePropertyPixelHeight] as? Int,
                  w > 0, h > 0, w <= 256, h <= 256 else { throw CharacterImportError.corrupt }
        }
    }
    private static func png(_ data: Data) throws -> CharacterImport {
        var offset = 8, chunks = 0, sawHeader = false, sawImage = false, ended = false
        var candidates: [(String, Data)] = [], raster = pngSignature, metadataBytes = 0
        func number(_ i: Int) -> Int { data[i..<(i + 4)].reduce(0) { ($0 << 8) | Int($1) } }
        while offset < data.count {
            guard data.count - offset >= 12, !ended, chunks < 4096 else { throw CharacterImportError.corrupt }
            let length = number(offset)
            guard length <= 8 * 1024 * 1024, length <= data.count - offset - 12 else { throw CharacterImportError.limit("PNG chunk 长度无效或超过 8 MiB") }
            let start = offset + 8, end = start + length
            let typeData = data[(offset + 4)..<start]
            guard typeData.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) }), (65...90).contains(typeData[typeData.startIndex + 2]),
                  let type = String(data: typeData, encoding: .ascii) else { throw CharacterImportError.corrupt }
            let crcData = data.subdata(in: (offset + 4)..<end)
            let crc = crcData.withUnsafeBytes { crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt(crcData.count)) }
            guard UInt32(crc) == UInt32(number(end)) else { throw CharacterImportError.corrupt }
            if !sawHeader && type != "IHDR" { throw CharacterImportError.corrupt }
            if type == "IHDR" {
                guard !sawHeader, length == 13 else { throw CharacterImportError.corrupt }
                let w = number(start), h = number(start + 4)
                guard w > 0, h > 0, w <= 4096, h <= 4096, w * h <= 8_000_000 else { throw CharacterImportError.limit("PNG 最长边 4096，最多 800 万像素") }
                guard data[start + 10] == 0, data[start + 11] == 0, data[start + 12] <= 1 else { throw CharacterImportError.corrupt }
                sawHeader = true
            } else if type == "IDAT" { sawImage = true }
            else if type == "IEND" { guard length == 0, sawImage else { throw CharacterImportError.corrupt }; ended = true }
            else if typeData.first! < 97 && type != "PLTE" { throw CharacterImportError.corrupt }
            if ["IHDR", "PLTE", "IDAT", "IEND"].contains(type) || (type == "tRNS" && length <= 256) {
                raster.append(data.subdata(in: offset..<(end + 4)))
            }
            if ["tEXt", "zTXt", "iTXt"].contains(type) {
                let payload = data.subdata(in: start..<end)
                if let nul = payload.firstIndex(of: 0) {
                    let key = String(data: payload[..<nul], encoding: .isoLatin1) ?? ""
                    if key == "chara" || key == "ccv3" {
                        guard nul > 0, nul <= 79, candidates.count < 16 else { throw CharacterImportError.corrupt }
                        let text = try metadata(payload, nul: nul, type: type)
                        metadataBytes += text.count
                        guard metadataBytes <= 2 * 1024 * 1024 else { throw CharacterImportError.limit("角色元数据累计超过 2 MiB") }
                        candidates.append((key, text))
                    }
                }
            }
            chunks += 1; offset = end + 4
        }
        guard ended, offset == data.count else { throw CharacterImportError.corrupt }
        guard !candidates.isEmpty else { throw CharacterImportError.missingMetadata }
        var selected: CharacterRecord?, warnings: [String] = []
        for key in ["ccv3", "chara"] {
            for (_, text) in candidates.filter({ $0.0 == key }) {
                let cleaned = Data(text.filter { ![9, 10, 13, 32].contains($0) })
                let decoded = Data(base64Encoded: cleaned) ?? (typeIsRawJSON(text) ? text : Data())
                guard decoded.count <= jsonLimit else { throw CharacterImportError.limit("角色 JSON 最多 512 KiB") }
                do {
                    let value = try json(decoded)
                    if value.spec == (key == "ccv3" ? "chara_card_v3" : "chara_card_v2") { selected = value; break }
                } catch CharacterImportError.limit(let reason) { throw CharacterImportError.limit(reason) }
                catch { /* Try another valid metadata candidate, preferring V3. */ }
                warnings.append("有一段 \(key) 元数据无效；已尝试其他有效版本。")
            }
            if selected != nil { break }
        }
        guard var record = selected else { throw CharacterImportError.invalid }
        // Strip metadata before ImageIO sees it, avoiding decompression of unrelated profile/text chunks.
        guard let source = CGImageSourceCreateWithData(raster as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 256, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary),
              let jpeg = UIImage(cgImage: image).jpegData(compressionQuality: 0.85), jpeg.count <= 128 * 1024 else { throw CharacterImportError.corrupt }
        record.avatarJPEG = jpeg
        return CharacterImport(record: record, originalPNG: data, warnings: warnings)
    }
    private static func typeIsRawJSON(_ data: Data) -> Bool { String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") == true }
    private static func inflate(_ data: Data) throws -> Data {
        var output = Data(count: jsonLimit * 2), length = uLongf(output.count)
        let status = output.withUnsafeMutableBytes { out in data.withUnsafeBytes { input in
            uncompress(out.bindMemory(to: Bytef.self).baseAddress, &length, input.bindMemory(to: Bytef.self).baseAddress, uLong(data.count))
        } }
        guard status == Z_OK else { throw status == Z_BUF_ERROR ? CharacterImportError.limit("解压内容超过 1 MiB") : .corrupt }
        output.count = Int(length); return output
    }
    private static func metadata(_ data: Data, nul: Int, type: String) throws -> Data {
        if type == "tEXt" { return data.subdata(in: (nul + 1)..<data.count) }
        var i = nul + 1
        guard i < data.count else { throw CharacterImportError.corrupt }
        if type == "zTXt" {
            guard data[i] == 0 else { throw CharacterImportError.corrupt }
            return try inflate(data.subdata(in: (i + 1)..<data.count))
        }
        guard i + 2 < data.count, data[i] <= 1, data[i + 1] == 0 else { throw CharacterImportError.corrupt }
        let compressed = data[i] == 1; i += 2
        guard let languageEnd = data[i...].firstIndex(of: 0), languageEnd - i <= 79 else { throw CharacterImportError.corrupt }
        i = languageEnd + 1
        guard i < data.count, let translatedEnd = data[i...].firstIndex(of: 0), String(data: data[i..<translatedEnd], encoding: .utf8) != nil else { throw CharacterImportError.corrupt }
        let text = data.subdata(in: (translatedEnd + 1)..<data.count)
        let decoded = compressed ? try inflate(text) : text
        guard String(data: decoded, encoding: .utf8) != nil else { throw CharacterImportError.corrupt }
        return decoded
    }
}
