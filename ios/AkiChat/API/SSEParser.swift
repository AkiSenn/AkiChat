import Foundation

/// Parses bytes, not independently decoded network chunks: split UTF-8 stays intact.
struct SSEParser {
    private var line = Data()
    private var eventLines: [String] = []
    private var pendingCR = false
    private var started = false
    private var eventBytes = 0
    mutating func feed(_ data: Data) throws -> [String] {
        var events: [String] = []
        for byte in data {
            if pendingCR {
                pendingCR = false
                if byte == 10 { continue }
            }
            if byte == 13 || byte == 10 {
                try finishLine(into: &events)
                pendingCR = byte == 13
            } else {
                line.append(byte)
                guard line.count <= 2 * 1024 * 1024 else { throw AppError.malformed }
            }
        }
        return events
    }
    mutating func finish() throws -> [String] {
        // EOF is not a blank-line event delimiter; incomplete events are rejected.
        guard line.isEmpty && eventLines.isEmpty else { throw AppError.interrupted }
        return []
    }
    private mutating func finishLine(into events: inout [String]) throws {
        guard var text = String(data: line, encoding: .utf8) else { throw AppError.malformed }
        line.removeAll(keepingCapacity: true)
        if !started { started = true; if text.hasPrefix("\u{feff}") { text.removeFirst() } }
        if text.isEmpty {
            if !eventLines.isEmpty { events.append(eventLines.joined(separator: "\n")); eventLines.removeAll(keepingCapacity: true) }
            eventBytes = 0
        } else if text.hasPrefix("data:") || text == "data" {
            var value = text == "data" ? "" : String(text.dropFirst(5))
            if value.hasPrefix(" ") { value.removeFirst() }
            eventBytes += value.utf8.count
            guard eventBytes <= 2 * 1024 * 1024 else { throw AppError.malformed }
            eventLines.append(value)
        }
    }
}

struct ChatEnvelope: Decodable {
    struct Choice: Decodable {
        struct Part: Decodable { var content: String?; var reasoning_content: String? }
        var delta: Part?
        var message: Part?
        var finish_reason: String?
    }
    struct Failure: Decodable { var message: String? }
    var choices: [Choice]?
    var usage: TokenUsage?
    var error: Failure?
    static func decode(_ data: Data) throws -> ChatEnvelope {
        do {
            let envelope = try JSONDecoder().decode(ChatEnvelope.self, from: data)
            guard envelope.error == nil, envelope.choices != nil || envelope.usage != nil else { throw AppError.malformed }
            return envelope
        } catch { throw AppError.malformed }
    }
}
