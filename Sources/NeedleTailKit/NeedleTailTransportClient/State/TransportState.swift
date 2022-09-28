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

    public enum State {
        case clientOffline
        case clientConnecting
        case clientConnected
        case transportRegistering(
            channel: Channel,
            nick: NeedleTailNick,
            userInfo: IRCUserInfo)
        case transportOnline(
            channel: Channel,
            nick: NeedleTailNick,
            userInfo: IRCUserInfo)
        case transportDeregistering
        case transportOffline
        case clientDisconnected
    }
    
    public var current: State = .clientOffline
    
    public func transition(to nextState: State) {
      Task {
            await setState(nextState)
        }
        self.current = nextState
        switch self.current {
        case .clientOffline:
            logger.info("The client is offline")
        case .clientConnecting:
            logger.info("The client is connecting")
        case .clientConnected:
            logger.info("The client has connected")
        case .transportRegistering(channel: _, nick: let nick, userInfo: let userInfo):
            logger.info("Now registering Nick: \(nick.name) has UserInfo: \(userInfo.description)")
        case .transportOnline(channel: _, nick: let nick, userInfo: let userInfo):
            logger.info("Nick: \(nick.name) with UserInfo: \(userInfo.description) is now online")
        case .transportDeregistering:
            logger.info("We are de-registering Session")
        case .transportOffline:
            logger.info("Successfully de-registerd Session")
        case .clientDisconnected:
            logger.info("Client has disconnected")
        }
    }
    
    @MainActor
    func setState(_ currentState: State) {
#if (os(macOS) || os(iOS))
    self.emitter.state = currentState
#endif
    }
}
