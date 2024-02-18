//
//  RunLoop.swift
//
//
//  Created by Cole M on 4/16/22.
//

import Foundation
import CypherMessaging

public protocol TaskObjectProtocol {}
public class RunLoop {
    
    public enum LoopResult {
        case finished, runnning
    }
    
    public enum Errors: Error {
        case cannotGetReturnable
    }
    
    /// This class method sets the date for the time interval to stop execution on
    /// - Parameter timeInterval: A Double Value in seconds
    /// - Returns: The Date for the exectution to stop on
    public static func timeInterval(_ timeInterval: TimeInterval) -> Date {
        let timeInterval = TimeInterval(timeInterval)
        let deadline = Date(timeIntervalSinceNow: Double(Double(1_000_000_000) * timeInterval) / Double(1_000_000_000)).timeIntervalSinceNow
        return Date(timeIntervalSinceNow: deadline)
    }
    
    ///  This method determines when the run loop should start and stop depending on the parameters value
    /// - Parameters:
    ///   - expriedDate: The Date we wish to exprire the loop on
    ///   - ack: The Acknowledgement we may receive from the server
    ///   - canRun: A Bool value we can customize property values in the caller
    /// - Returns: A Boolean value that indicates whether or not the loop should run
    public static func execute(_
                               expriedDate: Date,
                               canRun: Bool
    ) async -> Bool {
        func runTask() async -> LoopResult {
            let runningDate = Date()
            if canRun == true {
                guard expriedDate >= runningDate else { return .finished }
                return .runnning
            } else {
                return .finished
            }
        }
        
        let result = await runTask()
        switch result {
        case .finished:
            return false
        case .runnning:
            return true
        }
    }
    
    static var loopTasks = [Task<TaskObjectProtocol?, Error>]()
    static var voidTasks = [Task<Void, Error>]()
    
    
    /// Runs the loop
    /// - Parameters:
    ///   - expiresIn: The Date we wish to exprire the loop on
    ///   - sleep: The length we want to sleep the loop
    ///   - stopRunning: a custom callback to indicate when we should call canRun = false
    public static func run(_
                           expiresIn: TimeInterval,
                           sleep: UInt64,
                           stopRunning: @Sendable @escaping () async throws -> Bool
    ) async throws {
        let task: Task<Void, Error> = Task {
            try await withThrowingTaskGroup(of: Bool.self) { group in
                try Task.checkCancellation()
                let date = RunLoop.timeInterval(expiresIn)
                var canRun = true
                while await RunLoop.execute(date, canRun: canRun) {
                    try await Task.sleep(until: .now + .seconds(sleep), tolerance: .zero, clock: .continuous)
                    group.addTask {
                        return try await stopRunning()
                    }
                    guard let isRunning = try await group.next() else { return }
                    canRun = isRunning
                }
            }
        }
        voidTasks.append(task)
        _ = try await task.value
        let taskToCancel = voidTasks.first(where: { $0 == task })
        if taskToCancel?.isCancelled == false {
            taskToCancel?.cancel()
        }
        voidTasks.removeAll(where: { $0 == task })
    }
    
    public static func runReturningLoop<T: TaskObjectProtocol>(
        expiresIn: TimeInterval,
        seconds toSleep: UInt64,
        stopRunning: @Sendable @escaping () async throws -> (Bool, T?)
    ) async throws -> T? {
        let task: Task<TaskObjectProtocol?, Error> = Task {
            try await withThrowingTaskGroup(of: T?.self) { group in
                try Task.checkCancellation()
                let date = RunLoop.timeInterval(expiresIn)
                var canRun = true
                while await RunLoop.execute(date, canRun: canRun) {
                    try await Task.sleep(until: .now + .seconds(toSleep), tolerance: .zero, clock: .continuous)
                    let (isRunning, bundle) = try await stopRunning()
                    canRun = isRunning
                    if !isRunning {
                        group.addTask {
                            return bundle
                        }
                    } else {
                        return nil
                    }
                }
                guard let next = try await group.next() else { throw Errors.cannotGetReturnable }
                return next
            }
        }
        loopTasks.append(task)
        let value = try await task.value
        let taskToCancel = loopTasks.first(where: { $0 == task })
        if taskToCancel?.isCancelled == false {
            taskToCancel?.cancel()
        }
        loopTasks.removeAll(where: { $0 == task })
        return value as? T
    }
    
    
}

public class RunSyncLoop {
    
    public enum LoopResult {
        case finished, runnning
    }
    
    /// This class method sets the date for the time interval to stop execution on
    /// - Parameter timeInterval: A Double Value in seconds
    /// - Returns: The Date for the exectution to stop on
    public static func timeInterval(_ timeInterval: TimeInterval) -> Date {
        let timeInterval = TimeInterval(timeInterval)
        let deadline = Date(timeIntervalSinceNow: Double(Double(1_000_000_000) * timeInterval) / Double(1_000_000_000)).timeIntervalSinceNow
        return Date(timeIntervalSinceNow: deadline)
    }
    
    ///  This method determines when the run loop should start and stop depending on the parameters value
    /// - Parameters:
    ///   - expriedDate: The Date we wish to exprire the loop on
    ///   - ack: The Acknowledgement we may receive from the server
    ///   - canRun: A Bool value we can customize property values in the caller
    /// - Returns: A Boolean value that indicates whether or not the loop should run
    public static func executeSynchronously(_
                                            expriedDate: Date,
                                            canRun: Bool
    ) -> Bool {
        func runSyncTask() -> LoopResult {
            let runningDate = Date()
            if canRun == true {
                guard expriedDate >= runningDate else { return .finished }
                return .runnning
            } else {
                return .finished
            }
        }
        
        let result = runSyncTask()
        switch result {
        case .finished:
            return false
        case .runnning:
            return true
        }
    }
    
    /// Runs the loop
    /// - Parameters:
    ///   - expiresIn: The Date we wish to exprire the loop on
    ///   - sleep: The length we want to sleep the loop
    ///   - stopRunning: a custom callback to indicate when we should call canRun = false
    public static func runSync(_
                               expiresIn: TimeInterval,
                               stopRunning: @Sendable @escaping () throws -> Bool
    ) throws {
        let date = RunSyncLoop.timeInterval(expiresIn)
        var canRun = true
        while RunSyncLoop.executeSynchronously(date, canRun: canRun) {
            canRun = try stopRunning()
        }
    }
    
}
