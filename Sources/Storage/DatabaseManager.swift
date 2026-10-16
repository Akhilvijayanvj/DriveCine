import Foundation
import SQLite3

/// SQLite3 persistence manager for transfer sessions, download states, and resumable progress
public final class DatabaseManager: @unchecked Sendable {
    public static let shared = DatabaseManager()
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.drivecine.database", qos: .userInitiated)

    private init() {
        openDatabase()
        createTables()
    }

    deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }

    private func getDatabaseURL() -> URL {
        let fileManager = FileManager.default
        if let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let dir = appSupport.appendingPathComponent("DriveCine", isDirectory: true)
            do {
                try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
                let testFile = dir.appendingPathComponent(".write_test")
                try "ok".write(to: testFile, atomically: true, encoding: .utf8)
                try? fileManager.removeItem(at: testFile)
                return dir.appendingPathComponent("drivecine.sqlite3")
            } catch {
                // Application support restricted or not writable in sandbox
            }
        }

        // Resilient fallback to temporary or local storage
        let fallbackDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("DriveCine", isDirectory: true)
        try? fileManager.createDirectory(at: fallbackDir, withIntermediateDirectories: true)
        return fallbackDir.appendingPathComponent("drivecine.sqlite3")
    }

    private func openDatabase() {
        let url = getDatabaseURL()
        if sqlite3_open(url.path, &db) != SQLITE_OK {
            print("Failed to open SQLite database at: \(url.path)")
        } else {
            // Enable WAL mode for high performance concurrent reading and writing
            execute(sql: "PRAGMA journal_mode = WAL;")
            execute(sql: "PRAGMA synchronous = NORMAL;")
        }
    }

    private func execute(sql: String) {
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            if let errMsg = errMsg {
                let msg = String(cString: errMsg)
                print("SQLite exec error: \(msg) on: \(sql)")
                sqlite3_free(errMsg)
            }
        }
    }

    private func createTables() {
        let sqlSessions = """
        CREATE TABLE IF NOT EXISTS sessions (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            root_drive_id TEXT NOT NULL,
            original_url TEXT NOT NULL,
            destination_path TEXT NOT NULL,
            total_files INTEGER NOT NULL,
            total_bytes INTEGER NOT NULL,
            completed_files INTEGER NOT NULL,
            completed_bytes INTEGER NOT NULL,
            status TEXT NOT NULL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        );
        """

        let sqlTasks = """
        CREATE TABLE IF NOT EXISTS tasks (
            id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL,
            drive_file_id TEXT NOT NULL,
            file_name TEXT NOT NULL,
            relative_path TEXT NOT NULL,
            file_size INTEGER NOT NULL,
            downloaded_bytes INTEGER NOT NULL,
            md5_checksum TEXT,
            local_path TEXT NOT NULL,
            status TEXT NOT NULL,
            current_speed REAL NOT NULL,
            error_message TEXT,
            retry_count INTEGER NOT NULL,
            updated_at REAL NOT NULL,
            FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE
        );
        CREATE INDEX IF NOT EXISTS idx_tasks_session ON tasks(session_id);
        CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status);
        """

        let sqlKV = """
        CREATE TABLE IF NOT EXISTS secure_kv (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL,
            updated_at REAL NOT NULL
        );
        """

        execute(sql: sqlSessions)
        execute(sql: sqlTasks)
        execute(sql: sqlKV)
    }

    // MARK: - Sessions

    public func saveSession(_ session: TransferSession) {
        queue.sync {
            let sql = """
            INSERT OR REPLACE INTO sessions 
            (id, name, root_drive_id, original_url, destination_path, total_files, total_bytes, completed_files, completed_bytes, status, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, session.id.uuidString, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 2, session.name, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 3, session.rootDriveId, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 4, session.originalUrl, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 5, session.destinationPath, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int64(stmt, 6, Int64(session.totalFiles))
                sqlite3_bind_int64(stmt, 7, session.totalBytes)
                sqlite3_bind_int64(stmt, 8, Int64(session.completedFiles))
                sqlite3_bind_int64(stmt, 9, session.completedBytes)
                sqlite3_bind_text(stmt, 10, session.status.rawValue, -1, SQLITE_TRANSIENT)
                sqlite3_bind_double(stmt, 11, session.createdAt.timeIntervalSince1970)
                sqlite3_bind_double(stmt, 12, session.updatedAt.timeIntervalSince1970)

                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
    }

    public func updateSessionProgress(sessionId: UUID, completedFiles: Int, completedBytes: Int64, status: SessionStatus) {
        queue.sync {
            let sql = "UPDATE sessions SET completed_files = ?, completed_bytes = ?, status = ?, updated_at = ? WHERE id = ?;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int64(stmt, 1, Int64(completedFiles))
                sqlite3_bind_int64(stmt, 2, completedBytes)
                sqlite3_bind_text(stmt, 3, status.rawValue, -1, SQLITE_TRANSIENT)
                sqlite3_bind_double(stmt, 4, Date().timeIntervalSince1970)
                sqlite3_bind_text(stmt, 5, sessionId.uuidString, -1, SQLITE_TRANSIENT)
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
    }

    public func fetchSessions() -> [TransferSession] {
        return queue.sync {
            var sessions: [TransferSession] = []
            let sql = "SELECT id, name, root_drive_id, original_url, destination_path, total_files, total_bytes, completed_files, completed_bytes, status, created_at, updated_at FROM sessions ORDER BY created_at DESC;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    guard let idStr = sqlite3_column_text(stmt, 0),
                          let id = UUID(uuidString: String(cString: idStr)),
                          let name = sqlite3_column_text(stmt, 1),
                          let rootId = sqlite3_column_text(stmt, 2),
                          let url = sqlite3_column_text(stmt, 3),
                          let dest = sqlite3_column_text(stmt, 4),
                          let statusStr = sqlite3_column_text(stmt, 9) else { continue }

                    let totalFiles = Int(sqlite3_column_int64(stmt, 5))
                    let totalBytes = sqlite3_column_int64(stmt, 6)
                    let completedFiles = Int(sqlite3_column_int64(stmt, 7))
                    let completedBytes = sqlite3_column_int64(stmt, 8)
                    let status = SessionStatus(rawValue: String(cString: statusStr)) ?? .ready
                    let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 10))
                    let updatedAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 11))

                    sessions.append(TransferSession(
                        id: id,
                        name: String(cString: name),
                        rootDriveId: String(cString: rootId),
                        originalUrl: String(cString: url),
                        destinationPath: String(cString: dest),
                        totalFiles: totalFiles,
                        totalBytes: totalBytes,
                        completedFiles: completedFiles,
                        completedBytes: completedBytes,
                        status: status,
                        createdAt: createdAt,
                        updatedAt: updatedAt
                    ))
                }
            }
            sqlite3_finalize(stmt)
            return sessions
        }
    }

    public func deleteSession(_ sessionId: UUID) {
        queue.sync {
            let sqlTasks = "DELETE FROM tasks WHERE session_id = ?;"
            var stmt1: OpaquePointer?
            if sqlite3_prepare_v2(db, sqlTasks, -1, &stmt1, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt1, 1, sessionId.uuidString, -1, SQLITE_TRANSIENT)
                sqlite3_step(stmt1)
            }
            sqlite3_finalize(stmt1)

            let sqlSession = "DELETE FROM sessions WHERE id = ?;"
            var stmt2: OpaquePointer?
            if sqlite3_prepare_v2(db, sqlSession, -1, &stmt2, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt2, 1, sessionId.uuidString, -1, SQLITE_TRANSIENT)
                sqlite3_step(stmt2)
            }
            sqlite3_finalize(stmt2)
        }
    }

    // MARK: - Tasks

    public func saveTasks(_ tasks: [DownloadTask]) {
        queue.sync {
            execute(sql: "BEGIN TRANSACTION;")
            let sql = """
            INSERT OR REPLACE INTO tasks 
            (id, session_id, drive_file_id, file_name, relative_path, file_size, downloaded_bytes, md5_checksum, local_path, status, current_speed, error_message, retry_count, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                for task in tasks {
                    sqlite3_bind_text(stmt, 1, task.id.uuidString, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(stmt, 2, task.sessionId.uuidString, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(stmt, 3, task.driveFileId, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(stmt, 4, task.fileName, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(stmt, 5, task.relativePath, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_int64(stmt, 6, task.fileSize)
                    sqlite3_bind_int64(stmt, 7, task.downloadedBytes)
                    if let md5 = task.md5Checksum {
                        sqlite3_bind_text(stmt, 8, md5, -1, SQLITE_TRANSIENT)
                    } else {
                        sqlite3_bind_null(stmt, 8)
                    }
                    sqlite3_bind_text(stmt, 9, task.localPath, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(stmt, 10, task.status.rawValue, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_double(stmt, 11, task.currentSpeed)
                    if let err = task.errorMessage {
                        sqlite3_bind_text(stmt, 12, err, -1, SQLITE_TRANSIENT)
                    } else {
                        sqlite3_bind_null(stmt, 12)
                    }
                    sqlite3_bind_int(stmt, 13, Int32(task.retryCount))
                    sqlite3_bind_double(stmt, 14, task.updatedAt.timeIntervalSince1970)

                    sqlite3_step(stmt)
                    sqlite3_reset(stmt)
                }
            }
            sqlite3_finalize(stmt)
            execute(sql: "COMMIT;")
        }
    }

    public func updateTaskProgress(
        taskId: UUID,
        downloadedBytes: Int64,
        speed: Double,
        status: TaskStatus,
        errorMessage: String? = nil
    ) {
        queue.sync {
            let sql = """
            UPDATE tasks 
            SET downloaded_bytes = ?, current_speed = ?, status = ?, error_message = ?, updated_at = ?
            WHERE id = ?;
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int64(stmt, 1, downloadedBytes)
                sqlite3_bind_double(stmt, 2, speed)
                sqlite3_bind_text(stmt, 3, status.rawValue, -1, SQLITE_TRANSIENT)
                if let err = errorMessage {
                    sqlite3_bind_text(stmt, 4, err, -1, SQLITE_TRANSIENT)
                } else {
                    sqlite3_bind_null(stmt, 4)
                }
                sqlite3_bind_double(stmt, 5, Date().timeIntervalSince1970)
                sqlite3_bind_text(stmt, 6, taskId.uuidString, -1, SQLITE_TRANSIENT)
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
    }

    public func fetchTasks(for sessionId: UUID) -> [DownloadTask] {
        return queue.sync {
            var tasks: [DownloadTask] = []
            let sql = """
            SELECT id, session_id, drive_file_id, file_name, relative_path, file_size, downloaded_bytes, md5_checksum, local_path, status, current_speed, error_message, retry_count, updated_at
            FROM tasks WHERE session_id = ? ORDER BY relative_path ASC;
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, sessionId.uuidString, -1, SQLITE_TRANSIENT)
                while sqlite3_step(stmt) == SQLITE_ROW {
                    guard let idStr = sqlite3_column_text(stmt, 0),
                          let id = UUID(uuidString: String(cString: idStr)),
                          let sessStr = sqlite3_column_text(stmt, 1),
                          let sessId = UUID(uuidString: String(cString: sessStr)),
                          let driveId = sqlite3_column_text(stmt, 2),
                          let fileName = sqlite3_column_text(stmt, 3),
                          let relPath = sqlite3_column_text(stmt, 4),
                          let localPath = sqlite3_column_text(stmt, 8),
                          let statusStr = sqlite3_column_text(stmt, 9) else { continue }

                    let fileSize = sqlite3_column_int64(stmt, 5)
                    let downloaded = sqlite3_column_int64(stmt, 6)
                    let md5: String? = sqlite3_column_text(stmt, 7).map { String(cString: $0) }
                    let speed = sqlite3_column_double(stmt, 10)
                    let errorMsg: String? = sqlite3_column_text(stmt, 11).map { String(cString: $0) }
                    let retries = Int(sqlite3_column_int(stmt, 12))
                    let updatedAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 13))

                    let task = DownloadTask(
                        id: id,
                        sessionId: sessId,
                        driveFileId: String(cString: driveId),
                        fileName: String(cString: fileName),
                        relativePath: String(cString: relPath),
                        fileSize: fileSize,
                        downloadedBytes: downloaded,
                        md5Checksum: md5,
                        localPath: String(cString: localPath),
                        status: TaskStatus(rawValue: String(cString: statusStr)) ?? .queued,
                        currentSpeed: speed,
                        errorMessage: errorMsg,
                        retryCount: retries,
                        updatedAt: updatedAt
                    )
                    tasks.append(task)
                }
            }
            sqlite3_finalize(stmt)
            return tasks
        }
    }

    /// Reset any tasks that were marked downloading back to paused if the app was restarted
    public func resetIncompleteTasksOnLaunch() {
        queue.sync {
            execute(sql: "UPDATE tasks SET status = 'Paused', current_speed = 0 WHERE status = 'Downloading' OR status = 'Verifying MD5';")
            execute(sql: "UPDATE sessions SET status = 'Paused' WHERE status = 'Downloading';")
        }
    }

    // MARK: - Secure Key-Value Storage

    public func setSecureValue(_ value: String?, for key: String) {
        queue.sync {
            guard let val = value, !val.isEmpty else {
                let sql = "DELETE FROM secure_kv WHERE key = ?;"
                var stmt: OpaquePointer?
                if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                    sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT)
                    sqlite3_step(stmt)
                }
                sqlite3_finalize(stmt)
                return
            }

            let sql = "INSERT OR REPLACE INTO secure_kv (key, value, updated_at) VALUES (?, ?, ?);"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 2, val, -1, SQLITE_TRANSIENT)
                sqlite3_bind_double(stmt, 3, Date().timeIntervalSince1970)
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
    }

    public func getSecureValue(for key: String) -> String? {
        return queue.sync {
            let sql = "SELECT value FROM secure_kv WHERE key = ?;"
            var stmt: OpaquePointer?
            var result: String? = nil
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT)
                if sqlite3_step(stmt) == SQLITE_ROW {
                    if let text = sqlite3_column_text(stmt, 0) {
                        result = String(cString: text)
                    }
                }
            }
            sqlite3_finalize(stmt)
            return result
        }
    }

    public func deleteSecureValue(for key: String) {
        setSecureValue(nil, for: key)
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
