import BSON
import Crypto
import Foundation
import SwiftUI
import NIO
import CypherProtocol
import MongoKitten
import CypherMessaging
import Logging




@globalActor final actor JobQueueActor {
    public static let shared = JobQueueActor()
    
    private init() {}
}

@available(macOS 12, iOS 15, *)
final class IRCJobQueue {
    
    enum JobQueueErrors {
        case offline
    }
    
    private var store: NeedleTailStore
    public private(set) var runningJobs = false
    public private(set) var hasOutstandingTasks = true
    private var pausing: EventLoopPromise<Void>?
    private var jobs: [IRCJobModel] = [] {
        didSet {
            markAsDone()
        }
    }
    
    private var _taskResult: TaskResult = .success(ircMessage: nil)
    private var taskResult: TaskResult = .success(ircMessage: nil) {
        didSet {
            _taskResult = taskResult
        }
    }

    private static var taskDecoders = [IRCTaskKey: IRCTaskDecoder]()
    private var logger: Logger
    
    init(store: NeedleTailStore) async throws {
        self.logger = Logger(label: "JobQueue - ")
        self.store = store
        self.jobs = try await store.findJobs()
    }
    
    static func registerTask<T: IRCStoredTask>(_ task: T.Type, forKey key: IRCTaskKey) {
        taskDecoders[key] = { document in
            try BSONDecoder().decode(task, from: document)
        }
    }
    
    @JobQueueActor
    func cancelJob(_ job: IRCJobModel) async throws {
        // TODO: What if the job is cancelled while executing and succeeding?
        try await dequeueJob(job)
    }
    
    @JobQueueActor
    func dequeueJob(_ job: IRCJobModel) async throws {
        //        try await store.deleteJob(job)
        for i in 0..<self.jobs.count {
            if self.jobs[i].id == job.id {
                self.jobs.remove(at: i)
                return
            }
        }
    }
    
    @JobQueueActor public func queueTask<T: IRCStoredTask>(_ task: T) async throws -> TaskResult {
        
        let queuedJob = try IRCJobModel(task: task)
        
        self.jobs.append(queuedJob)
        self.hasOutstandingTasks = true
        //        try await store.createJob(job)
        var tasks: TaskResult = .success(ircMessage: nil)
        if !self.runningJobs {
           tasks = await self.startRunningTasks() ?? .success(ircMessage: nil)
        }
        return tasks
    }
    
    @JobQueueActor public func queueTasks<T: IRCStoredTask>(_ tasks: [T]) async throws {
        
        let jobs = try tasks.map { task in
            try IRCJobModel(task: task)
        }
        
        var queuedJobs = [IRCJobModel]()
        
        for job in jobs {
            queuedJobs.append(job)
        }
        
        do {
            for job in jobs {
//                try await store.createJob(job)
            }
        } catch {
            self.logger.notice("Failed to queue all jobs of type \(T.self)")
            for job in jobs {
//                _ = try? await store.deleteJob(job)
            }
            
            throw error
        }
        
        self.jobs.append(contentsOf: queuedJobs)
        self.hasOutstandingTasks = true
        
        if !self.runningJobs {
            _ = await self.startRunningTasks()
        }
    }
    
    fileprivate var isDoneNotifications = [EventLoopPromise<Void>]()
    
    @JobQueueActor
    func awaitDoneProcessing() async throws -> SynchronisationResult {
//                if runningJobs {
//                    return .busy
//                } else
        if hasOutstandingTasks {
            //            let promise = messenger.eventLoop.makePromise(of: Void.self)
            //            self.isDoneNotifications.append(promise)
            _ = await startRunningTasks()
            //            try await promise.futureResult.get()
            return .synchronised
        } else {
            return .skipped
        }
    }
    
    func markAsDone() {
        if !hasOutstandingTasks && !isDoneNotifications.isEmpty {
            for notification in isDoneNotifications {
                notification.succeed(())
            }
            
            isDoneNotifications = []
        }
    }
    
