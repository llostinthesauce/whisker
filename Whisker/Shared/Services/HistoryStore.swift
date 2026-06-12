import Foundation

@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var entries: [DictationResult] = [] {
        didSet { stats = WhiskerStats.compute(from: entries) }
    }
    // Cached, not computed: RecorderView reads this during body evaluation,
    // which the recording timer triggers every 0.1s.
    @Published private(set) var stats: WhiskerStats = .empty

    private let directory: URL
    private let storeFile: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("history", isDirectory: true)
        storeFile = directory.appendingPathComponent("history.json")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        setFileProtection()
        reload()
    }

    func save(_ result: DictationResult) {
        guard !entries.contains(where: { $0.id == result.id }) else { return }
        entries.insert(result, at: 0)
        if persistEntries() {
            WLogger.history.info("Saved result \(result.id)")
        } else {
            entries.removeAll { $0.id == result.id }
        }
    }

    func delete(_ result: DictationResult) {
        entries.removeAll { $0.id == result.id }
        _ = persistEntries()
    }

    func deleteAll() {
        entries = []
        _ = persistEntries()
        for file in legacyEntryFiles() {
            try? FileManager.default.removeItem(at: file)
        }
        WLogger.history.info("Deleted all history")
    }

    func reload() {
        if let storedEntries = loadStoreFile() {
            entries = storedEntries
            return
        }

        let migratedEntries = loadLegacyEntryFiles()
        if !migratedEntries.isEmpty {
            entries = migratedEntries
            _ = persistEntries()
        }
    }

    private func loadStoreFile() -> [DictationResult]? {
        guard FileManager.default.fileExists(atPath: storeFile.path) else { return nil }

        do {
            let data = try Data(contentsOf: storeFile)
            var decoded = try JSONDecoder().decode([DictationResult].self, from: data)
            decoded.sort { $0.createdAt > $1.createdAt }
            return decoded
        } catch {
            WLogger.history.error("Failed to load history store: \(error)")
            return nil
        }
    }

    private func loadLegacyEntryFiles() -> [DictationResult] {
        let decoder = JSONDecoder()
        var loaded: [DictationResult] = legacyEntryFiles().compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(DictationResult.self, from: data)
        }
        loaded.sort { $0.createdAt > $1.createdAt }
        return loaded
    }

    private func legacyEntryFiles() -> [URL] {
        do {
            return try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )
            .filter { $0.pathExtension == "json" && $0.lastPathComponent != storeFile.lastPathComponent }
        } catch {
            WLogger.history.error("Failed to list history directory: \(error)")
            return []
        }
    }

    private func persistEntries() -> Bool {
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: storeFile, options: [.atomic, .completeFileProtectionUnlessOpen])
            try? (storeFile as NSURL).setResourceValue(
                URLFileProtection.completeUnlessOpen,
                forKey: .fileProtectionKey
            )
            return true
        } catch {
            WLogger.history.error("Failed to persist history store: \(error)")
            return false
        }
    }

    private func setFileProtection() {
        try? (directory as NSURL).setResourceValue(
            URLFileProtection.completeUnlessOpen,
            forKey: .fileProtectionKey
        )
    }
}
