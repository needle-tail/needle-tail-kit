//
//  File.swift
//
//
//  Created by Cole M on 1/9/22.
//

import Foundation
import NIO
import BSON
import Foundation

public protocol IRCStoredTask: Codable {
    var key: IRCTaskKey { get }
    var isBackgroundTask: Bool { get }
    var retryMode: IRCTaskRetryMode { get }
    var priority: IRCTaskPriority { get }
    var requiresConnectivity: Bool { get }
    
    func execute() async throws -> IRCMessage?
    func onDelayed() async throws
}

public typealias IRCTaskDecoder = (Document) throws -> IRCStoredTask

public struct IRCTaskPriority {
    enum _Raw: Comparable {
        case lowest, lower, normal, higher, urgent
    }

    let raw: _Raw

    /// Take your time, it's expected to take a while
    public static let lowest = IRCTaskPriority(raw: .lowest)

    /// Not as urgent as regular user actions, but please do not take all the time in the world
    public static let lower = IRCTaskPriority(raw: .lower)

    /// Regular user actions
    public static let normal = IRCTaskPriority(raw: .normal)

    /// This is needed fast, think of real-time communication
    public static let higher = IRCTaskPriority(raw: .higher)

    /// THIS CANNOT WAIT
    public static let urgent = IRCTaskPriority(raw: .urgent)
}

public struct IRCTaskRetryMode {
    enum _Raw {
        case never
        case always
        case retryAfter(TimeInterval, maxAttempts: Int?)
    }

    let raw: _Raw

    public static let never = IRCTaskRetryMode(raw: .never)
    public static let always = IRCTaskRetryMode(raw: .always)
    public static func retryAfter(_ interval: TimeInterval, maxAttempts: Int?) -> IRCTaskRetryMode {
        .init(raw: .retryAfter(interval, maxAttempts: maxAttempts))
    }
}

public struct IRCTaskKey: ExpressibleByStringLiteral, RawRepresentable, Hashable {
    private let taskName: String

    public var rawValue: String { taskName }

    public init(rawValue: String) {
        self.taskName = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.taskName = value
    }
}
