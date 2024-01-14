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
import NIOCore
import NeedleTailProtocol

#if (os(macOS) || os(iOS))
extension NeedleTailClient: ClientTransportDelegate {
    
    // Due to NIOAsyncChannels new API we need to redesign the creation of connection and redirecting the stream of data. Do the following
    //1. Attempt Connection needs to be a long running task i.e. it never stops running until we close the connection intentionally. We can control the lenght of how long it runs by means of yet another state machine.
    //2. once connected and we call executeAndClose we need to set up inbound and outbound AsyncStreams that allow us to send the logic over to another method that handles the inbound and outbound logic whenever it needs to send events or receives data.
    // As long as we can do this we can keep the channel open and send and receive data.
    // The challenge will be keeping the long running task open and iterate over the outbound writer
    
    @NeedleTailTransportActor
    func processStream(childChannel: NIOAsyncChannel<ByteBuffer, ByteBuffer>) async throws {
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                try Task.checkCancellation()
                try await childChannel.executeThenClose { inbound, outbound in
                    switch transportState.current {
                    case .clientConnected:
                      
                        // set up async streams and handle data
                        let _outbound = AsyncStream<NIOAsyncChannelOutboundWriter<ByteBuffer>> { continuation in
                            continuation.yield(outbound)
                            self.continuation = continuation
                            continuation.onTermination = { status in
                                print("Writer Stream Terminated with status:", status)
                            }
                        }
                      
                        let _inbound = AsyncStream<NIOAsyncChannelInboundStream<ByteBuffer>> { continuation in
                            continuation.yield(inbound)
                            self.inboundContinuation = continuation
                            continuation.onTermination = { status in
                                print("Inbound Stream Terminated with status:", status)
                            }
                        }
                        
                        group.addTask { @NeedleTailTransportActor in
                            for await writer in _outbound {
                                self.writer = writer
                            }
                        }
                        
                        for await stream in _inbound {
                            do {
                                for try await buffer in stream {
                                    group.addTask {
                                        var buffer = buffer
                                        guard let message = buffer.readString(length: buffer.readableBytes) else { fatalError() }
                                        guard !message.isEmpty else { fatalError() }
                                        let messages = message.components(separatedBy: Constants.cLF.rawValue)
                                            .map { $0.replacingOccurrences(of: Constants.cCR.rawValue, with: Constants.space.rawValue) }
                                            .filter { !$0.isEmpty }
                                        
                                        for message in messages {
                                            guard let parsedMessage = AsyncMessageTask.parseMessageTask(task: message, messageParser: MessageParser()) else { break }
                                            self.logger.trace("Message Parsed \(parsedMessage)")
                                            await self.mechanism?.processKeyBundle(parsedMessage)
                                            await self.transport?.processReceivedMessages(parsedMessage)
                                        }
                                    }
                                    if cancelStream {
                                        return
                                    }
                                }
                            } catch {
                                print(error)
                            }
                        }
                        return
                    default:
                        break
                    }
                }
            }
        } catch {
            logger.error("Could not start client: \(error)")
            await transportState.transition(to: .clientOffline)
            try await attemptDisconnect(true)
            await setAuthenticationState(ntkBundle: ntkBundle)
            throw error
        }
        throw NeedleTailError.couldNotConnectToNetwork
    }
    
    @NeedleTailTransportActor
    func setAuthenticationState(ntkBundle: NTKClientBundle) async {
        ntkBundle.cypherTransport.authenticated = .unauthenticated
    }
    
    @KeyBundleMechanismActor
    func setStore(_ store: TransportStore?) async throws {
        self.store = store
    }
    
    @KeyBundleMechanismActor
    func setMechanisim(_ mechanism: KeyBundleMechanism?) async throws {
        self.mechanism = mechanism
    }
    
    @NeedleTailClientActor
    func setTransport(_
                      transport: NeedleTailTransport?,
                      cypherTransport: NeedleTailCypherTransport
    ) async throws {
        let job: Deque<NeedleTailCypherTransport.DelegateJob> = try await cypherTransport.delegateJob.checkForExistingJobs { [weak self] job in
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
        if let unwrappedTransport = job.last?.transport {
            await setTransport(transport: unwrappedTransport)
        } else {
            await setTransport(transport: transport!)
        }
    }
    
    @NeedleTailTransportActor
    func setTransport(transport: NeedleTailTransport) async {
        self.transport = transport
    }
    
    func setChildChannel(_ childChannel: NIOAsyncChannel<ByteBuffer, ByteBuffer>) async {
        self.childChannel = childChannel
        self.channelIsActive = childChannel.channel.isActive
    }
    
    
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
    ) async throws -> (TransportStore, KeyBundleMechanism, NeedleTailTransport) {
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
        return try await (store, mechanism, transport)
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
        await transport?.transportState.transition(to: .shouldCloseChannel)
        await continuation?.finish()
        await inboundContinuation?.finish()
        await cancelInboundStream()
        await groupManager.shutdown()
        await ntkBundle.cypherTransport.configuration.client?.teardownClient()
        await transportState.transition(to: .clientOffline)
    }
    
    @NeedleTailTransportActor
    func cancelInboundStream() {
        cancelStream = true
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
