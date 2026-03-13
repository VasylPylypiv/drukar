import Foundation

/// Memory-mapped dictionary with binary search.
/// Loads a sorted newline-delimited word list via mmap — near-zero RAM usage.
/// If the resource is gzip-compressed (.gz), decompresses to cache on first use.
final class MappedDictionary: @unchecked Sendable {
    private let data: Data

    private init(data: Data) {
        self.data = data
    }

    /// Load a sorted word list from a bundle resource.
    static func load(resource: String) -> MappedDictionary? {
        if let url = Bundle.main.url(forResource: resource, withExtension: "txt") {
            do {
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                DrukarLog.info("MappedDictionary: mmap \(resource).txt — \(data.count) bytes")
                return MappedDictionary(data: data)
            } catch {
                DrukarLog.warning("MappedDictionary: failed to mmap \(resource).txt — \(error)")
            }
        }

        if let gzURL = Bundle.main.url(forResource: resource, withExtension: "txt.gz") {
            let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
                .appendingPathComponent("com.vasylpylypiv.inputmethod.Drukar", isDirectory: true)

            guard let cacheDir else {
                DrukarLog.warning("MappedDictionary: cannot find cache directory")
                return nil
            }

            let cachedPath = cacheDir.appendingPathComponent("\(resource).txt")

            if FileManager.default.fileExists(atPath: cachedPath.path) {
                do {
                    let data = try Data(contentsOf: cachedPath, options: .mappedIfSafe)
                    DrukarLog.info("MappedDictionary: mmap cached \(resource).txt — \(data.count) bytes")
                    return MappedDictionary(data: data)
                } catch {
                    DrukarLog.warning("MappedDictionary: cached file unreadable — \(error)")
                }
            }

            do {
                try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
                let decompressed = try decompressGzip(url: gzURL)
                try decompressed.write(to: cachedPath)
                let data = try Data(contentsOf: cachedPath, options: .mappedIfSafe)
                DrukarLog.info("MappedDictionary: decompressed & mmap \(resource).txt — \(data.count) bytes")
                return MappedDictionary(data: data)
            } catch {
                DrukarLog.warning("MappedDictionary: failed to decompress \(resource).txt.gz — \(error)")
                return nil
            }
        }

        DrukarLog.warning("MappedDictionary: missing \(resource).txt(.gz) in bundle")
        return nil
    }

    /// Check if a word exists in the dictionary. O(log n) binary search.
    func contains(_ word: String) -> Bool {
        let target = Array(word.lowercased().utf8)
        guard !target.isEmpty else { return false }

        return data.withUnsafeBytes { buffer -> Bool in
            guard let base = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return false
            }
            let size = buffer.count
            guard size > 0 else { return false }

            var lo = 0
            var hi = size - 1

            while lo <= hi {
                let mid = lo + (hi - lo) / 2
                let lineStart = findLineStart(base: base, from: mid)
                let lineEnd = findLineEnd(base: base, from: lineStart, size: size)
                let lineLen = lineEnd - lineStart

                let cmp = compareBytes(base: base, offset: lineStart, length: lineLen, target: target)

                if cmp == 0 {
                    return true
                } else if cmp < 0 {
                    lo = lineEnd + 1
                    if lo >= size { return false }
                } else {
                    if lineStart == 0 { return false }
                    hi = lineStart - 1
                    if hi < 0 { return false }
                }
            }
            return false
        }
    }

    // MARK: - Binary Search Helpers

    private func findLineStart(base: UnsafePointer<UInt8>, from pos: Int) -> Int {
        var i = pos
        while i > 0 && base[i - 1] != 0x0A {
            i -= 1
        }
        return i
    }

    private func findLineEnd(base: UnsafePointer<UInt8>, from start: Int, size: Int) -> Int {
        var i = start
        while i < size && base[i] != 0x0A {
            i += 1
        }
        return i
    }

    private func compareBytes(base: UnsafePointer<UInt8>, offset: Int, length: Int, target: [UInt8]) -> Int {
        let minLen = min(length, target.count)
        for i in 0..<minLen {
            let a = base[offset + i]
            let b = target[i]
            if a != b { return Int(a) - Int(b) }
        }
        return length - target.count
    }

    // MARK: - Gzip Decompression

    private static func decompressGzip(url: URL) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/gunzip")
        process.arguments = ["-c", url.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        return pipe.fileHandleForReading.readDataToEndOfFile()
    }
}
