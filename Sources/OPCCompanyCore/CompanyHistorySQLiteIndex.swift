import Foundation
import SQLite3

public struct CompanyHistoryIndexStats: Equatable, Sendable {
    public var recordCount: Int
    public var productCount: Int
    public var lastIndexedAt: Date?

    public init(recordCount: Int, productCount: Int, lastIndexedAt: Date?) {
        self.recordCount = recordCount
        self.productCount = productCount
        self.lastIndexedAt = lastIndexedAt
    }
}

public struct CompanyHistoryArchiveStats: Equatable, Sendable {
    public var archivedRecordCount: Int
    public var productCount: Int
    public var cutoffAt: Date
    public var lastArchivedAt: Date?

    public init(archivedRecordCount: Int, productCount: Int, cutoffAt: Date, lastArchivedAt: Date?) {
        self.archivedRecordCount = archivedRecordCount
        self.productCount = productCount
        self.cutoffAt = cutoffAt
        self.lastArchivedAt = lastArchivedAt
    }
}

public struct CompanyHistorySearchResult: Equatable, Sendable {
    public var id: String
    public var productID: UUID?
    public var agentID: UUID?
    public var taskID: UUID?
    public var kind: String
    public var subtype: String
    public var title: String
    public var body: String
    public var createdAt: Date

    public init(id: String, productID: UUID?, agentID: UUID?, taskID: UUID?, kind: String, subtype: String, title: String, body: String, createdAt: Date) {
        self.id = id
        self.productID = productID
        self.agentID = agentID
        self.taskID = taskID
        self.kind = kind
        self.subtype = subtype
        self.title = title
        self.body = body
        self.createdAt = createdAt
    }
}

public enum CompanyHistorySQLiteIndex {
    public enum IndexError: Error, Equatable {
        case openFailed(String)
        case executeFailed(String)
        case prepareFailed(String)
        case stepFailed(String)
    }

