import Foundation

enum ModelDiscovery {
    static func filtered(_ models: [ModelRecord], query: String, favoritesOnly: Bool = false) -> [ModelRecord] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return models.filter { (!favoritesOnly || $0.favorite) && (text.isEmpty || $0.name.localizedCaseInsensitiveContains(text) || $0.id.localizedCaseInsensitiveContains(text)) }
            .sorted { a, b in a.favorite != b.favorite ? a.favorite : (a.order != b.order ? a.order < b.order : a.name.localizedStandardCompare(b.name) == .orderedAscending) }
    }
    static func parse(_ data: Data, provider: Provider) throws -> [ModelRecord] {
        let parsed: Any
        do { parsed = try JSONSerialization.jsonObject(with: data) } catch { throw AppError.malformed }
        guard let object = parsed as? [String: Any], let rows = object["data"] as? [[String: Any]] else { throw AppError.malformed }
        guard rows.count <= 5000 else { throw AppError.validation("模型列表超过 5000 条") }
        var ids = Set<String>()
        return rows.compactMap { row in
            guard let id = row["id"] as? String, !id.isEmpty, id.count <= 256, ids.insert(id).inserted else { return nil }
            var model = ModelRecord(id: id, name: row["name"] as? String ?? id)
            model.contextWindow = (row["context_window"] as? Int ?? row["context_length"] as? Int ?? row["max_input_tokens"] as? Int).flatMap { $0 > 0 ? $0 : nil }
            model.outputLimit = (row["max_output_tokens"] as? Int).flatMap { $0 > 0 ? $0 : nil }
            model.inputModalities = row["input_modalities"] as? [String] ?? []
            model.outputModalities = row["output_modalities"] as? [String] ?? []
            model.effort = row["reasoning_efforts"] as? [String] ?? (row["effort"] as? [String: Any])?["supported_levels"] as? [String] ?? []
            let caps = row["api_capabilities"] as? [String: Any] ?? [:]
            let chatCaps = caps["chat_completions"] as? [String: Any] ?? caps
            model.discovered.vision = row["supports_vision"] as? Bool ?? (row["capabilities"] as? [String: Any])?["vision"] as? Bool ??
                (row["input_modalities"] == nil ? nil : model.inputModalities.contains("image"))
            model.discovered.thinking = row["supports_reasoning"] as? Bool ?? (row["capabilities"] as? [String: Any])?["reasoning"] as? Bool ??
                (model.effort.isEmpty && row["reasoning_fixed_effort"] == nil ? nil : true)
            model.discovered.tools = row["supports_tool_calls"] as? Bool ?? (row["capabilities"] as? [String: Any])?["tool_calls"] as? Bool ?? row["supports_tools"] as? Bool ?? (row["capabilities"] as? [String: Any])?["tools"] as? Bool ??
                chatCaps["function_calling"] as? Bool ?? chatCaps["tools"] as? Bool
            model.discovered.streaming = chatCaps["streaming"] as? Bool
            model.discovered.systemPrompt = chatCaps["system_prompt"] as? Bool
            if provider.kind == .deepSeek && id == "deepseek-flash" {
                // An ID-only catalog must not erase the built-in default's capabilities.
                // Explicit remote flags still win; unknown model IDs remain conservative.
                model.discovered.vision = model.discovered.vision ?? Provider.deepSeek.supportsVision
                model.discovered.thinking = model.discovered.thinking ?? Provider.deepSeek.supportsThinking
                model.discovered.tools = model.discovered.tools ?? true
                model.discovered.prefix = model.discovered.prefix ?? true
            }
            let metadataSource: [String: Any] = provider.kind == .workBuddy ? row : caps
            if let encoded = try? JSONSerialization.data(withJSONObject: metadataSource, options: [.sortedKeys]) { model.metadata = String(decoding: encoded, as: UTF8.self) }
            return model
        }
    }
    static func merge(_ fetched: [ModelRecord], cached: [ModelRecord]) -> [ModelRecord] {
        // Keep the first cached duplicate, matching the former first(where:) rule.
        var byID: [String: ModelRecord] = [:]
        for model in cached where byID[model.id] == nil { byID[model.id] = model }
        let fetchedIDs = Set(fetched.map(\.id))
        var result = fetched.map { remote -> ModelRecord in
            var value = remote
            if let old = byID[remote.id] {
                value.favorite = old.favorite; value.order = old.order; value.overrides = old.overrides
                value.manual = old.manual
                value.systemPrompt = old.systemPrompt; value.presetIDs = old.presetIDs
                value.contextWindowOverride = old.contextWindowOverride; value.outputLimitOverride = old.outputLimitOverride
                if old.manual { value.contextWindow = old.contextWindow ?? value.contextWindow; value.outputLimit = old.outputLimit ?? value.outputLimit }
            }
            return value
        }
        // Preserve missing models too, so refresh never destroys a working local configuration.
        result += cached.filter { !fetchedIDs.contains($0.id) }
        return result
    }
}
