import Foundation

/// CPU work is serial and cancellable; only delivery and snapshot validation use main.
final class CatalogWorker {
    private let queue: OperationQueue
    #if DEBUG
    var onSubmit: (() -> Void)?
    #endif
    init(queue: OperationQueue? = nil) {
        self.queue = queue ?? OperationQueue()
        self.queue.maxConcurrentOperationCount = 1
        self.queue.qualityOfService = .userInitiated
    }
    @discardableResult
    func submit<T>(_ work: @escaping () -> T, completion: @escaping (T) -> Void) -> BlockOperation {
        let operation = BlockOperation()
        operation.addExecutionBlock { [weak operation] in
            guard let operation = operation, !operation.isCancelled else { return }
            let value = work()
            guard !operation.isCancelled else { return }
            DispatchQueue.main.async {
                guard !operation.isCancelled else { return }
                completion(value)
            }
        }
        #if DEBUG
        onSubmit?()
        #endif
        queue.addOperation(operation)
        return operation
    }
}
