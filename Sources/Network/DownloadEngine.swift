import Foundation
import SwiftUI
import Combine

/// State and delegate for a single active streaming file download
private final class SingleDownloadWorker: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    let taskId: UUID
    let request: URLRequest
    let destinationURL: URL
    let partURL: URL
    let totalExpectedBytes: Int64
    let initialByteOffset: Int64
    let expectedMD5: String?

    var onProgress: (@Sendable (Int64, Double) -> Void)?
    var onCompletion: (@Sendable (Result<Void, Error>) -> Void)?

    private var session: URLSession?
    private var dataTask: URLSessionDataTask?
    private var fileHandle: FileHandle?
    private var bytesDownloadedInSession: Int64 = 0
    private var lastSpeedCheckTime = Date()
    private var lastSpeedCheckBytes: Int64 = 0
    private var isCancelled = false
    private let lock = NSLock()

    init(
        taskId: UUID,
        request: URLRequest,
        destinationURL: URL,
        partURL: URL,
        totalExpectedBytes: Int64,
        initialByteOffset: Int64,
        expectedMD5: String?
    ) {
        self.taskId = taskId
        self.request = request
        self.destinationURL = destinationURL
        self.partURL = partURL
        self.totalExpectedBytes = totalExpectedBytes
        self.initialByteOffset = initialByteOffset
        self.expectedMD5 = expectedMD5
        super.init()
    }

    func start() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 86400 // 24 hours for massive video files
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1

        self.session = URLSession(configuration: config, delegate: self, delegateQueue: queue)

        // Ensure parent directory exists
        try? FileManager.default.createDirectory(at: partURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        if initialByteOffset == 0 {
            // Create or truncate .part file
            FileManager.default.createFile(atPath: partURL.path, contents: nil)
        }

        do {
            self.fileHandle = try FileHandle(forWritingTo: partURL)
            if initialByteOffset > 0 {
                try self.fileHandle?.seek(toOffset: UInt64(initialByteOffset))
            }
        } catch {
            onCompletion?(.failure(error))
            return
        }

        self.lastSpeedCheckTime = Date()
        self.lastSpeedCheckBytes = 0
        self.dataTask = session?.dataTask(with: request)
        self.dataTask?.resume()
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        lock.unlock()

        dataTask?.cancel()
        session?.invalidateAndCancel()
        try? fileHandle?.close()
        fileHandle = nil
    }

    // MARK: - URLSessionDataDelegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 200 && initialByteOffset > 0 {
                // Server ignored range, must restart from 0
                try? fileHandle?.seek(toOffset: 0)
                try? fileHandle?.truncate(atOffset: 0)
                lock.lock()
                bytesDownloadedInSession = 0
                lock.unlock()
            } else if http.statusCode >= 400 {
                completionHandler(.cancel)
                let error = NSError(domain: "HTTP", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server returned HTTP \(http.statusCode)"])
                onCompletion?(.failure(error))
                return
            }
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        defer { lock.unlock() }
        guard !isCancelled else { return }

        do {
            try fileHandle?.write(contentsOf: data)
            bytesDownloadedInSession += Int64(data.count)

            let now = Date()
            let interval = now.timeIntervalSince(lastSpeedCheckTime)
            if interval >= 0.5 {
                let speed = Double(bytesDownloadedInSession - lastSpeedCheckBytes) / interval
                let totalCurrent = initialByteOffset + bytesDownloadedInSession
                lastSpeedCheckTime = now
                lastSpeedCheckBytes = bytesDownloadedInSession
                onProgress?(totalCurrent, speed)
            }
        } catch {
            dataTask.cancel()
            onCompletion?(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        try? fileHandle?.close()
        fileHandle = nil

        if let error = error {
            if (error as NSError).code == NSURLErrorCancelled {
                // Explicitly paused or cancelled
                return
            }
            onCompletion?(.failure(error))
            return
        }

        // Rename .part to destination
        do {
            try? FileManager.default.removeItem(at: destinationURL)
            try FileManager.default.moveItem(at: partURL, to: destinationURL)
            onCompletion?(.success(()))
        } catch {
            onCompletion?(.failure(error))
        }
    }
}

/// The master download engine managing concurrent streams, pause/resume, and SQLite synchronization
@MainActor
public final class DownloadEngine: ObservableObject {
    public static let shared = DownloadEngine()

    @Published public var sessions: [TransferSession] = []
    @Published public var activeTasks: [DownloadTask] = []
    @Published public var currentSessionId: UUID?
    @Published public var totalSpeed: Double = 0
    @Published public var totalActiveCount: Int = 0
    @Published public var isRunning: Bool = false

    private var workers: [UUID: SingleDownloadWorker] = [:]
    private var speedTimer: Timer?

    private init() {
        loadPersistedState()
        startSpeedMonitoring()
    }

    public func loadPersistedState() {
        DatabaseManager.shared.resetIncompleteTasksOnLaunch()
        self.sessions = DatabaseManager.shared.fetchSessions()
        if let first = sessions.first {
            self.currentSessionId = first.id
            self.activeTasks = DatabaseManager.shared.fetchTasks(for: first.id)
        }
    }

    public func selectSession(_ session: TransferSession) {
        self.currentSessionId = session.id
        self.activeTasks = DatabaseManager.shared.fetchTasks(for: session.id)
    }

    private func startSpeedMonitoring() {
        speedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                var speedSum: Double = 0
                for task in self.activeTasks where task.status == .downloading {
                    speedSum += task.currentSpeed
                }
                self.totalSpeed = speedSum
                self.totalActiveCount = self.workers.count
            }
        }
    }

    // MARK: - New Session Initiation

    public func createSession(
        name: String,
        rootDriveId: String,
        originalUrl: String,
        destinationDirectory: String,
        items: [DriveItem]
    ) {
        let session = TransferSession(
            name: name,
            rootDriveId: rootDriveId,
            originalUrl: originalUrl,
            destinationPath: destinationDirectory,
            totalFiles: items.count,
            totalBytes: items.reduce(0) { $0 + $1.size },
            status: .ready
        )

        var tasks: [DownloadTask] = []
        for item in items {
            let localFile = (destinationDirectory as NSString).appendingPathComponent(item.relativePath)
            let task = DownloadTask(
                sessionId: session.id,
                driveFileId: item.id,
                fileName: item.name,
                relativePath: item.relativePath,
                fileSize: item.size,
                downloadedBytes: 0,
                md5Checksum: item.md5Checksum,
                localPath: localFile,
                status: .queued
            )
            tasks.append(task)
        }

        DatabaseManager.shared.saveSession(session)
        DatabaseManager.shared.saveTasks(tasks)

        self.sessions.insert(session, at: 0)
        self.currentSessionId = session.id
        self.activeTasks = tasks

        // Auto-start download
        startSession(sessionId: session.id)
    }

    // MARK: - Queue Orchestration

    public func startSession(sessionId: UUID) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[idx].status = .downloading
        DatabaseManager.shared.saveSession(sessions[idx])
        isRunning = true

        pumpQueue()
    }

    public func pauseSession(sessionId: UUID) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[idx].status = .paused
        DatabaseManager.shared.saveSession(sessions[idx])

        // Cancel workers for this session
        for (taskId, worker) in workers {
            if activeTasks.contains(where: { $0.id == taskId && $0.sessionId == sessionId }) {
                worker.cancel()
                workers.removeValue(forKey: taskId)
                updateTaskInPlace(taskId: taskId) {
                    $0.status = .paused
                    $0.currentSpeed = 0
                }
            }
        }

        if workers.isEmpty {
            isRunning = false
            totalSpeed = 0
        }
    }

    public func resumeSession(sessionId: UUID) {
        startSession(sessionId: sessionId)
    }

    public func deleteSession(sessionId: UUID) {
        pauseSession(sessionId: sessionId)
        DatabaseManager.shared.deleteSession(sessionId)
        sessions.removeAll(where: { $0.id == sessionId })
        if currentSessionId == sessionId {
            currentSessionId = sessions.first?.id
            if let newId = currentSessionId {
                activeTasks = DatabaseManager.shared.fetchTasks(for: newId)
            } else {
                activeTasks = []
            }
        }
    }

    public func pauseTask(taskId: UUID) {
        if let worker = workers[taskId] {
            worker.cancel()
            workers.removeValue(forKey: taskId)
        }
        updateTaskInPlace(taskId: taskId) {
            $0.status = .paused
            $0.currentSpeed = 0
        }
        pumpQueue()
    }

    public func resumeTask(taskId: UUID) {
        updateTaskInPlace(taskId: taskId) {
            $0.status = .queued
            $0.errorMessage = nil
        }
        pumpQueue()
    }

    public func retryFailedTasks() {
        Task {
            // Proactively refresh OAuth token in case the session expired (>1 hour)
            _ = try? await OAuthManager.shared.getValidAccessToken(forceRefresh: true)

            await MainActor.run {
                for i in 0..<self.activeTasks.count {
                    if self.activeTasks[i].status == .failed {
                        self.activeTasks[i].status = .queued
                        self.activeTasks[i].errorMessage = nil
                        self.activeTasks[i].retryCount = 0
                        DatabaseManager.shared.updateTaskProgress(
                            taskId: self.activeTasks[i].id,
                            downloadedBytes: self.activeTasks[i].downloadedBytes,
                            speed: 0,
                            status: .queued
                        )
                    }
                }
                self.pumpQueue()
            }
        }
    }

    // MARK: - Queue Pump

    private func pumpQueue() {
        let maxConcurrent = 4

        while workers.count < maxConcurrent {
            // Find next queued task
            guard let nextTaskIndex = activeTasks.firstIndex(where: { $0.status == .queued }) else {
                break
            }

            let task = activeTasks[nextTaskIndex]
            launchWorker(for: task)
        }
    }

    private func launchWorker(for task: DownloadTask) {
        let partPath = task.localPath + ".part"
        let destURL = URL(fileURLWithPath: task.localPath)
        let partURL = URL(fileURLWithPath: partPath)

        // Check existing byte offset on disk
        var existingBytes: Int64 = 0
        if FileManager.default.fileExists(atPath: partPath) {
            let attrs = try? FileManager.default.attributesOfItem(atPath: partPath)
            existingBytes = (attrs?[.size] as? Int64) ?? 0
            if existingBytes >= task.fileSize && task.fileSize > 0 {
                // File already completely downloaded in part, finalize
                try? FileManager.default.removeItem(at: destURL)
                try? FileManager.default.moveItem(at: partURL, to: destURL)
                finalizeTask(taskId: task.id, localURL: destURL, md5: task.md5Checksum)
                return
            }
        }

        let request = GoogleDriveClient.shared.buildDownloadRequest(fileId: task.driveFileId, startByte: existingBytes)

        let worker = SingleDownloadWorker(
            taskId: task.id,
            request: request,
            destinationURL: destURL,
            partURL: partURL,
            totalExpectedBytes: task.fileSize,
            initialByteOffset: existingBytes,
            expectedMD5: task.md5Checksum
        )

        workers[task.id] = worker

        updateTaskInPlace(taskId: task.id) {
            $0.status = .downloading
            $0.downloadedBytes = existingBytes
        }

        worker.onProgress = { [weak self] currentBytes, speed in
            Task { @MainActor [weak self] in
                self?.updateTaskInPlace(taskId: task.id) {
                    $0.downloadedBytes = currentBytes
                    $0.currentSpeed = speed
                }
            }
        }

        worker.onCompletion = { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.workers.removeValue(forKey: task.id)

                switch result {
                case .success:
                    self.finalizeTask(taskId: task.id, localURL: destURL, md5: task.md5Checksum)
                case .failure(let error):
                    self.handleWorkerFailure(taskId: task.id, error: error)
                }

                self.pumpQueue()
                self.syncSessionProgress()
            }
        }

        worker.start()
    }

    private func finalizeTask(taskId: UUID, localURL: URL, md5: String?) {
        guard let md5 = md5, !md5.isEmpty else {
            // No checksum provided, mark completed
            updateTaskInPlace(taskId: taskId) {
                $0.status = .completed
                $0.downloadedBytes = $0.fileSize
                $0.currentSpeed = 0
            }
            return
        }

        // Perform MD5 verification in background
        updateTaskInPlace(taskId: taskId) {
            $0.status = .verifying
            $0.currentSpeed = 0
        }

        Task {
            let isValid = await MD5Verifier.verify(localURL: localURL, expectedMD5: md5)
            await MainActor.run {
                if isValid {
                    self.updateTaskInPlace(taskId: taskId) {
                        $0.status = .completed
                        $0.downloadedBytes = $0.fileSize
                    }
                } else {
                    self.updateTaskInPlace(taskId: taskId) {
                        $0.status = .failed
                        $0.errorMessage = "Checksum MD5 verification failed. File may be corrupted."
                    }
                }
                self.syncSessionProgress()
            }
        }
    }

    private func handleWorkerFailure(taskId: UUID, error: Error) {
        let errDesc = error.localizedDescription
        let isAuthError = (error as NSError).code == 401 || errDesc.contains("401") || errDesc.localizedCaseInsensitiveContains("unauthorized")

        if isAuthError {
            // Google OAuth access token expired midway through large project download!
            // Automatically refresh token and requeue task
            Task {
                _ = try? await OAuthManager.shared.getValidAccessToken(forceRefresh: true)
                await MainActor.run {
                    self.updateTaskInPlace(taskId: taskId) {
                        $0.currentSpeed = 0
                        $0.status = .queued
                        $0.errorMessage = "Token refreshed, retrying..."
                    }
                    self.pumpQueue()
                }
            }
            return
        }

        updateTaskInPlace(taskId: taskId) {
            $0.currentSpeed = 0
            $0.retryCount += 1
            if $0.retryCount <= 3 {
                // Auto requeue
                $0.status = .queued
                $0.errorMessage = "Retrying (\($0.retryCount)/3)..."
            } else {
                $0.status = .failed
                $0.errorMessage = error.localizedDescription
            }
        }
    }

    private func updateTaskInPlace(taskId: UUID, mutate: (inout DownloadTask) -> Void) {
        guard let idx = activeTasks.firstIndex(where: { $0.id == taskId }) else { return }
        mutate(&activeTasks[idx])

        // Persist to SQLite
        let t = activeTasks[idx]
        DatabaseManager.shared.updateTaskProgress(
            taskId: t.id,
            downloadedBytes: t.downloadedBytes,
            speed: t.currentSpeed,
            status: t.status,
            errorMessage: t.errorMessage
        )
    }

    private func syncSessionProgress() {
        guard let sessId = currentSessionId,
              let idx = sessions.firstIndex(where: { $0.id == sessId }) else { return }

        let completedFiles = activeTasks.filter { $0.status == .completed }.count
        let completedBytes = activeTasks.reduce(0) { $0 + ($1.status == .completed ? $1.fileSize : $1.downloadedBytes) }

        sessions[idx].completedFiles = completedFiles
        sessions[idx].completedBytes = completedBytes

        if completedFiles >= sessions[idx].totalFiles && sessions[idx].totalFiles > 0 {
            sessions[idx].status = .completed
            isRunning = false
            totalSpeed = 0
        }

        DatabaseManager.shared.updateSessionProgress(
            sessionId: sessId,
            completedFiles: completedFiles,
            completedBytes: completedBytes,
            status: sessions[idx].status
        )
    }
}
