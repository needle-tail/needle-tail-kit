//
//  TransportState.swift
//
//
//  Created by Cole M on 11/28/21.
//

import Foundation
import Logging
import NeedleTailHelpers
import NeedleTailProtocol
@_spi(AsyncChannel) import NIOCore

@NeedleTailTransportActor
public class TransportState: StateMachine {

    public let identifier: UUID
    public var current: State = .clientOffline
    private var logger: Logger
    @MainActor private var messenger: NeedleTailMessenger
    
    public init(
        identifier: UUID,
        messenger: NeedleTailMessenger
    ) {
        self.identifier = identifier
        self.messenger = messenger
        self.logger = Logger(label: "TransportState:")
    }

    public enum State {
        
        case clientOffline
        case clientConnecting
        case clientConnected
        case transportRegistering(
            isActive: Bool,
            clientContext: ClientContext)
        case transportRegistered(
            isActive: Bool,
            clientContext: ClientContext)
        case transportOnline(
            isActive: Bool,
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
        case .transportRegistering(isActive: _, clientContext: let context):
            logger.info("Now registering Nick: \(context.nickname.name) has UserInfo: \(context.userInfo.description)")
        case .transportRegistered(isActive: _, clientContext: let context):
            logger.info("Registered Nick: \(context.nickname.name) has UserInfo: \(context.userInfo.description)")
#if (os(macOS) || os(iOS))
            Task { @MainActor in
                messenger.emitter.clientIsRegistered = true
            }
#endif
        case .transportOnline(isActive: let isActive, clientContext: let clientContext):
            logger.info("Transport Channel is Active? - \(isActive)")
            logger.info("Nick: \(clientContext.nickname.name) with UserInfo: \(clientContext.userInfo.description) is now online")
        case .transportDeregistering:
            logger.info("We are de-registering Session")
        case .transportOffline:
            logger.info("Successfully de-registerd Session")
#if (os(macOS) || os(iOS))
            Task { @MainActor in
                messenger.emitter.clientIsRegistered = false
            }
#endif
        case .clientDisconnected:
            logger.info("Client has disconnected")
        }
    }
    
    @MainActor
    func setState(_ currentState: State) -> State {
#if (os(macOS) || os(iOS))
        self.messenger.emitter.transportState = currentState
        return self.messenger.emitter.transportState
#else
return State.clientOffline
#endif
    }
}
