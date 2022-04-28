//
//  UserState.swift
//  
//
//  Created by Cole M on 11/28/21.
//

import Foundation
import NIOCore

public struct UserState: StateMachine {

    let identifier: String
    public init(identifier: String) {
        self.identifier = identifier
    }
    // MARK: StateMachine
    public enum State: Equatable {
        public static func == (lhs: UserState.State, rhs: UserState.State) -> Bool {
            switch (lhs, rhs) {
            case (.offline, .offline), (.online, .online):
            return true
            default:
            return false
            }
        }
        
        case suspended
        case offline
        case registering(
            channel: Channel,
            nick: NeedleTailNick,
            userInfo: IRCUserInfo)
        case registered(
            channel: Channel,
            nick: NeedleTailNick,
            userInfo: IRCUserInfo)
        case connecting
        case online
        case disconnect
        case error
        case quit
        
    }

    public var state: State = .offline
//    static let stateTransitions: [State: Set<State> = [
//        .suspended: [.offline],
//        .offline: [.connecting],
//        .registering(channel:Channel, nick:NeedleTailNick, userInfo:IRCUserInfo): [.connecting],
//        .connecting: [.suspended, .offline, .online],
//        .online: [.connecting, .offline, .suspended],
//    ]
    
    
    public mutating func transition(to nextState: State) {
//        precondition(self.canTransition(to: nextState), "Invalid state transition (\(self.state) -> \(nextState))!")
        self.state = nextState
    }
}
