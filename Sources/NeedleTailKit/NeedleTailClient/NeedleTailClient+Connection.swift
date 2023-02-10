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

//@NeedleTailClientActor
extension NeedleTailClient: ClientTransportDelegate {
    
    func attemptConnection() async throws {
        switch await transportState.current {
        case .clientOffline:
            await transportState.transition(to: .clientConnecting)
            do {
                let clientChannel = try await createChannel(host: clientInfo.hostname, port: clientInfo.port)
                try await addChildHandle(clientChannel)
                self.userInfo = clientContext.userInfo
                await transportState.transition(to: .clientConnected)
            } catch {
                logger.error("Could not start client: \(error)")
                await transportState.transition(to: .clientOffline)
                try await attemptDisconnect(true)
                messenger.authenticated  = .unauthenticated
            }
        default:
            break
        }
    }
    
    
    func createChannel(host: String, port: Int) async throws -> NIOAsyncChannel<ByteBuffer, ByteBuffer> {
        userMode = IRCUserMode()
        return try await createBootstrap().connectAsync(host: host, port:port)
    }
    
    @KeyBundleMechanismActor
    func setMechanisim(_ mechanism: KeyBundleMechanism) {
        self.mechanism = mechanism
    }
    
    @NeedleTailTransportActor
    func setTransport(_ transport: NeedleTailTransport) {
        self.mtDelegate = transport
        self.transport = transport
    }
    
    
    //This never exits the stream
    func addChildHandle(_ clientChannel: NIOAsyncChannel<ByteBuffer, ByteBuffer>) async throws {
        let handlers = try await self.createHandlers(clientChannel)
        store = handlers.2
        await setMechanisim(handlers.0)
        await setTransport(handlers.1)
        self.asyncChannel = clientChannel
        handleStream(clientChannel.inboundStream)
    }
    
    func handleChildChannel(_ stream: NIOInboundChannelStream<ByteBuffer>, mechanism: KeyBundleMechanism, transport: NeedleTailTransport, store: TransportStore) async {
        
        do {
            for try await buffer in stream {
                var buffer = buffer
                guard let message = buffer.readString(length: buffer.readableBytes) else { return }
                guard !message.isEmpty else { return }
                let messages = message.components(separatedBy: Constants.cLF)
                    .map { $0.replacingOccurrences(of: Constants.cCR, with: Constants.space) }
                    .filter { !$0.isEmpty }
                
                
                for message in messages {
                    let parsedMessage = try await AsyncMessageTask.parseMessageTask(task: message, messageParser: MessageParser())
                    self.logger.info("Message Parsed \(parsedMessage)")
                    try await mechanism.processKeyBundle(parsedMessage)
                    try await transport.processReceivedMessages(parsedMessage)
                }
            }
        } catch {
            logger.error("Hit error: \(error)")
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
        let context = self.clientContext
        return KeyBundleMechanism(channel: channel, store: store, clientContext: context)
    }
    
    @NeedleTailTransportActor
    func createTransport(_ channel: NIOAsyncChannel<ByteBuffer, ByteBuffer>, store: TransportStore) async -> NeedleTailTransport {
        return NeedleTailTransport(
            cypher: self.cypher,
            channel: channel,
            userMode: self.userMode,
            transportState: self.transportState,
            signer: self.signer,
            clientContext: self.clientContext,
            clientInfo: self.clientInfo,
            store: store,
            ctDelegate: self
        )
    }
    
    //Transport Delegate Method
    func shutdown() async {
        await shutdownClient()
    }
    
    func shutdownClient() async {
        do {
            guard let channel = asyncChannel?.channel else { throw NeedleTailError.channelIsNil }
            _ = try await channel.close(mode: .all).get()
            try await groupManager.shutdown()
            await removeReferences()
            await transportState.transition(to: .clientOffline)
            //            isConnected = false
            logger.info("disconnected from server")
            await transportState.transition(to: .transportOffline)
            //            authenticated = .unauthenticated
        } catch {
            logger.error("Could not gracefully shutdown, Forcing the exit (\(error))")
            exit(0)
        }
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
            try await self.transport?.sendQuit(username, deviceId: deviceId)
            await transportState.transition(to: .transportOffline)
            messenger.authenticated = .unauthenticated
        default:
            break
        }
    }
    
}
