import Foundation

struct TagObsidianNoteAction: ForgeAction {
    static let typeId = "tag-obsidian-note"
    static let displayName = "Tag Obsidian Note"
    static let description = "Add or remove YAML frontmatter tags on a markdown file"
    static let configFields: [ActionConfigField] = [
        ActionConfigField(key: "notePath", label: "Note Path (or use trigger file)", placeholder: "/path/to/note.md", required: false, fieldType: .filePicker),
        ActionConfigField(key: "addTags", label: "Tags to Add (comma-separated)", placeholder: "processed, auto"),
        ActionConfigField(key: "removeTags", label: "Tags to Remove (comma-separated)", placeholder: "inbox", required: false),
    ]

    private let notePath: String
    private let addTags: [String]
    private let removeTags: [String]

    init(config: [String: String]) {
        self.notePath = config["notePath"] ?? ""
        self.addTags = (config["addTags"] ?? "")
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        self.removeTags = (config["removeTags"] ?? "")
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    func execute(trigger: TriggerEvent) async throws -> ActionResult {
        let path = notePath.isEmpty ? (trigger.path ?? "") : notePath
        guard !path.isEmpty else {
            return .fail("No note path configured or provided by trigger")
        }

        guard FileManager.default.fileExists(atPath: path) else {
            return .fail("Note not found: \(path)")
        }

        var content = try String(contentsOfFile: path, encoding: .utf8)

        if content.hasPrefix("---\n") {
            // Has frontmatter — find and modify tags
            guard let endIdx = content.range(of: "\n---", range: content.index(content.startIndex, offsetBy: 3)..<content.endIndex) else {
                return .fail("Malformed frontmatter in \(path)")
            }

            let frontmatterRange = content.startIndex..<endIdx.upperBound
            var frontmatter = String(content[frontmatterRange])

            var tags = extractTags(from: frontmatter)
            for tag in addTags where !tags.contains(tag) {
                tags.append(tag)
            }
            tags.removeAll { removeTags.contains($0) }

            frontmatter = replaceTags(in: frontmatter, with: tags)
            content.replaceSubrange(frontmatterRange, with: frontmatter)
        } else {
            // No frontmatter — add it
            let tagList = addTags.map { "\"\($0)\"" }.joined(separator: ", ")
            content = "---\ntags: [\(tagList)]\n---\n\n" + content
        }

        try content.write(toFile: path, atomically: true, encoding: .utf8)

        let fileName = (path as NSString).lastPathComponent
        var summary = [String]()
        if !addTags.isEmpty { summary.append("Added: \(addTags.joined(separator: ", "))") }
        if !removeTags.isEmpty { summary.append("Removed: \(removeTags.joined(separator: ", "))") }
        return .ok(["Tagged \(fileName)"] + summary)
    }

    private func extractTags(from frontmatter: String) -> [String] {
        // Match tags: [tag1, tag2] or tags:\n- tag1\n- tag2
        guard let tagsLine = frontmatter.components(separatedBy: .newlines)
            .first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("tags:") }) else {
            return []
        }

        let value = tagsLine.split(separator: ":", maxSplits: 1).last.map(String.init) ?? ""
        let trimmed = value.trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
            let inner = trimmed.dropFirst().dropLast()
            return inner.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
                .filter { !$0.isEmpty }
        }

        return []
    }

    private func replaceTags(in frontmatter: String, with tags: [String]) -> String {
        let tagList = tags.map { "\"\($0)\"" }.joined(separator: ", ")
        let newTagLine = "tags: [\(tagList)]"

        var lines = frontmatter.components(separatedBy: .newlines)
        if let idx = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("tags:") }) {
            lines[idx] = newTagLine
        } else {
            // Insert before closing ---
            lines.insert(newTagLine, at: max(lines.count - 1, 1))
        }
        return lines.joined(separator: "\n")
    }
}
