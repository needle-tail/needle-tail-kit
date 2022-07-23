//
//  RunLoop.swift
//  
//
//  Created by Cole M on 4/16/22.
//

import Foundation


public final class RunLoop {
    
    public enum LoopResult {
        case finished, runnning
    }
    
    /// This class method sets the date for the time interval to stop execution on
    /// - Parameter timeInterval: A Double Value in seconds
    /// - Returns: The Date for the exectution to stop on
    public class func timeInterval(_ timeInterval: TimeInterval) -> Date {
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
    public class func execute(_
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
    
    /// Runs the loop
    /// - Parameters:
    ///   - expiresIn: The Date we wish to exprire the loop on
    ///   - sleep: The length we want to sleep the loop
    ///   - stopRunning: a custom callback to indicate when we should call canRun = false
    public class func run(_
                          expiresIn: TimeInterval,
                          sleep: UInt64,
                          stopRunning: () async throws -> Bool
    ) async throws {
        let date = RunLoop.timeInterval(expiresIn)
        var canRun = true
        repeat {
//            try await Task.sleep(nanoseconds: sleep)
            canRun = try await stopRunning()
        } while await RunLoop.execute(date, canRun: canRun)
    }
}
