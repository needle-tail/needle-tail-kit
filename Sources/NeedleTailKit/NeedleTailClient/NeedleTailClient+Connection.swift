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

extension NeedleTailClient: ClientTransportDelegate {
    
    // Due to NIOAsyncChannels new API we need to redesign the creation of connection and redirecting the stream of data. Do the following
    //1. Attempt Connection needs to be a long running task i.e. it never stops running until we close the connection intentionally. We can control the lenght of how long it runs by means of yet another state machine.
    //2. once connected and we call executeAndClose we need to set up inbound and outbound AsyncStreams that allow us to send the logic over to another method that handles the inbound and outbound logic whenever it needs to send events or receives data.
    // As long as we can do this we can keep the channel open and send and receive data.
    // The challenge will be keeping the long running task open and iterate over the outbound writer
    func processStream(
        childChannel: NIOAsyncChannel<ByteBuffer, ByteBuffer>,
        store: TransportStore
    ) async throws {
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                try Task.checkCancellation()
                try await childChannel.executeThenClose { inbound, outbound in
                    
                    switch await transportConfiguration.transportState.current {
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
                        
                        group.addTask {
                            for await writer in _outbound {
                                //Create Writer Class
                                let writer = try await NeedleTailWriter(
                                    asyncChannel: childChannel,
                                    writer: writer,
                                    transportState: self.transportConfiguration.transportState,
                                    clientContext: self.configuration.clientContext)
                                
                                let stream = await NeedleTailStream(
                                    configuration: NeedleTailStream.Configuration(
                                        writer: writer,
                                        ntkBundle: self.configuration.ntkBundle,
                                        clientContext: self.configuration.clientContext,
                                        store: store,
                                        messenger: self.configuration.messenger,
                                        transportState: self.transportConfiguration.transportState)
                                )
                                try await self.finishRegistering(with: stream, and: writer)
                            }
                        }
                        
                        for await stream in _inbound {
                            do {
                                for try await buffer in stream {
                                    group.addTask { [weak self] in
                                    guard let self else { return }
                                        var buffer = buffer
                                        guard let message = buffer.readString(length: buffer.readableBytes) else { return }
                                        guard !message.isEmpty else { return }
                                        let messages = message.components(separatedBy: Constants.cLF.rawValue)
                                            .map { $0.replacingOccurrences(of: Constants.cCR.rawValue, with: Constants.space.rawValue) }
                                            .filter { !$0.isEmpty }
                                        
                                        for message in messages {
                                            guard let parsedMessage = AsyncMessageTask.parseMessageTask(task: message, messageParser: MessageParser()) else { break }
                                            self.logger.trace("Message Parsed \(parsedMessage)")
                                            await self.stream?.processReceivedMessage(parsedMessage)
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
            await transportConfiguration.transportState.transition(to: .clientOffline)
            try await attemptDisconnect(true)
            await setAuthenticationState(ntkBundle: configuration.ntkBundle)
            throw error
        }
        throw NeedleTailError.couldNotConnectToNetwork
    }
    
    func setAuthenticationState(ntkBundle: NTKClientBundle) async {
        ntkBundle.cypherTransport.authenticated = .unauthenticated
    }
    
    func setStore(_ store: TransportStore?) async throws {
        self.store = store
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
    
    //Transport Delegate Method
    func shutdown() async {
        await shutdownClient()
    }
    
    func shutdownClient() async {
        await stream?.configuration.transportState.transition(to: .shouldCloseChannel)
        continuation?.finish()
        inboundContinuation?.finish()
        cancelInboundStream()
        await groupManager.shutdown()
        await transportConfiguration.client?.teardownClient()
        await transportConfiguration.transportState.transition(to: .clientOffline)
    }
    
    private func cancelInboundStream() {
        cancelStream = true
    }
    
    /// We send the disconnect message and wait for the ACK before shutting down the connection to the server
    func attemptDisconnect(_ isSuspending: Bool) async throws {
        if isSuspending {
            await transportConfiguration.transportState.transition(to: .transportDeregistering)
        }
        
        switch await transportConfiguration.transportState.current {
        case .transportDeregistering:
            if transportConfiguration.username == nil && self.transportConfiguration.deviceId == nil {
                guard let nick = transportConfiguration.needleTailNick else { return }
                transportConfiguration.username = Username(nick.name)
                transportConfiguration.deviceId = nick.deviceId
            }
            guard let username = transportConfiguration.username else { throw NeedleTailError.usernameNil }
            guard let deviceId = transportConfiguration.deviceId else { throw NeedleTailError.deviceIdNil }
            try await self.writer?.sendQuit(username, deviceId: deviceId)
            configuration.ntkBundle.cypherTransport.authenticated = .unauthenticated
        default:
            break
        }
    }
    
    func requestOfflineMessages() async throws{
        try await self.writer?.requestOfflineMessages()
    }
    
    func deleteOfflineMessages(from contact: String) async throws {
        try await self.writer?.deleteOfflineMessages(from: contact)
    }
    
    func notifyContactRemoved(_ ntkUser: NTKUser, removed contact: Username) async throws {
        try await self.writer?.notifyContactRemoved(ntkUser, removed: contact)
    }
}
