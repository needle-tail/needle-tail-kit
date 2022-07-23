//
//  TransportState.swift
//  
//
//  Created by Cole M on 11/28/21.
//

import Foundation
import NIOCore
import Logging
import NeedleTailHelpers
import NeedleTailProtocol

@NeedleTailClientActor
public class TransportState: StateMachine {

    public let identifier: UUID
    private var logger: Logger
    @MainActor private var emitter: NeedleTailEmitter
    
    public init(
        identifier: UUID,
        emitter: NeedleTailEmitter
    ) {
        self.identifier = identifier
        self.emitter = emitter
        self.logger = Logger(label: "TransportState:")
    }
    // MARK: StateMachine
    public enum State: Equatable {
        public static func == (lhs: TransportState.State, rhs: TransportState.State) -> Bool {
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

    public var current: State = .offline
    
    public func transition(to nextState: State) {
        self.current = nextState
        switch self.current {
        case .connecting:
            logger.info("The client is transitioning to a connecting state")
        case .registering(channel: let channel, nick: let nick, userInfo: let userInfo):
            logger.info("client is transitioning to a registering state with channel: \(channel), and Nick: \(nick) has UserInfo: \(userInfo)")
        case .registered(channel: let channel, nick: let nick, userInfo: let userInfo):
            logger.info("The client is transitioning to a registered state with channel: \(channel), and Nick: \(nick) has UserInfo: \(userInfo)")
        case .online:
            logger.info("The client is transitioning to an online state")
            Task {
                await online()
            }
        case .suspended:
            logger.info("The client is transitioning to a suspended state")
        case .offline:
            logger.info("The client is transitioning to an offline state")
            Task {
                await offline()
            }
        case .disconnect:
            logger.info("The client is transitioning to a disconnected state")
        case .error(let error):
            logger.info("The client is transitioning to an error state \(error)")
        case .quit:
            logger.info("The client is transitioning to quited state")
        }
    }
    
    @MainActor
    func online() {
#if (os(macOS) || os(iOS))
        emitter.online = true
#endif
    }
    
    @MainActor
    func offline() {
#if (os(macOS) || os(iOS))
        emitter.online = false
#endif
    }
}
