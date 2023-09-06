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
import DequeModule
@_spi(AsyncChannel) import NIOCore
@_spi(AsyncChannel) import NeedleTailProtocol

#if (os(macOS) || os(iOS))
extension NeedleTailClient: ClientTransportDelegate {
    
    func attemptConnection(
        serverInfo: ClientContext.ServerClientInfo,
        groupManager: EventLoopGroupManager,
        eventLoopGroup: EventLoopGroup,
        ntkBundle: NTKClientBundle,
        transportState: TransportState,
        clientContext: ClientContext,
        messenger: NeedleTailMessenger
    ) async throws {
        switch await transportState.current {
        case .clientOffline, .transportOffline:
            await transportState.transition(to: .clientConnecting)
            
            do {
                try await withThrowingTaskGroup(of: NIOAsyncChannel<ByteBuffer, ByteBuffer>.self) { taskGroup in
                    try Task.checkCancellation()
                    taskGroup.addTask {
                        return try await self.createChannel(
                            host: serverInfo.hostname,
                            port: serverInfo.port,
                            enableTLS: serverInfo.tls,
                            groupManager: groupManager,
                            group: eventLoopGroup
                        )
                    }
                    let nextItem = try await taskGroup.next()
                    guard let childChannel = nextItem else { return }
                    taskGroup.addTask {
                        
                        let handlers = try await self.createHandlers(
                            childChannel,
                            ntkBundle: ntkBundle,
                            transportState: transportState,
                            clientContext: clientContext,
                            messenger: messenger
                        )
                        async let mechanism = try await self.setMechanisim(handlers.0)
                        async let transport = try await self.setTransport(handlers.1)
                        async let _ = try await self.setStore(handlers.2)

                        await NeedleTailClient.handleChildChannel(
                            childChannel.inboundStream,
                            mechanism: try await mechanism,
                            transport: try await transport
                        )
                        
                        await self.setChildChannel(childChannel)
                        await self.transportState.transition(to: .clientConnected)
                        return childChannel
                    }
                    _ = try await taskGroup.next()
                    taskGroup.cancelAll()
                }
            } catch {
                logger.error("Could not start client: \(error)")
                await transportState.transition(to: .clientOffline)
                try await attemptDisconnect(true)
                await setAuthenticationState(ntkBundle: ntkBundle)
            }
        default:
            break
        }
    }
    
    
    
    @NeedleTailTransportActor
    func setAuthenticationState(ntkBundle: NTKClientBundle) async {
        ntkBundle.cypherTransport.authenticated  = .unauthenticated
    }
    
    @KeyBundleMechanismActor
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
    
    func setTransport(_ transport: NeedleTailTransport?) async throws -> NeedleTailTransport {
     
        let job: Deque<NeedleTailCypherTransport.DelegateJob> = try await self.delegateJob.checkForExistingJobs { [weak self] job in
            guard let self else { return job }
            guard let transport = transport else { return job }
            let setTransport = await self.setDelegates(
                transport,
                delegate: job.delegate,
                plugin: job.plugin,
                messenger: job.messenger
            )
            var job = job
            job.transport = setTransport
            return job
        }
        self.transport = job.last?.transport
        guard let transport = self.transport else { throw NeedleTailError.transportNotIntitialized }
        return transport
    }
    
    func setChildChannel(_ childChannel: NIOAsyncChannel<ByteBuffer, ByteBuffer>) async {
        self.childChannel = childChannel
#if (os(macOS) || os(iOS))
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.transport?.messenger.emitter.channelIsActive = childChannel.channel.isActive
        }
#endif
    }
    
    static func handleChildChannel(_
                                   stream: NIOAsyncChannelInboundStream<ByteBuffer>,
                                   mechanism: KeyBundleMechanism,
                                   transport: NeedleTailTransport
    ) async {
        Task {
            let messageParser = MessageParser()
            try Task.checkCancellation()
            do {
                for try await buffer in stream {
                    var buffer = buffer
                    guard let message = buffer.readString(length: buffer.readableBytes) else { break }
                    guard !message.isEmpty else { return }
                    let messages = message.components(separatedBy: Constants.cLF.rawValue)
                        .map { $0.replacingOccurrences(of: Constants.cCR.rawValue, with: Constants.space.rawValue) }
                        .filter { !$0.isEmpty }
                    
                    for message in messages {
                        guard let parsedMessage = AsyncMessageTask.parseMessageTask(task: message, messageParser: messageParser) else { break }
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
        enableTLS: Bool,
        groupManager: EventLoopGroupManager,
        group: EventLoopGroup
    ) async throws -> NIOAsyncChannel<ByteBuffer, ByteBuffer> {
        return try await groupManager.makeAsyncChannel(
            host: host,
            port: port,
            enableTLS: enableTLS,
            group: group
        )
    }
    
    func createHandlers(_
                        channel: NIOAsyncChannel<ByteBuffer, ByteBuffer>,
                        ntkBundle: NTKClientBundle,
                        transportState: TransportState,
                        clientContext: ClientContext,
                        messenger: NeedleTailMessenger
    ) async throws -> (KeyBundleMechanism, NeedleTailTransport, TransportStore) {
        let store = await createStore()
        async let mechanism = try await createMechanism(channel, store: store)
        async let transport = await createTransport(
            channel,
            store: store,
            ntkBundle: ntkBundle,
            transportState: transportState,
            clientContext: clientContext,
            messenger: messenger
        )
        return try await (mechanism, transport, store)
    }
    
    func createStore() async -> TransportStore {
        TransportStore()
    }
    
    func createMechanism(_ channel: NIOAsyncChannel<ByteBuffer, ByteBuffer>, store: TransportStore) async throws -> KeyBundleMechanism {
        let context = self.clientContext
        return await KeyBundleMechanism(asyncChannel: channel, store: store, clientContext: context)
    }
    
    func createTransport(_
                         asyncChannel: NIOAsyncChannel<ByteBuffer, ByteBuffer>,
                         store: TransportStore,
                         ntkBundle: NTKClientBundle,
                         transportState: TransportState,
                         clientContext: ClientContext,
                         messenger: NeedleTailMessenger
    ) async -> NeedleTailTransport {
        return await NeedleTailTransport(
            ntkBundle: ntkBundle,
            asyncChannel: asyncChannel,
            transportState: transportState,
            clientContext: clientContext,
            store: store,
            messenger: messenger
        )
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
            await ntkBundle.cypherTransport.configuration.client?.teardownClient()
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
    @NeedleTailTransportActor
    func attemptDisconnect(_ isSuspending: Bool) async throws {
        if isSuspending {
            await transportState.transition(to: .transportDeregistering)
        }
        
        switch transportState.current {
        case .transportDeregistering:
            if self.ntkBundle.cypherTransport.configuration.username == nil && self.ntkBundle.cypherTransport.configuration.deviceId == nil {
                guard let nick = ntkBundle.cypherTransport.configuration.needleTailNick else { return }
                self.ntkBundle.cypherTransport.configuration.username = Username(nick.name)
                self.ntkBundle.cypherTransport.configuration.deviceId = nick.deviceId
            }
            guard let username = self.ntkBundle.cypherTransport.configuration.username else { throw NeedleTailError.usernameNil }
            guard let deviceId = self.ntkBundle.cypherTransport.configuration.deviceId else { throw NeedleTailError.deviceIdNil }
            try await self.transport?.sendQuit(username, deviceId: deviceId)
            await transportState.transition(to: .transportOffline)
            ntkBundle.cypherTransport.authenticated = .unauthenticated
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
#endif
