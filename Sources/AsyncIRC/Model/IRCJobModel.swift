//
//  JobModel.swift
//  
//
//  Created by Cole M on 1/8/22.
//

import Foundation
import CypherMessaging
import BSON


public struct IRCJobModel: Codable {
    public enum DeliveryState: Int, Codable {
        case none = 0
        case undelivered = 1
        case received = 2
        case read = 3
        case revoked = 4
        
        @discardableResult
        public mutating func transition(to newState: DeliveryState) -> MarkMessageResult {
            switch (self, newState) {
            case (.none, _), (.undelivered, _), (.received, .read), (.received, .revoked):
                self = newState
                return .success
            case (_, .undelivered), (_, .none), (.read, .revoked), (.read, .received), (.revoked, .read), (.revoked, .received):
                return .error
            case (.revoked, .revoked), (.read, .read), (.received, .received):
                return .notModified
            }
        }
    }
    
    public var id: UUID
    public let taskKey: String
    public var task: Document
    public var delayedUntil: Date?
    public var scheduledAt: Date
    public var attempts: Int
    public let isBackgroundTask: Bool
    
    init<T: IRCStoredTask>(task: T) throws {
        self.id = UUID()
        self.taskKey = task.key.rawValue
        self.isBackgroundTask = task.isBackgroundTask
        self.task = try BSONEncoder().encode(task)
        self.scheduledAt = Date()
        self.attempts = 0
    }
    
    
    public init(
        id: UUID,
        taskKey: String,
        task: Document,
        delayedUntil: Date?,
        scheduledAt: Date,
        attempts: Int,
        isBackgroundTask: Bool
    ) {
        self.id = id
        self.taskKey = taskKey
        self.task = task
        self.delayedUntil = delayedUntil
        self.scheduledAt = scheduledAt
        self.attempts = attempts
        self.isBackgroundTask = isBackgroundTask
    }
    
    func delayExecution(retryDelay: TimeInterval) async throws {
//        try await setProp(at: \.delayedUntil, to: Date().addingTimeInterval(retryDelay))
//        try await setProp(at: \.attempts, to: self.attempts + 1)
    }
}