    public static func rebuild(snapshot: CompanySnapshot, at databaseURL: URL) throws -> CompanyHistoryIndexStats {
        try FileManager.default.createDirectory(at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let database = try openDatabase(at: databaseURL)
        defer { sqlite3_close(database) }

        try execute(schemaSQL, database: database)
        try execute("BEGIN IMMEDIATE TRANSACTION;", database: database)
        do {
            try execute("DELETE FROM history_records;", database: database)
            try execute("DELETE FROM history_meta;", database: database)
            let records = makeRecords(from: snapshot)
            try insert(records: records, database: database)
            let indexedAt = Date()
            try writeMeta(key: "last_indexed_at", value: formatDate(indexedAt), database: database)
            try writeMeta(key: "schema_version", value: "\(snapshot.schemaVersion)", database: database)
            try execute("COMMIT;", database: database)
            return CompanyHistoryIndexStats(
                recordCount: records.count,
                productCount: Set(records.compactMap(\.productID)).count,
                lastIndexedAt: indexedAt
            )
        } catch {
            try? execute("ROLLBACK;", database: database)
            throw error
        }
    }

    public static func stats(at databaseURL: URL) throws -> CompanyHistoryIndexStats {
        let database = try openDatabase(at: databaseURL)
        defer { sqlite3_close(database) }

        let recordCount = try intValue("SELECT COUNT(*) FROM history_records;", database: database)
        let productCount = try intValue("SELECT COUNT(DISTINCT product_id) FROM history_records WHERE product_id IS NOT NULL AND product_id != '';", database: database)
        let indexedAtText = try stringValue("SELECT value FROM history_meta WHERE key = 'last_indexed_at' LIMIT 1;", database: database)
        return CompanyHistoryIndexStats(recordCount: recordCount, productCount: productCount, lastIndexedAt: indexedAtText.flatMap(parseDate))
    }

    public static func archive(snapshot: CompanySnapshot, at databaseURL: URL, olderThan cutoffAt: Date) throws -> CompanyHistoryArchiveStats {
        try FileManager.default.createDirectory(at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let database = try openDatabase(at: databaseURL)
        defer { sqlite3_close(database) }

        try execute(schemaSQL, database: database)
        let records = makeRecords(from: snapshot).filter { record in
            archiveKinds.contains(record.kind) && record.createdAt < cutoffAt
        }
        try execute("BEGIN IMMEDIATE TRANSACTION;", database: database)
        do {
            try insertArchive(records: records, archivedAt: Date(), database: database)
            let archivedAt = Date()
            try writeMeta(key: "last_archived_at", value: formatDate(archivedAt), database: database)
            try writeMeta(key: "archive_cutoff_at", value: formatDate(cutoffAt), database: database)
            try execute("COMMIT;", database: database)
            return CompanyHistoryArchiveStats(
                archivedRecordCount: records.count,
                productCount: Set(records.compactMap(\.productID)).count,
                cutoffAt: cutoffAt,
                lastArchivedAt: archivedAt
            )
        } catch {
            try? execute("ROLLBACK;", database: database)
            throw error
        }
    }

    public static func archiveStats(at databaseURL: URL) throws -> CompanyHistoryArchiveStats {
        let database = try openDatabase(at: databaseURL)
        defer { sqlite3_close(database) }

        try execute(schemaSQL, database: database)
        let recordCount = try intValue("SELECT COUNT(*) FROM history_archives;", database: database)
        let productCount = try intValue("SELECT COUNT(DISTINCT product_id) FROM history_archives WHERE product_id IS NOT NULL AND product_id != '';", database: database)
        let cutoffText = try stringValue("SELECT value FROM history_meta WHERE key = 'archive_cutoff_at' LIMIT 1;", database: database)
        let archivedAtText = try stringValue("SELECT value FROM history_meta WHERE key = 'last_archived_at' LIMIT 1;", database: database)
        return CompanyHistoryArchiveStats(
            archivedRecordCount: recordCount,
            productCount: productCount,
            cutoffAt: cutoffText.flatMap(parseDate) ?? .distantPast,
            lastArchivedAt: archivedAtText.flatMap(parseDate)
        )
    }

    public static func search(at databaseURL: URL, query: String, productID: UUID? = nil, limit: Int = 20) throws -> [CompanyHistorySearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let database = try openDatabase(at: databaseURL)
        defer { sqlite3_close(database) }

        let clampedLimit = max(1, min(limit, 100))
        let sql: String
        if productID == nil {
            sql = """
            SELECT id, product_id, agent_id, task_id, kind, subtype, title, body, created_at
            FROM history_records
            WHERE title LIKE ? ESCAPE '\\' OR body LIKE ? ESCAPE '\\'
            ORDER BY created_at DESC
            LIMIT ?;
            """
        } else {
            sql = """
            SELECT id, product_id, agent_id, task_id, kind, subtype, title, body, created_at
            FROM history_records
            WHERE product_id = ? AND (title LIKE ? ESCAPE '\\' OR body LIKE ? ESCAPE '\\')
            ORDER BY created_at DESC
            LIMIT ?;
            """
        }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw IndexError.prepareFailed(errorMessage(database))
        }
        defer { sqlite3_finalize(statement) }

        let pattern = "%\(escapeLikePattern(trimmed))%"
        if let productID {
            bindText(productID.uuidString, at: 1, statement: statement)
            bindText(pattern, at: 2, statement: statement)
            bindText(pattern, at: 3, statement: statement)
            sqlite3_bind_int(statement, 4, Int32(clampedLimit))
        } else {
            bindText(pattern, at: 1, statement: statement)
            bindText(pattern, at: 2, statement: statement)
            sqlite3_bind_int(statement, 3, Int32(clampedLimit))
        }

        var results: [CompanyHistorySearchResult] = []
        while true {
            let code = sqlite3_step(statement)
            if code == SQLITE_ROW {
                let createdAtText = columnText(statement, 8) ?? ""
                results.append(CompanyHistorySearchResult(
                    id: columnText(statement, 0) ?? "",
                    productID: columnText(statement, 1).flatMap(UUID.init(uuidString:)),
                    agentID: columnText(statement, 2).flatMap(UUID.init(uuidString:)),
                    taskID: columnText(statement, 3).flatMap(UUID.init(uuidString:)),
                    kind: columnText(statement, 4) ?? "",
                    subtype: columnText(statement, 5) ?? "",
                    title: columnText(statement, 6) ?? "",
                    body: columnText(statement, 7) ?? "",
                    createdAt: parseDate(createdAtText) ?? .distantPast
                ))
            } else if code == SQLITE_DONE {
                break
            } else {
                throw IndexError.stepFailed(errorMessage(database))
            }
        }
        return results
    }

    private struct IndexedRecord {
        var id: String
        var productID: UUID?
        var agentID: UUID?
        var taskID: UUID?
        var kind: String
        var subtype: String
        var title: String
        var body: String
        var createdAt: Date
        var encodedJSON: String
    }

    private static let archiveKinds: Set<String> = [
        "chat_message",
        "event",
        "communication_log",
        "agent_message"
    ]

    private static let schemaSQL = """
    PRAGMA journal_mode = WAL;
    CREATE TABLE IF NOT EXISTS history_records (
      id TEXT PRIMARY KEY NOT NULL,
      product_id TEXT,
      agent_id TEXT,
      task_id TEXT,
      kind TEXT NOT NULL,
      subtype TEXT NOT NULL,
      title TEXT NOT NULL,
      body TEXT NOT NULL,
      created_at TEXT NOT NULL,
      encoded_json TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_history_product_created ON history_records(product_id, created_at);
    CREATE INDEX IF NOT EXISTS idx_history_agent_created ON history_records(agent_id, created_at);
    CREATE INDEX IF NOT EXISTS idx_history_task_created ON history_records(task_id, created_at);
    CREATE INDEX IF NOT EXISTS idx_history_kind_created ON history_records(kind, created_at);
    CREATE TABLE IF NOT EXISTS history_meta (
      key TEXT PRIMARY KEY NOT NULL,
      value TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS history_archives (
      id TEXT PRIMARY KEY NOT NULL,
      product_id TEXT,
      agent_id TEXT,
      task_id TEXT,
      kind TEXT NOT NULL,
      subtype TEXT NOT NULL,
      title TEXT NOT NULL,
      body TEXT NOT NULL,
      created_at TEXT NOT NULL,
      archived_at TEXT NOT NULL,
      encoded_json TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_history_archive_product_created ON history_archives(product_id, created_at);
    CREATE INDEX IF NOT EXISTS idx_history_archive_kind_created ON history_archives(kind, created_at);
    """

    private static func makeRecords(from snapshot: CompanySnapshot) -> [IndexedRecord] {
        var records: [IndexedRecord] = []
        records.reserveCapacity(
            snapshot.messages.count
                + snapshot.events.count
                + snapshot.tasks.count
                + snapshot.workQueue.count
                + snapshot.approvals.count
                + snapshot.artifacts.count
                + snapshot.verifications.count
                + snapshot.memories.count
                + snapshot.communicationLogs.count
                + snapshot.reviewGates.count
                + snapshot.agentMessages.count
        )

        for message in snapshot.messages {
            records.append(record(
                id: message.id,
                productID: message.productID,
                agentID: message.agentID,
                taskID: nil,
                kind: "chat_message",
                subtype: message.author.rawValue,
                title: message.author == .user ? "老板消息".L() : "员工对话".L(),
                body: message.text,
                createdAt: message.createdAt,
                source: message
            ))
        }

        for event in snapshot.events {
            records.append(record(
                id: event.id,
                productID: event.productID,
                agentID: event.agentID,
                taskID: nil,
                kind: "event",
                subtype: event.kind.rawValue,
                title: event.title,
                body: event.detail,
                createdAt: event.createdAt,
                source: event
            ))
        }

        for task in snapshot.tasks {
            records.append(record(
                id: task.id,
                productID: task.productID,
                agentID: task.ownerID,
                taskID: task.id,
                kind: "task",
                subtype: task.status.rawValue,
                title: task.title,
                body: task.successCriteria,
                createdAt: Date(timeIntervalSince1970: 0),
                source: task
            ))
        }

        for item in snapshot.workQueue {
            records.append(record(
                id: item.id,
                productID: item.productID,
                agentID: item.agentID,
                taskID: item.taskID,
                kind: "work_item",
                subtype: item.status.rawValue,
                title: "员工工作项".L(),
                body: item.promptPreview,
                createdAt: item.createdAt,
                source: item
            ))
        }

        for approval in snapshot.approvals {
            records.append(record(
                id: approval.id,
                productID: approval.productID,
                agentID: approval.requesterID,
                taskID: approval.taskID,
                kind: "approval",
                subtype: approval.status.rawValue,
                title: approval.title,
                body: approval.reason,
                createdAt: approval.createdAt,
                source: approval
            ))
        }

        for artifact in snapshot.artifacts {
            records.append(record(
                id: artifact.id,
                productID: artifact.productID,
                agentID: nil,
                taskID: artifact.taskID,
                kind: "artifact",
                subtype: artifact.kind.rawValue,
                title: artifact.title,
                body: "\(artifact.summary)\n\(artifact.path)",
                createdAt: artifact.createdAt,
                source: artifact
            ))
        }

        for verification in snapshot.verifications {
            records.append(record(
                id: verification.id,
                productID: verification.productID,
                agentID: nil,
                taskID: nil,
                kind: "verification",
                subtype: verification.status.rawValue,
                title: verification.title,
                body: verification.detail,
                createdAt: verification.createdAt,
                source: verification
            ))
        }

        for memory in snapshot.memories {
            records.append(record(
                id: memory.id,
                productID: memory.productID,
                agentID: memory.agentID,
                taskID: nil,
                kind: "memory",
                subtype: memory.kind.rawValue,
                title: memory.title,
                body: memory.detail,
                createdAt: memory.createdAt,
                source: memory
            ))
        }

        for log in snapshot.communicationLogs {
            records.append(record(
                id: log.id,
                productID: log.productID,
                agentID: log.agentID,
                taskID: nil,
                kind: "communication_log",
                subtype: "\(log.direction.rawValue).\(log.status.rawValue)",
                title: log.title,
                body: log.body,
                createdAt: log.createdAt,
                source: log
            ))
        }

        for gate in snapshot.reviewGates {
            records.append(record(
                id: gate.id,
                productID: gate.productID,
                agentID: gate.reviewerID ?? gate.requesterID,
                taskID: gate.taskID,
                kind: "review_gate",
                subtype: gate.status.rawValue,
                title: "验收门禁".L(),
                body: gate.summary,
                createdAt: gate.updatedAt,
                source: gate
            ))
        }

        for message in snapshot.agentMessages {
            records.append(record(
                id: message.id,
                productID: message.productID,
                agentID: message.toAgentID ?? message.fromAgentID,
                taskID: message.taskID,
                kind: "agent_message",
                subtype: "\(message.kind.rawValue).\(message.status.rawValue)",
                title: message.subject,
                body: message.body,
                createdAt: message.createdAt,
                source: message
            ))
        }

        return records
    }

    private static func record<T: Encodable>(id: UUID, productID: UUID?, agentID: UUID?, taskID: UUID?, kind: String, subtype: String, title: String, body: String, createdAt: Date, source: T) -> IndexedRecord {
        IndexedRecord(
            id: id.uuidString,
            productID: productID,
            agentID: agentID,
            taskID: taskID,
            kind: kind,
            subtype: subtype,
            title: title,
            body: body,
            createdAt: createdAt,
            encodedJSON: encode(source)
        )
    }

    private static func encode<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private static func insert(records: [IndexedRecord], database: OpaquePointer) throws {
        let sql = """
        INSERT OR REPLACE INTO history_records
        (id, product_id, agent_id, task_id, kind, subtype, title, body, created_at, encoded_json)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw IndexError.prepareFailed(errorMessage(database))
        }
        defer { sqlite3_finalize(statement) }

        for record in records {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            bindText(record.id, at: 1, statement: statement)
            bindOptionalText(record.productID?.uuidString, at: 2, statement: statement)
            bindOptionalText(record.agentID?.uuidString, at: 3, statement: statement)
            bindOptionalText(record.taskID?.uuidString, at: 4, statement: statement)
            bindText(record.kind, at: 5, statement: statement)
            bindText(record.subtype, at: 6, statement: statement)
            bindText(record.title, at: 7, statement: statement)
            bindText(record.body, at: 8, statement: statement)
            bindText(formatDate(record.createdAt), at: 9, statement: statement)
            bindText(record.encodedJSON, at: 10, statement: statement)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw IndexError.stepFailed(errorMessage(database))
            }
        }
    }

    private static func insertArchive(records: [IndexedRecord], archivedAt: Date, database: OpaquePointer) throws {
        let sql = """
        INSERT OR REPLACE INTO history_archives
        (id, product_id, agent_id, task_id, kind, subtype, title, body, created_at, archived_at, encoded_json)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw IndexError.prepareFailed(errorMessage(database))
        }
        defer { sqlite3_finalize(statement) }

        let archivedAtText = formatDate(archivedAt)
        for record in records {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            bindText(record.id, at: 1, statement: statement)
            bindOptionalText(record.productID?.uuidString, at: 2, statement: statement)
            bindOptionalText(record.agentID?.uuidString, at: 3, statement: statement)
            bindOptionalText(record.taskID?.uuidString, at: 4, statement: statement)
            bindText(record.kind, at: 5, statement: statement)
            bindText(record.subtype, at: 6, statement: statement)
            bindText(record.title, at: 7, statement: statement)
            bindText(record.body, at: 8, statement: statement)
            bindText(formatDate(record.createdAt), at: 9, statement: statement)
            bindText(archivedAtText, at: 10, statement: statement)
            bindText(record.encodedJSON, at: 11, statement: statement)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw IndexError.stepFailed(errorMessage(database))
            }
        }
    }

    private static func writeMeta(key: String, value: String, database: OpaquePointer) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "INSERT OR REPLACE INTO history_meta(key, value) VALUES (?, ?);", -1, &statement, nil) == SQLITE_OK, let statement else {
            throw IndexError.prepareFailed(errorMessage(database))
        }
        defer { sqlite3_finalize(statement) }
        bindText(key, at: 1, statement: statement)
        bindText(value, at: 2, statement: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw IndexError.stepFailed(errorMessage(database))
        }
    }

    private static func openDatabase(at url: URL) throws -> OpaquePointer {
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &database, flags, nil) == SQLITE_OK, let database else {
            let message = database.map(errorMessage) ?? "无法打开本地历史索引。".L()
            if let database { sqlite3_close(database) }
            throw IndexError.openFailed(message)
        }
        return database
    }

    private static func execute(_ sql: String, database: OpaquePointer) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? errorMessage(database)
            sqlite3_free(error)
            throw IndexError.executeFailed(message)
        }
    }

    private static func intValue(_ sql: String, database: OpaquePointer) throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw IndexError.prepareFailed(errorMessage(database))
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(statement, 0))
    }

    private static func stringValue(_ sql: String, database: OpaquePointer) throws -> String? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw IndexError.prepareFailed(errorMessage(database))
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return columnText(statement, 0)
    }

    private static func bindOptionalText(_ value: String?, at index: Int32, statement: OpaquePointer) {
        if let value {
            bindText(value, at: index, statement: statement)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private static func bindText(_ value: String, at index: Int32, statement: OpaquePointer) {
        sqlite3_bind_text(statement, index, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    }

    private static func columnText(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard let text = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: text)
    }

    private static func errorMessage(_ database: OpaquePointer) -> String {
        String(cString: sqlite3_errmsg(database))
    }

    private static func escapeLikePattern(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    private static func formatDate(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func parseDate(_ value: String) -> Date? {
        ISO8601DateFormatter().date(from: value)
    }
}
