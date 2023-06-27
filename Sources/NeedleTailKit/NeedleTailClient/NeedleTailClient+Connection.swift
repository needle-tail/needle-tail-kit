//
//  NeedleTailTransportClient+Connection.swift
//
//
//  Created by Cole M on 3/4/22.
//

import NeedleTailHelpers
import CypherMessaging
import NIOExtras
import NIOTransportServices
import Logging
@_spi(AsyncChannel) import NIOCore
@_spi(AsyncChannel) import NeedleTailProtocol


@NeedleTailClientActor
extension NeedleTailClient: ClientTransportDelegate {
    
    func attemptConnection() async throws {
        switch await transportState.current {
        case .clientOffline, .transportOffline:
            await transportState.transition(to: .clientConnecting)
            
            do {
                
                try await withThrowingTaskGroup(of: NIOAsyncChannel<ByteBuffer, ByteBuffer>.self) { group in
                    try Task.checkCancellation()
                    group.addTask {
                        return try await self.createChannel(
                            host: self.serverInfo.hostname,
                            port: self.serverInfo.port,
                            enableTLS: self.serverInfo.tls
                        )
                    }
                    let nextItem = try await group.next()
                    guard let childChannel = nextItem else { return }
                    
                    try await RunLoop.run(30, sleep: 1, stopRunning: {
                        var canRun = true
                        if childChannel.channel.isActive  {
                            canRun = false
                        }
                        return canRun
                    })
                    
                    group.addTask {
                        
                        let handlers = try await self.createHandlers(childChannel)
                        async let mechanism = try await self.setMechanisim(handlers.0)
                        async let transport = try await self.setTransport(handlers.1)
                        async let store = try await self.setStore(handlers.2)
                        
                        await NeedleTailClient.handleChildChannel(
                            childChannel.inboundStream,
                            mechanism: try await mechanism,
                            transport: try await transport,
                            store: try await store
                        )
                        
                        await self.setChildChannel(childChannel)
                        await self.transportState.transition(to: .clientConnected)
                        return childChannel
                    }
                    _ = try await group.next()
                    group.cancelAll()
                }
                
                
                
            } catch {
                logger.error("Could not start client: \(error)")
                await transportState.transition(to: .clientOffline)
                try await attemptDisconnect(true)
                ntkBundle.messenger.authenticated  = .unauthenticated
            }
        default:
            break
        }
    }
    
    
    func setStore(_ store: TransportStore?) async throws -> TransportStore {
        self.store = store
        guard let store = self.store else { throw NeedleTailError.storeNotIntitialized }
        return store
    }
    
    @KeyBundleMechanismActor
    func setMechanisim(_ mechanism: KeyBundleMechanism?) async throws -> KeyBundleMechanism {
        self.mechanism = mechanism
        guard let mechanism = self.mechanism else { throw NeedleTailError.mechanisimNotIntitialized }
        return mechanism
    }
    
    @NeedleTailTransportActor
    func setTransport(_ transport: NeedleTailTransport?) async throws -> NeedleTailTransport {
        self.transport = transport
        guard let transport = self.transport else { throw NeedleTailError.transportNotIntitialized }
        return transport
    }
    
    func setChildChannel(_ childChannel: NIOAsyncChannel<ByteBuffer, ByteBuffer>) async {
        self.childChannel = childChannel
#if (os(macOS) || os(iOS))
        await transport?.emitter?.channelIsActive = childChannel.channel.isActive
#endif
    }
    
