import Foundation

enum ModelDiscovery {
    static func parse(_ data: Data, provider: Provider) throws -> [ModelRecord] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], let rows = object["data"] as? [[String: Any]] else { throw AppError.malformed }
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
            model.discovered.tools = row["supports_tools"] as? Bool ?? (row["capabilities"] as? [String: Any])?["tools"] as? Bool ??
                chatCaps["function_calling"] as? Bool ?? chatCaps["tools"] as? Bool
            model.discovered.streaming = chatCaps["streaming"] as? Bool
            model.discovered.systemPrompt = chatCaps["system_prompt"] as? Bool
            if provider.kind == .deepSeek && id == "deepseek-flash" {
                model.discovered.tools = true; model.discovered.prefix = true // documented official preset
            }
            let metadataSource: [String: Any] = provider.kind == .workBuddy ? row : caps
            if let encoded = try? JSONSerialization.data(withJSONObject: metadataSource, options: [.sortedKeys]) { model.metadata = String(decoding: encoded, as: UTF8.self) }
            return model
        }
    }
    static func merge(_ fetched: [ModelRecord], cached: [ModelRecord]) -> [ModelRecord] {
        var result = fetched.map { remote -> ModelRecord in
            var value = remote
            if let old = cached.first(where: { $0.id == remote.id }) {
                value.favorite = old.favorite; value.order = old.order; value.overrides = old.overrides
                value.systemPrompt = old.systemPrompt; value.presetIDs = old.presetIDs
                value.contextWindowOverride = old.contextWindowOverride; value.outputLimitOverride = old.outputLimitOverride
                if old.manual { value.contextWindow = old.contextWindow ?? value.contextWindow; value.outputLimit = old.outputLimit ?? value.outputLimit }
            }
            return value
        }
        // Preserve missing models too, so refresh never destroys a working local configuration.
        result += cached.filter { old in !result.contains(where: { $0.id == old.id }) }
        return result
    }
}
