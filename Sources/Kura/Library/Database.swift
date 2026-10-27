import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct DatabaseError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// 一行查询结果，按列序号取值
struct Row {
    fileprivate let values: [Any?]

    func string(_ i: Int) -> String { values[i] as? String ?? "" }
    func optionalString(_ i: Int) -> String? { values[i] as? String }
    func int(_ i: Int) -> Int {
        if let v = values[i] as? Int64 { return Int(v) }
        if let v = values[i] as? Double { return Int(v) }
        return 0
    }
    func optionalDouble(_ i: Int) -> Double? {
        if let v = values[i] as? Double { return v }
        if let v = values[i] as? Int64 { return Double(v) }
        return nil
    }
    func date(_ i: Int) -> Date { Date(timeIntervalSince1970: optionalDouble(i) ?? 0) }
    func optionalDate(_ i: Int) -> Date? { optionalDouble(i).map(Date.init(timeIntervalSince1970:)) }
}

/// 对系统 SQLite 的最小封装。只在主线程使用。
final class Database {
    private var handle: OpaquePointer?

    init(path: String) throws {
        guard sqlite3_open_v2(path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "无法打开数据库"
            sqlite3_close(handle)
            throw DatabaseError(message: message)
        }
        sqlite3_busy_timeout(handle, 3000)
        try execute("PRAGMA foreign_keys = ON")
    }

    deinit {
        sqlite3_close(handle)
    }

    func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? "SQLite 错误"
            sqlite3_free(error)
            throw DatabaseError(message: message)
        }
    }

    func run(_ sql: String, _ args: [Any?] = []) throws {
        let statement = try prepare(sql, args)
        defer { sqlite3_finalize(statement) }
        let rc = sqlite3_step(statement)
        guard rc == SQLITE_DONE || rc == SQLITE_ROW else { throw lastError() }
    }

    func query(_ sql: String, _ args: [Any?] = []) throws -> [Row] {
        let statement = try prepare(sql, args)
        defer { sqlite3_finalize(statement) }
        let columns = sqlite3_column_count(statement)
        var rows: [Row] = []
        while true {
            let rc = sqlite3_step(statement)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else { throw lastError() }
            var values: [Any?] = []
            values.reserveCapacity(Int(columns))
            for column in 0..<columns {
                switch sqlite3_column_type(statement, column) {
                case SQLITE_INTEGER: values.append(sqlite3_column_int64(statement, column))
                case SQLITE_FLOAT: values.append(sqlite3_column_double(statement, column))
                case SQLITE_TEXT: values.append(String(cString: sqlite3_column_text(statement, column)))
                default: values.append(nil)
                }
            }
            rows.append(Row(values: values))
        }
        return rows
    }

    func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try body()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func prepare(_ sql: String, _ args: [Any?]) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { throw lastError() }
        for (offset, arg) in args.enumerated() {
            let index = Int32(offset + 1)
            switch arg {
            case nil: sqlite3_bind_null(statement, index)
            case let value as String: sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
            case let value as Int: sqlite3_bind_int64(statement, index, Int64(value))
            case let value as Int64: sqlite3_bind_int64(statement, index, value)
            case let value as Double: sqlite3_bind_double(statement, index, value)
            case let value as Bool: sqlite3_bind_int64(statement, index, value ? 1 : 0)
            case let value as Date: sqlite3_bind_double(statement, index, value.timeIntervalSince1970)
            default: sqlite3_bind_null(statement, index)
            }
        }
        return statement
    }

    private func lastError() -> DatabaseError {
        DatabaseError(message: handle.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite 错误")
    }
}

enum Schema {
    static func migrate(_ db: Database) throws {
        let version = try db.query("PRAGMA user_version").first?.int(0) ?? 0
        if version < 1 {
            try db.execute("""
            CREATE TABLE IF NOT EXISTS items (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                ext TEXT NOT NULL,
                kind TEXT NOT NULL,
                path TEXT NOT NULL,
                thumb TEXT,
                thumb_rev INTEGER NOT NULL DEFAULT 0,
                size INTEGER NOT NULL DEFAULT 0,
                width INTEGER NOT NULL DEFAULT 0,
                height INTEGER NOT NULL DEFAULT 0,
                duration REAL,
                rating INTEGER NOT NULL DEFAULT 0,
                note TEXT NOT NULL DEFAULT '',
                url TEXT NOT NULL DEFAULT '',
                colors TEXT NOT NULL DEFAULT '',
                added_at REAL NOT NULL,
                modified_at REAL NOT NULL,
                viewed_at REAL,
                deleted_at REAL
            );
            CREATE TABLE IF NOT EXISTS folders (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                parent_id TEXT REFERENCES folders(id) ON DELETE CASCADE,
                color TEXT NOT NULL DEFAULT '',
                sort INTEGER NOT NULL DEFAULT 0,
                created_at REAL NOT NULL
            );
            CREATE TABLE IF NOT EXISTS item_tags (
                item_id TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
                tag TEXT NOT NULL,
                PRIMARY KEY (item_id, tag)
            );
            CREATE TABLE IF NOT EXISTS item_folders (
                item_id TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
                folder_id TEXT NOT NULL REFERENCES folders(id) ON DELETE CASCADE,
                PRIMARY KEY (item_id, folder_id)
            );
            CREATE INDEX IF NOT EXISTS item_tags_tag ON item_tags(tag);
            CREATE INDEX IF NOT EXISTS item_folders_folder ON item_folders(folder_id);
            PRAGMA user_version = 1;
            """)
        }
        if version < 2 {
            try db.execute("""
            ALTER TABLE items ADD COLUMN cover_time REAL;
            PRAGMA user_version = 2;
            """)
        }
        if version < 3 {
            try db.execute("""
            CREATE TABLE IF NOT EXISTS tag_meta (
                tag TEXT PRIMARY KEY,
                icon TEXT NOT NULL
            );
            PRAGMA user_version = 3;
            """)
        }
        if version < 4 {
            // 标签自己的信息：上级和图标。素材上只记标签名，没有素材的父标签也靠这张表留下来
            try db.execute("""
            CREATE TABLE IF NOT EXISTS tags (
                name TEXT PRIMARY KEY,
                parent TEXT,
                icon TEXT
            );
            INSERT OR IGNORE INTO tags (name, icon) SELECT tag, icon FROM tag_meta;
            DROP TABLE IF EXISTS tag_meta;
            PRAGMA user_version = 4;
            """)
        }
    }
}
