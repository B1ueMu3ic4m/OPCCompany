import Foundation

public enum ProjectImportScanner {
    public static func scan(rootURL: URL) -> ProjectImportReport {
        let root = rootURL.standardizedFileURL
        let projectName = root.lastPathComponent.isEmpty ? "导入项目".L().L() : root.lastPathComponent
        let shortName = String(projectName.prefix(3)).isEmpty ? "项目".L().L() : String(projectName.prefix(3))

        let ruleFiles = existingPaths(in: root, candidates: [
            "AGENTS.md",
            "CLAUDE.md",
            "GEMINI.md",
            "README.md",
            ".cursorrules",
            ".windsurfrules",
            ".codex",
            ".codex/memories",
            ".claude",
            ".claude/settings.json",
            ".claude/commands",
            ".gemini",
            ".gemini/settings.json"
        ])

        var projectFiles = existingPaths(in: root, candidates: [
            "Package.swift",
            "package.json",
            "pnpm-lock.yaml",
            "yarn.lock",
            "package-lock.json",
            "pyproject.toml",
            "requirements.txt",
            "Cargo.toml",
            "go.mod",
            "Gemfile",
            "Dockerfile",
            "README.md"
        ])
        projectFiles.append(contentsOf: xcodeContainers(in: root))

        let detectedTools = detectedTools(ruleFiles: ruleFiles)
        let summary = """
        \(projectName)\(" 已导入。检测到 ".L())\(detectedTools.count)\(" 类智能工具线索、".L())\(ruleFiles.count)\(" 个规则/记忆位置、".L())\(projectFiles.count)\(" 个项目结构文件。".L())
        """

        return ProjectImportReport(
            projectName: projectName,
            shortName: shortName,
            rootDirectory: root.path,
            ruleFiles: ruleFiles,
            detectedTools: detectedTools,
            projectFiles: Array(projectFiles.prefix(12)),
            summary: summary
        )
    }

    private static func existingPaths(in root: URL, candidates: [String]) -> [String] {
        let manager = FileManager.default
        return candidates.compactMap { candidate in
            let url = root.appendingPathComponent(candidate)
            var isDirectory: ObjCBool = false
            guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return nil }
            return isDirectory.boolValue ? "\(candidate)/" : candidate
        }
    }

    private static func xcodeContainers(in root: URL) -> [String] {
        guard let children = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
            return []
        }
        return children.compactMap { url in
            let name = url.lastPathComponent
            guard name.hasSuffix(".xcodeproj") || name.hasSuffix(".xcworkspace") else { return nil }
            return name
        }
    }

    private static func detectedTools(ruleFiles: [String]) -> [String] {
        var tools: [String] = []
        if ruleFiles.contains(where: { $0 == "AGENTS.md" || $0.hasPrefix(".codex") }) {
            tools.append("Codex")
        }
        if ruleFiles.contains(where: { $0 == "CLAUDE.md" || $0.hasPrefix(".claude") }) {
            tools.append("Claude Code")
        }
        if ruleFiles.contains(where: { $0 == "GEMINI.md" || $0.hasPrefix(".gemini") }) {
            tools.append("Gemini 命令行".L().L())
        }
        return tools
    }
}
