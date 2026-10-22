import Foundation
import Combine

/// Bounded, cancelable JSON networking. Refuses redirects so credentials cannot move hosts.
final class JSONHTTPClient: NSObject, URLSessionDataDelegate, Cancellable {
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var data = Data()
    private var completion: ((Result<Data, Error>) -> Void)?
    private let lock = NSLock()
    func start(_ request: URLRequest, configuration: URLSessionConfiguration = .ephemeral,
               completion: @escaping (Result<Data, Error>) -> Void) {
        self.completion = completion
        configuration.urlCache = nil; configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = request.timeoutInterval
        configuration.timeoutIntervalForResource = request.timeoutInterval + 10
        let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        task = session?.dataTask(with: request); task?.resume()
    }
    func cancel() { task?.cancel(); finish(.failure(URLError(.cancelled))) }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let response = response as? HTTPURLResponse else { completionHandler(.cancel); finish(.failure(AppError.malformed)); return }
        guard (200...299).contains(response.statusCode) else { completionHandler(.cancel); finish(.failure(AppError.http(response.statusCode))); return }
        completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil); finish(.failure(AppError.validation("服务返回重定向，请填写最终 HTTPS 地址。")))
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        data.append(chunk)
        if data.count > 4 * 1024 * 1024 { task?.cancel(); finish(.failure(AppError.validation("服务响应超过 4 MiB 限制"))) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error { finish(.failure(error)) } else { finish(.success(data)) }
    }
    private func finish(_ result: Result<Data, Error>) {
        lock.lock(); let callback = completion; completion = nil; lock.unlock()
        guard let callback = callback else { return }
        session?.invalidateAndCancel()
        DispatchQueue.main.async { callback(result) }
    }
    static func request(url: URL, key: String, method: String = "GET", body: [String: Any]? = nil, timeout: Double = 30, headers: [String: String] = [:]) throws -> URLRequest {
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !key.contains("\n"), !key.contains("\r") else { throw AppError.validation("请先保存 API Key") }
        var request = URLRequest(url: url); request.httpMethod = method; request.timeoutInterval = min(300, max(10, timeout))
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (name, value) in headers {
            guard RequestBuilder.safeHeader(name), !value.contains("\r"), !value.contains("\n") else { throw AppError.validation("自定义 Header 无效") }
            request.setValue(value, forHTTPHeaderField: name)
        }
        if let body = body { request.httpBody = try JSONSerialization.data(withJSONObject: body); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return request
    }
}
