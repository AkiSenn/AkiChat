import Foundation

enum CharacterImportService {
    private static let worker = DispatchQueue(label: "com.akisenn.akichat.character-import", qos: .userInitiated)
    static func load(_ url: URL, completion: @escaping (Result<CharacterImport, Error>) -> Void) {
        worker.async {
            let result = Result { () throws -> CharacterImport in
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                guard values.isRegularFile == true, let size = values.fileSize, size <= CharacterCardParser.fileLimit else { throw CharacterImportError.limit("文件最多 16 MiB") }
                let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
                let data = try handle.read(upToCount: CharacterCardParser.fileLimit + 1) ?? Data()
                return try CharacterCardParser.parse(data)
            }
            DispatchQueue.main.async { completion(result) }
        }
    }
}

enum CharacterAssetStore {
    /// Original PNGs are retained locally, including unknown embedded assets. Never resolve card URLs.
    static func save(_ data: Data, id: UUID) throws {
        guard data.count <= CharacterCardParser.fileLimit, data.starts(with: CharacterCardParser.pngSignature) else { throw CharacterImportError.corrupt }
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        var folder = support.appendingPathComponent("CharacterAssets", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var values = URLResourceValues(); values.isExcludedFromBackup = true; try folder.setResourceValues(values)
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])
        let existing = try files.reduce(0) { $0 + (try $1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }
        guard existing + data.count <= 128 * 1024 * 1024 else { throw CharacterImportError.limit("原始角色 PNG 资源总量最多 128 MiB") }
        try data.write(to: folder.appendingPathComponent(id.uuidString + ".png"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
