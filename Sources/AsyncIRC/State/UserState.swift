//
//  UserState.swift
//  
//
//  Created by Cole M on 11/28/21.
//

import Foundation
import NIOCore
import Logging

public struct UserState: StateMachine {

    public let identifier: UUID
    private var logger: Logger
    public init(identifier: UUID) {
        self.identifier = identifier
        self.logger = Logger(label: "UserState:")
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
    
        case connecting
        case registering(
            channel: Channel,
            nick: NeedleTailNick,
            userInfo: IRCUserInfo)
        case registered(
            channel: Channel,
            nick: NeedleTailNick,
            userInfo: IRCUserInfo)
        case online
        case suspended
        case offline
        case disconnect
        case error(error: Error)
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
        switch self.state {
        case .connecting:
            logger.info("The client is transitioning to a connecting state")
        case .registering(channel: let channel, nick: let nick, userInfo: let userInfo):
            logger.info("client is transitioning to a registering state with channel: \(channel), and Nick: \(nick) has UserInfo: \(userInfo)")
        case .registered(channel: let channel, nick: let nick, userInfo: let userInfo):
            logger.info("The client is transitioning to a registered state with channel: \(channel), and Nick: \(nick) has UserInfo: \(userInfo)")
        case .online:
            logger.info("The client is transitioning to an online state")
        case .suspended:
            logger.info("The client is transitioning to a suspended state")
        case .offline:
            logger.info("The client is transitioning to an offline state")
        case .disconnect:
            logger.info("The client is transitioning to a disconnected state")
        case .error(let error):
            logger.info("The client is transitioning to an error state \(error)")
        case .quit:
            logger.info("The client is transitioning to quited state")
        }
        
        
    }
}
