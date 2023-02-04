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
extension NeedleTailClient {
    
    //    func passMessage(_ message: NeedleTailProtocol.IRCMessage) async throws {
    //        try await self.mechanism?.processKeyBundle(message)
    //        try await self.transport?.processReceivedMessages(message)
    //    }
    
    
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
            let asyncChannel = try await createChannel(host: clientInfo.hostname, port: clientInfo.port)
            self.channel = asyncChannel.channel
            try await addChildHandle(asyncChannel)
            self.userInfo = clientContext.userInfo
            await transportState.transition(to: .clientConnected)
        } catch {
            logger.error("Could not start client: \(error)")
            await transportState.transition(to: .clientOffline)
            try await attemptDisconnect(true)
            messenger.authenticated  = .unauthenticated
        }
    }
    
    
    
    func createChannel(host: String, port: Int) async throws -> NIOAsyncChannel<NIOAsyncChannel<ByteBuffer, ByteBuffer>, Never> {
        userMode = IRCUserMode()
        return try await createBootstrap().connectAsync(host: host, port:port)
    }
    
    func addChildHandle(_ asyncChannel: NIOAsyncChannel<NIOAsyncChannel<ByteBuffer, ByteBuffer>, Never>) async throws {
        try await withThrowingTaskGroup(of: Void.self) { taskGroup in
            for try await childChannel in asyncChannel.inboundStream {
               let handlers = try await self.createHandlers(childChannel)
                self.asyncChannel = childChannel
                taskGroup.addTask {
                    await Self.handleChildChannel(childChannel, mechanism: handlers.0, transport: handlers.1, store: handlers.2)
                }
            }
        }
    }
    
    private static func handleChildChannel(_ asyncChannel: NIOAsyncChannel<ByteBuffer, ByteBuffer>, mechanism: KeyBundleMechanism, transport: NeedleTailTransport, store: TransportStore) async {
        Self.store = store
        Self.mechanism = mechanism
        Self.transport = transport
        do {
            for try await buffer in asyncChannel.inboundStream {
                var buffer = buffer
//                self.logger.trace("Successfully got message from sequence in AsyncMessageChannelHandlerAdapter")
                guard let message = buffer.readString(length: buffer.readableBytes) else { return }
                guard !message.isEmpty else { return }
                let messages = message.components(separatedBy: Constants.cLF)
                    .map { $0.replacingOccurrences(of: Constants.cCR, with: Constants.space) }
                    .filter { !$0.isEmpty }
              
                
                for message in messages {
                    let parsedMessage = try await AsyncMessageTask.parseMessageTask(task: message, messageParser: MessageParser())
                    try await mechanism.processKeyBundle(parsedMessage)
                    try await transport.processReceivedMessages(parsedMessage)
                }
                }
            } catch {
                //            logger.error("Hit error: \(error)")
            }
        }
        
        private func createBootstrap() async throws -> NIOClientTCPBootstrap {
            return try await groupManager.makeBootstrap(hostname: clientInfo.hostname, useTLS: clientInfo.tls)
                .connectTimeout(.minutes(1))
                .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET),SO_REUSEADDR), value: 1)
        }
        
        func createHandlers(_ channel: NIOAsyncChannel<ByteBuffer, ByteBuffer>) async throws -> (KeyBundleMechanism, NeedleTailTransport, TransportStore) {
            let store = await createStore()
            let mechanism = try await createMechanism(channel, store: store)
            let transport = await createTransport(channel, store: store)
            return (mechanism, transport, store)
        }
        
        func createStore() async -> TransportStore {
            TransportStore()
        }
        
        @KeyBundleMechanismActor
        func createMechanism(_ channel: NIOAsyncChannel<ByteBuffer, ByteBuffer>, store: TransportStore) async throws -> KeyBundleMechanism {
            let context = await self.clientContext
            guard let asyncChannel = await asyncChannel else { throw NeedleTailError.channelIsNil }
            return KeyBundleMechanism(channel: asyncChannel, store: store, clientContext: context)
        }
        
        @NeedleTailTransportActor
        func createTransport(_ channel: NIOAsyncChannel<ByteBuffer, ByteBuffer>, store: TransportStore) async -> NeedleTailTransport {
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
                try await Self.transport?.sendQuit(username, deviceId: deviceId)
                await transportState.transition(to: .transportOffline)
                messenger.authenticated = .unauthenticated
            default:
                break
            }
        }
        
    }
