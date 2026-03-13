import Foundation

/// Memory-mapped dictionary with binary search.
/// Loads a sorted newline-delimited word list via mmap — near-zero RAM usage.
final class MappedDictionary: @unchecked Sendable {
    private let data: Data

    private init(data: Data) {
        self.data = data
    }

    static func load(resource: String) -> MappedDictionary? {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "txt") else {
            DrukarLog.warning("MappedDictionary: missing \(resource).txt in bundle")
            return nil
        }

        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            DrukarLog.info("MappedDictionary: mmap \(resource).txt — \(data.count) bytes")
            return MappedDictionary(data: data)
        } catch {
            DrukarLog.warning("MappedDictionary: failed to mmap \(resource).txt — \(error)")
            return nil
        }
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
}
