import Foundation

/// Turns what the user typed or pasted into an existing filesystem location.
enum PathResolver {
    struct Target {
        let path: String
        let isDirectory: Bool
    }

    /// `base` is the folder relative paths resolve against (the Finder window's folder).
    static func resolve(_ input: String, relativeTo base: String?) -> Target? {
        for candidate in spellings(of: input) {
            let path = absolute(candidate, base: base)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDir) {
                return Target(path: path, isDirectory: isDir.boolValue)
            }
        }
        return nil
    }

    /// Tab completion: extends the last path component as far as all matching entries agree.
    /// Returns nil when nothing can be added.
    static func complete(_ text: String, relativeTo base: String?) -> String? {
        let slash = text.lastIndex(of: "/")
        let dirText = slash.map { String(text[...$0]) } ?? ""
        let prefix = slash.map { String(text[text.index(after: $0)...]) } ?? text
        let dir = dirText.isEmpty ? (base ?? NSHomeDirectory()) : absolute(dirText, base: base)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return nil }

        let matches = names.filter {
            (prefix.hasPrefix(".") || !$0.hasPrefix(".")) && $0.lowercased().hasPrefix(prefix.lowercased())
        }.sorted()
        guard let first = matches.first else { return nil }

        var common = first
        for name in matches.dropFirst() {
            common = String(zip(common, name).prefix { $0.lowercased() == $1.lowercased() }.map(\.0))
        }
        var completed = dirText + common
        if matches.count == 1 {
            var isDir: ObjCBool = false
            let path = (dir as NSString).appendingPathComponent(first)
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                completed += "/"
            }
        }
        return completed == text ? nil : completed
    }

    /// Spellings to try: the text as given, then with shell escapes (`My\ Folder`) removed.
    /// Surrounding quotes and file:// URLs, common in pasted paths, are unwrapped first.
    private static func spellings(of input: String) -> [String] {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count >= 2, let quote = text.first, quote == text.last, quote == "\"" || quote == "'" {
            text = String(text.dropFirst().dropLast())
        }
        if text.hasPrefix("file://"), let url = URL(string: text), url.isFileURL {
            text = url.path
        }
        guard !text.isEmpty else { return [] }
        let unescaped = text.replacingOccurrences(of: #"\\(.)"#, with: "$1", options: .regularExpression)
        return unescaped == text ? [text] : [text, unescaped]
    }

    private static func absolute(_ text: String, base: String?) -> String {
        var path = (text as NSString).expandingTildeInPath
        if !path.hasPrefix("/") {
            path = ((base ?? NSHomeDirectory()) as NSString).appendingPathComponent(path)
        }
        return (path as NSString).standardizingPath
    }
}
