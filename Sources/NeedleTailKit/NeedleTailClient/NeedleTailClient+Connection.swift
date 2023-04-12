//
//  NeedleTailTransportClient+Connection.swift
//
//
//  Created by Cole M on 3/4/22.
//

import NeedleTailProtocol
import NeedleTailHelpers
import CypherMessaging
import NIOExtras

@NeedleTailClientActor
extension NeedleTailClient: ClientTransportDelegate {
    
    func attemptConnection() async throws {
            switch await transportState.current {
            case .clientOffline, .transportOffline:
                await transportState.transition(to: .clientConnecting)
                do {
                    let childChannel = try await createChannel(host: serverInfo.hostname, port: serverInfo.port)
                    try await addChildHandle(childChannel)
                    await transportState.transition(to: .clientConnected)
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
    
    func createChannel(host: String, port: Int) async throws -> NIOAsyncChannel<ByteBuffer, ByteBuffer> {
        return try await createBootstrap().connectAsync(host: host, port:port)
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
    
    func addChildHandle(_ childChannel: NIOAsyncChannel<ByteBuffer, ByteBuffer>) async throws {
        let handlers: (KeyBundleMechanism, NeedleTailTransport, TransportStore)? = try await withThrowingTaskGroup(of: (KeyBundleMechanism, NeedleTailTransport, TransportStore).self) { taskGroup in
            taskGroup.addTask { [weak self] in
                guard let strongSelf = self else { throw NeedleTailError.couldNotCreateHandlers }
                let handlers = try await strongSelf.createHandlers(childChannel)
                return handlers
            }
            return try await taskGroup.next()
        }
        await withThrowingTaskGroup(of: Void.self, body: { taskGroup in
            taskGroup.addTask {
                Task.detached { [weak self] in
                    guard let strongSelf = self else { return }
                    try await childChannel.channel.pipeline.addHandlers([
                        ByteToMessageHandler(
                            LineBasedFrameDecoder(),
                            maximumBufferSize: 16777216
                        ),
                    ], position: .first).get()
                    
                    let mechanism = try await strongSelf.setMechanisim(handlers?.0)
                    let transport = try await strongSelf.setTransport(handlers?.1)
                    let store = try await strongSelf.setStore(handlers?.2)
                    await strongSelf.handleChildChannel(childChannel.inboundStream, mechanism: mechanism, transport: transport, store: store)
                }
            }
        })
        await setChildChannel(childChannel)
        
    }
    
    func setChildChannel(_ childChannel: NIOAsyncChannel<ByteBuffer, ByteBuffer>) async {
        self.childChannel = childChannel
        
    }
    
    func handleChildChannel(_
                            stream: NIOInboundChannelStream<ByteBuffer>,
                            mechanism: KeyBundleMechanism,
                            transport: NeedleTailTransport,
                            store: TransportStore
    ) async {
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
                    self.logger.trace("Message Parsed \(parsedMessage)")
                    try await mechanism.processKeyBundle(parsedMessage)
                    try await transport.processReceivedMessages(parsedMessage)
                }
            }
        } catch {
            logger.error("Hit error: \(error)")
        }
    }
    
    private func createBootstrap() async throws -> NIOClientTCPBootstrap {
        return try await groupManager.makeBootstrap(hostname: serverInfo.hostname, useTLS: serverInfo.tls)
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
        let transport = NeedleTailTransport(
            ntkBundle: self.ntkBundle,
            channel: channel,
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
            ntkBundle.messenger.authenticated = .unauthenticated
            ntkBundle.messenger.isConnected = false
            await ntkBundle.messenger.client?.teardownClient()
            await transportState.transition(to: .clientOffline)
        } catch {
            ntkBundle.messenger.authenticated = .unauthenticated
            ntkBundle.messenger.isConnected = false
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