    @JobQueueActor
    func startRunningTasks() async -> TaskResult {
        self.logger.notice("Starting job queue")
        if runningJobs {
            self.logger.notice("Job queue already running")
            return .stopTask
        }
        
        if let pausing = pausing {
            self.logger.notice("Pausing job queue")
            pausing.succeed(())
            return .stopTask
        }
        self.logger.notice("Job queue started")
        runningJobs = true
        
        
        @JobQueueActor @Sendable func next() async throws -> TaskResult {
            self.logger.notice("Looking for next task")
            if self.jobs.isEmpty {
                self.logger.notice("No more tasks")
                self.runningJobs = false
                self.hasOutstandingTasks = false
                self.markAsDone()
                return .stopTask
            }
            
            let result: TaskResult
            
            do {
                result = try await runNextJob()
            } catch {
                self.logger.error("Task error \(error)")
                result = .failed(haltExecution: true)
            }
            
            if let pausing = self.pausing {
                self.logger.notice("Job finished, pausing started. Stopping further processing")
                self.runningJobs = false
                pausing.succeed(())
                return .stopTask
            } else {
                switch result {
                case .success, .delayed, .failed(haltExecution: false), .stopTask:
                    _ = try await next()
                case .failed(haltExecution: true):
                    for job in self.jobs {
                        let task: IRCStoredTask
                        
                        let taskKey = IRCTaskKey(rawValue: job.taskKey)
                        if let decoder = Self.taskDecoders[taskKey] {
                            task = try decoder(job.task)
                        } else {
                            task = try BSONDecoder().decode(IRCTask.self, from: job.task)
                        }
                        
                        try await task.onDelayed()
                    }
                    self.logger.notice("Task failed or none found, stopping processing")
                    self.runningJobs = false
                }
            }
            return result
        }
    
            if self.jobs.isEmpty {
                self.logger.notice("No jobs to run")
                self.hasOutstandingTasks = false
                self.runningJobs = false
                self.markAsDone()
            } else {
                var hasUsefulTasks = false
                
            findUsefulTasks: for job in self.jobs {
                if let delayedUntil = job.delayedUntil, delayedUntil >= Date() {
                    if !job.isBackgroundTask {
                        break findUsefulTasks
                    }
                    
                    continue findUsefulTasks
                }
                
                hasUsefulTasks = true
                break findUsefulTasks
            }
                
                guard hasUsefulTasks else {
                    self.logger.notice("All jobs are delayed")
                    self.hasOutstandingTasks = false
                    self.runningJobs = false
                    return .stopTask
                }
                
                do {
                    self.taskResult = try await next() ?? .success(ircMessage: nil)
                } catch {
                    self.logger.error("Job queue Error: \(error)")
                    self.runningJobs = false
                    self.pausing?.succeed(())
                }
            }
        return _taskResult
    }
    
    @JobQueueActor
    public func resume() async {
        pausing = nil
        _ = await startRunningTasks()
    }
    
    @JobQueueActor
    public func restart() async throws {
        //        try await pause()
        await resume()
    }
    
    //    public func pause() async throws {
    //        let promise = eventLoop.makePromise(of: Void.self)
    //        pausing = promise
    //        if !runningJobs {
    //            promise.succeed(())
    //        }
    //
    //        return try await promise.futureResult.get()
    //    }
    
    public enum TaskResult {
        case success(ircMessage: IRCMessage?), delayed, failed(haltExecution: Bool), stopTask
    }
    
    @JobQueueActor
    private func runNextJob() async throws -> TaskResult {
        self.logger.info("Available jobs \(jobs.count)")
        var index = 0
        let initialJob = jobs[0]
        if initialJob.isBackgroundTask, jobs.count > 1 {
        findBetterTask: for newIndex in 1..<jobs.count {
            let newJob = jobs[newIndex]
            if !newJob.isBackgroundTask {
                index = newIndex
                break findBetterTask
            }
        }
        }
        
        let job = jobs[index]
        self.logger.info("Running Job", metadata: ["Job:-":"\(job)"])
        if let delayedUntil = job.delayedUntil, delayedUntil >= Date() {
            self.logger.info("Task was delayed into the future", metadata: ["Task":"\(job.task)"])
            return .delayed
        }
        
        let task: IRCStoredTask
        
        do {
            let taskKey = IRCTaskKey(rawValue: job.taskKey)
            if let decoder = Self.taskDecoders[taskKey] {
                task = try decoder(job.task)
            } else {
                task = try BSONDecoder().decode(IRCTask.self, from: job.task)
            }
        } catch {
            self.logger.critical("Failed to decode job \(job.id)", metadata: ["Error":"\(error)"])
            try await self.dequeueJob(job)
            return .success(ircMessage: nil)
        }
        
//                if task.requiresConnectivity {
//                    self.logger.error("Job required connectivity, but app is offline"])
//                    throw JobQueueErrors.offline
//                }
        do {
            let ircMessage = try await task.execute()
            try await self.dequeueJob(job)
            return .success(ircMessage: ircMessage)
        } catch {
            self.logger.error("Job Error: \(error)")
            switch task.retryMode.raw {
            case .retryAfter(let retryDelay, let maxAttempts):
                self.logger.notice("Delaying task for an hour")
                try await job.delayExecution(retryDelay: retryDelay)
                
                if let maxAttempts = maxAttempts, job.attempts >= maxAttempts {
                    try await self.cancelJob(job)
                    return .success(ircMessage: nil)
                }
//                try await self.store.updateJob(job)
                return .delayed
            case .always:
                return .delayed
            case .never:
                try await self.dequeueJob(job)
                return .failed(haltExecution: false)
            }
        }
    }
}


