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
import NIOCore

public actor TransportState {
    
    public let identifier: UUID
    public var current: State = .clientOffline
    private var logger: Logger
    
    private var messenger: NeedleTailMessenger
    
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
            clientContext: ClientContext)
        case transportRegistered(
            clientContext: ClientContext)
        case transportOnline(
            clientContext: ClientContext)
        case transportDeregistering
        case transportOffline
        case shouldCloseChannel
        case clientDisconnected
    }
    
    public func transition(to nextState: State) async {
        self.current = await self.setState(nextState)
        switch self.current {
        case .clientOffline:
            logger.info("The client is offline")
        case .clientConnecting:
            logger.info("The client is connecting")
        case .clientConnected:
            logger.info("The client has connected")
        case .transportRegistering(clientContext: let context):
            logger.info("Now registering Nick: \(context.nickname.name) has UserInfo: \(context.userInfo.description)")
        case .transportRegistered(clientContext: let context):
            logger.info("Registered Nick: \(context.nickname.name) has UserInfo: \(context.userInfo.description)")
        case .transportOnline(clientContext: let clientContext):
            logger.info("Transport Channel is Online")
            logger.info("Nick: \(clientContext.nickname.name) with UserInfo: \(clientContext.userInfo.description) is now online")
#if (os(macOS) || os(iOS))
      await setRegistered()
#endif
        case .transportDeregistering:
            logger.info("We are de-registering Session")
        case .transportOffline:
            logger.info("Successfully de-registerd Session")
            await messenger.setRegistrationState(.deregistered)
        case .shouldCloseChannel:
            logger.info("Should close channel")
        case .clientDisconnected:
            logger.info("Client has disconnected")
        }
    }
    
    @MainActor
    func setRegistered() async {
#if (os(macOS) || os(iOS))
        await self.messenger.emitter.connectionState = .registered
#endif
    }
    
    @MainActor
    func setState(_ currentState: State) async -> State {
#if (os(macOS) || os(iOS))
        await self.messenger.emitter.transportState = currentState
        return await self.messenger.emitter.transportState
#else
        return State.clientOffline
#endif
    }
}
