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

@NeedleTailTransportActor
public class TransportState: StateMachine {

    public let identifier: UUID
    public var current: State = .clientOffline
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
            clientContext: ClientContext)
        case transportRegistered(
            channel: Channel,
            clientContext: ClientContext)
        case transportOnline(
            channel: Channel,
            clientContext: ClientContext)
        case transportDeregistering
        case transportOffline
        case clientDisconnected
    }
    
    public func transition(to nextState: State) async {
        async let set = setState(nextState)
        self.current = await set
        switch self.current {
        case .clientOffline:
            logger.info("The client is offline")
        case .clientConnecting:
            logger.info("The client is connecting")
        case .clientConnected:
            logger.info("The client has connected")
        case .transportRegistering(channel: _, clientContext: let context):
            logger.info("Now registering Nick: \(context.nickname.name) has UserInfo: \(context.userInfo.description)")
        case .transportRegistered(channel: _, clientContext: let context):
            logger.info("Registered Nick: \(context.nickname.name) has UserInfo: \(context.userInfo.description)")
#if (os(macOS) || os(iOS))
            Task { @MainActor in
                emitter.clientIsRegistered = true
            }
#endif
        case .transportOnline(channel: let channel, clientContext: let clientContext):
            logger.info("Transport Channel is Active? - \(channel.isActive)")
            logger.info("Nick: \(clientContext.nickname.name) with UserInfo: \(clientContext.userInfo.description) is now online")
        case .transportDeregistering:
            logger.info("We are de-registering Session")
        case .transportOffline:
            logger.info("Successfully de-registerd Session")
#if (os(macOS) || os(iOS))
            Task { @MainActor in
                emitter.clientIsRegistered = false
            }
#endif
        case .clientDisconnected:
            logger.info("Client has disconnected")
        }
    }
    
    @MainActor
    func setState(_ currentState: State) -> State {
#if (os(macOS) || os(iOS))
        self.emitter.state = currentState
        return self.emitter.state
#else
return State.clientOffline
#endif
    }
}
