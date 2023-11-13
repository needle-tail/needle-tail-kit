//
//  JobQueue.swift
//  
//
//  Created by Cole M on 6/17/23.
//

import Foundation
import DequeModule

public actor JobQueue<J: Sendable> {
    
    public var jobDeque = Deque<J>()
    public var newDeque = Deque<J>()
    private var jobState:JobState = .finished
    
    public init() {}
    
    public func addJob(_ job: J) async {
        jobDeque.append(job)
    }
    
    private enum JobState: Sendable {
        case hasJobs, finished
    }
    
    public func checkForExistingJobs(passJob: @Sendable @escaping (J) async throws -> J?) async throws -> Deque<J> {
        
        func runJobs() async throws -> J? {
            if !jobDeque.isEmpty {
                jobState = .hasJobs
            } else {
                jobState = .finished
            }
            
            switch jobState {
            case .hasJobs:
                guard !jobDeque.isEmpty else { return nil }
                return try await passJob(jobDeque.removeLast())
            case .finished:
                return nil
            }
        }
        
        while !jobDeque.isEmpty {
            if let job = try await runJobs() {
                    newDeque.append(job)
            }
        }
        
        //We will hit nil in our job state so this will never be called
        return newDeque
    }
    
    public func transferTransportJobs() async {
        if !newDeque.isEmpty && jobDeque.isEmpty {
            _ = newDeque.popLast()
            jobDeque = newDeque
            newDeque.removeAll()
        }
    }
}
