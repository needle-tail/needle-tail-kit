//
//  NeedleTailTransportClient+Connection.swift
//  
//
//  Created by Cole M on 3/4/22.
//

import NIOCore
import NIOPosix
import NeedleTailProtocol
import NeedleTailHelpers
import BSON
import Foundation
import CypherMessaging

@NeedleTailClientActor
extension NeedleTailClient: NeedleTailHandlerDelegate {
    
    func passMessage(_ message: NeedleTailProtocol.IRCMessage) async throws {
        try await self.mechanism?.processKeyBundle(message)
        try await self.transport?.processReceivedMessages(message)
    }
    
    
    func attemptConnection() async throws {
        switch await transportState.current {
        case .clientOffline:
            await transportState.transition(to: .clientConnecting)
            try await startClient()
        default:
            break
        }
    }
    
    func startClient() async throws {
        do {
            self.channel = try await createChannel(host: clientInfo.hostname, port: clientInfo.port)
            self.userInfo = clientContext.userInfo
            await transportState.transition(to: .clientConnected)
        } catch {
            logger.error("Could not start client: \(error)")
            await transportState.transition(to: .clientOffline)
            try await attemptDisconnect(true)
            messenger.authenticated  = .unauthenticated
        }
    }
    
    func createChannel(host: String, port: Int) async throws -> Channel {
        userMode = IRCUserMode()
        return try await createBootstrap()
            .connect(host: host, port: port).get()
    }
    
    private func createBootstrap() async throws -> NIOClientTCPBootstrap {
        return try await groupManager.makeBootstrap(hostname: clientInfo.hostname, useTLS: clientInfo.tls)
            .connectTimeout(.minutes(1))
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET),SO_REUSEADDR), value: 1)
        //            .channelInitializer { channel in
        ////                channel.eventLoop.executeAsync {
        //////                await self.createHandlers(channel)
        ////
        ////                   return try await channel.pipeline.addHandlers([
        //////                        AsyncMessageChannelHandlerAdapter<ByteBuffer, ByteBuffer>(logger: self.logger, closeRatchet: NeedleTailProtocol.CloseRatchet()),
        //////                        NeedleTailHandler<ByteBuffer>(closeRatchet: CloseRatchet(), needleTailHandlerDelegate: self)
        ////                    ])
        ////                }
        //            }
    }
    
    
    func createAsyncHandler(_ wrapping: Channel, completionHandler: (NIOAsyncChannel<ByteBuffer, ByteBuffer>) -> NIOAsyncChannel<ByteBuffer, ByteBuffer>) async throws -> NIOAsyncChannel<ByteBuffer, ByteBuffer> {
        let handler = try await NIOAsyncChannel<ByteBuffer, ByteBuffer>(wrapping: wrapping)
        return completionHandler(handler)
    }
    
    func createHandlers(_ channel: Channel) async {
        self.store = await createStore()
        guard let store = self.store else { return }
        self.mechanism = await createMechanism(channel, store: store)
        self.transport = await createTransport(channel, store: store)
    }
    
    func createStore() async -> TransportStore {
        TransportStore()
    }
    
    @KeyBundleMechanismActor
    func createMechanism(_ channel: Channel, store: TransportStore) async -> KeyBundleMechanism {
        let context = await self.clientContext
        return KeyBundleMechanism(channel: channel, store: store, clientContext: context)
    }
    
    @NeedleTailTransportActor
    func createTransport(_ channel: Channel, store: TransportStore) async -> NeedleTailTransport {
        return await NeedleTailTransport(
            cypher: self.cypher,
            messenger: self.messenger,
            channel: channel,
            userMode: self.userMode,
            transportState: self.transportState,
            signer: self.signer,
            clientContext: self.clientContext,
            clientInfo: self.clientInfo,
            store: store
        )
    }
    
    func attemptDisconnect(_ isSuspending: Bool) async throws {
        if isSuspending {
            await transportState.transition(to: .transportDeregistering)
        }
        
        switch await transportState.current {
        case .transportDeregistering:
            if self.messenger.username == nil && self.messenger.deviceId == nil {
                guard let nick = messenger.needleTailNick else { return }
                self.messenger.username = Username(nick.name)
                self.messenger.deviceId = nick.deviceId
            }
            guard let username = self.messenger.username else { throw NeedleTailError.usernameNil }
            guard let deviceId = self.messenger.deviceId else { throw NeedleTailError.deviceIdNil }
            try await transport?.sendQuit(username, deviceId: deviceId)
            await transportState.transition(to: .transportOffline)
            messenger.authenticated = .unauthenticated
        default:
            break
        }
    }
    
}
