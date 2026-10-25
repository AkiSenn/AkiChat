import Foundation

/// Transient discovery feedback; never changes the saved catalog or credential state.
struct ModelDiscoveryIssue {
    enum Kind { case authentication, permission, unsupported, rateLimited, format, timeout, other }
    let kind: Kind
    let message: String
    init(_ error: Error) {
        if let appError = error as? AppError {
            switch appError {
            case .http(401): kind = .authentication; message = "认证失败（401），请检查 API Key。模型列表失败不代表聊天接口一定不可用。"
            case .http(403): kind = .permission; message = "权限不足（403），请检查模型列表访问权限。"
            case .http(let code) where code == 404 || code == 405:
                kind = .unsupported; message = "无法自动获取模型，使用兼容模式。模型列表接口可能不支持（\(code)）；请检查路径，或手动添加模型 ID。"
            case .http(429): kind = .rateLimited; message = "请求限流（429），请稍后重试；已有模型仍可使用。"
            case .malformed: kind = .format; message = "模型列表返回格式不兼容，无法解析 JSON。可以手动添加模型，已有模型已保留。"
            default: kind = .other; message = error.localizedDescription
            }
        } else if (error as NSError).domain == NSURLErrorDomain && (error as NSError).code == URLError.timedOut.rawValue {
            kind = .timeout; message = "连接超时，未能获取模型；请检查网络或稍后重试。已有模型已保留。"
        } else {
            kind = .other; message = error.localizedDescription
        }
    }
}