    static func handleChildChannel(_
                                   stream: NIOAsyncChannelInboundStream<ByteBuffer>,
                                   mechanism: KeyBundleMechanism,
                                   transport: NeedleTailTransport,
                                   store: TransportStore
    ) async {
        //TODO: THIS IS BAD BUT WE CANNOT RECEIVE UPDATES FROM THE CHANNEL WITH OUT DETACHING FOR SOME REASON
        Task.detached { 
            do {
                for try await buffer in stream {
                    var buffer = buffer
                    guard let message = buffer.readString(length: buffer.readableBytes) else { break }
                    guard !message.isEmpty else { return }
                    let messages = message.components(separatedBy: Constants.cLF.rawValue)
                        .map { $0.replacingOccurrences(of: Constants.cCR.rawValue, with: Constants.space.rawValue) }
                        .filter { !$0.isEmpty }
                    
                    for await message in messages.async {
                        guard let parsedMessage = AsyncMessageTask.parseMessageTask(task: message, messageParser: MessageParser()) else { break }
                        Logger(label: "Child Channel Processor").trace("Message Parsed \(parsedMessage)")
                        await mechanism.processKeyBundle(parsedMessage)
                        await transport.processReceivedMessages(parsedMessage)
                    }
                }
            } catch {
                Logger(label: "Child Channel Processor").error("Hit error: \(error)")
            }
        }
    }
    
    
    @_spi(AsyncChannel)
    public func createChannel(
        host: String,
        port: Int,
        enableTLS: Bool
    ) async throws -> NIOAsyncChannel<ByteBuffer, ByteBuffer> {
        return try await groupManager.makeAsyncChannel(
            host: host,
            port: port,
            enableTLS: enableTLS
        )
    }
    
    func createHandlers(_ channel: NIOAsyncChannel<ByteBuffer, ByteBuffer>) async throws -> (KeyBundleMechanism, NeedleTailTransport, TransportStore) {
        let store = await createStore()
        async let mechanism = try await createMechanism(channel, store: store)
        async let transport = await createTransport(channel, store: store)
        return try await (mechanism, transport, store)
    }
    
    func createStore() async -> TransportStore {
        TransportStore()
    }
    
    @KeyBundleMechanismActor
    func createMechanism(_ channel: NIOAsyncChannel<ByteBuffer, ByteBuffer>, store: TransportStore) async throws -> KeyBundleMechanism {
        let context = self.clientContext
        return KeyBundleMechanism(asyncChannel: channel, store: store, clientContext: context)
    }
    
    @NeedleTailTransportActor
    func createTransport(_ asyncChannel: NIOAsyncChannel<ByteBuffer, ByteBuffer>, store: TransportStore) async -> NeedleTailTransport {
        let transport = NeedleTailTransport(
            ntkBundle: self.ntkBundle,
            asyncChannel: asyncChannel,
            transportState: self.transportState,
            clientContext: self.clientContext,
            store: store
        )
        return transport
    }
    
    //Transport Delegate Method
    func shutdown() async {
        await shutdownClient()
    }
    
    func shutdownClient() async {
        do {
            guard let channel = childChannel?.channel else { throw NeedleTailError.channelIsNil }
            _ = try await channel.close(mode: .all).get()
            try await groupManager.shutdown()
            await ntkBundle.messenger.client?.teardownClient()
            await transportState.transition(to: .clientOffline)
        } catch {
            await transportState.transition(to: .clientOffline)
            logger.error("Could not gracefully shutdown, Forcing the exit (\(error.localizedDescription))")
            if error.localizedDescription != "alreadyClosed" {
                exit(0)
            }
        }
    }
    
    /// We send the disconnect message and wait for the ACK before shutting down the connection to the server
    func attemptDisconnect(_ isSuspending: Bool) async throws {
        if isSuspending {
            await transportState.transition(to: .transportDeregistering)
        }
        
        switch await transportState.current {
        case .transportDeregistering:
            if self.ntkBundle.messenger.username == nil && self.ntkBundle.messenger.deviceId == nil {
                guard let nick = ntkBundle.messenger.needleTailNick else { return }
                self.ntkBundle.messenger.username = Username(nick.name)
                self.ntkBundle.messenger.deviceId = nick.deviceId
            }
            guard let username = self.ntkBundle.messenger.username else { throw NeedleTailError.usernameNil }
            guard let deviceId = self.ntkBundle.messenger.deviceId else { throw NeedleTailError.deviceIdNil }
            try await self.transport?.sendQuit(username, deviceId: deviceId)
            await transportState.transition(to: .transportOffline)
            ntkBundle.messenger.authenticated = .unauthenticated
        default:
            break
        }
    }
    
    func requestOfflineMessages() async throws{
        try await self.transport?.requestOfflineMessages()
    }
    
    func deleteOfflineMessages(from contact: String) async throws {
        try await self.transport?.deleteOfflineMessages(from: contact)
    }
    
    func notifyContactRemoved(_ ntkUser: NTKUser, removed contact: Username) async throws {
        try await self.transport?.notifyContactRemoved(ntkUser, removed: contact)
    }
}
