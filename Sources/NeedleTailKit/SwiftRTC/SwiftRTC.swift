//
//  SwiftRTC.swift
//  
//
//  Created by Cole M on 2/13/22.
//

import NIO
import Dribble
import CypherMessaging
#if canImport(Network)
import NIOTransportServices



///Basic P2P flow is. We can call the methods from our CypherMessenger
///CypherMessenger.sendRawMessage()
///1. Register Cypher Messenger with P2PHandler
///2. buildP2PConnections()
/// Calling send raw message willl send to CypherTextKit which will encrypt it at queue it in a job and then execute `writeMessageTask`. If we have P2P
/// set up the it will send the message via P2P via the `getEstablishedP2PConnection` with the `P2PClient`, otherwise it will use our transport method and send it to the server.
/// Inside this class is where we will set up how `P2PClient` will use `sendMessage` by conforming to `P2PTransportClient` protocol
///3 sendRawMessage()
///4. receiveMessage()
///
///We start a session by calling resume on messenger

enum SwiftRTCErrors: Error {
    case nilGroup
}

public class SwiftRTC: P2PTransportClientFactory {
    
    
    // We want to set up a P2P connection. Sending the needed information about each client. When a user recieves an offer they send the answer and once an agreement is made we can send our UDP Data P2P.
    public let transportLayerIdentifier: String = "_udp"
    var group: EventLoopGroup?
    init(group: EventLoopGroup? = nil) {
        self.group = group
    }
    
    deinit {
        try? self.group?.syncShutdownGracefully()
        self.group = nil
    }
    
    

    
    public func receiveMessage(_ text: String, metadata: Document, handle: P2PTransportFactoryHandle) async throws -> P2PTransportClient? {
        guard
            let host = metadata["ip"] as? String,
            let port = metadata["port"] as? Int
        else {
            throw IPv6TCPP2PError.socketCreationFailed
        }
        

         return try! await rtcClientBootstrap(handle: handle)
            .connectTimeout(.seconds(30))
            .connect(host: host, port: port)
            .flatMap({ channel in
                DatagramTransportClient.initialize(state: handle.state, channel: channel)
            }).get()
    }
    
    public func createConnection(handle: P2PTransportFactoryHandle) async throws -> P2PTransportClient? {
        return nil
    }
    
    
    //UDP Stuff
    private func rtcClientBootstrap(handle: P2PTransportFactoryHandle) async throws -> NIOTSDatagramBootstrap {
        let bootstrap: NIOTSDatagramBootstrap
#if canImport(Network)
        guard let group = group else {
            group = NIOTSEventLoopGroup()
            throw SwiftRTCErrors.nilGroup
        }
        bootstrap = NIOTSDatagramBootstrap(group: group)
#else
        guard let group = group else {
            group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
            throw SwiftRTCErrors.nilGroup
        }
        bootstrap = NIOTSDatagramBootstrap(group: group)
#endif
        return bootstrap
    }
}


@available(macOS 12, iOS 15, *)
final class DatagramTransportClient: P2PTransportClient {
    
    public var state: P2PFrameworkState
    public private(set) var connected = ConnectionState.connected
    private let channel: Channel
    public weak var delegate: P2PTransportClientDelegate?
    
    init(state: P2PFrameworkState, channel: Channel) {
        self.state = state
        self.channel = channel
    }
    
    func reconnect() async throws {
        
    }
    
    func disconnect() async {
        
    }
    
    func sendMessage(_ buffer: ByteBuffer) async throws {
        
    }
    
    static func initialize(state: P2PFrameworkState, channel: Channel) -> EventLoopFuture<DatagramTransportClient> {
        let client = DatagramTransportClient(state: state, channel: channel)
        return channel.pipeline.addHandler(BufferHandler(client: client)).map {
            client
        }
    }
}

@available(macOS 12, iOS 15, *)
private final class BufferHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    private weak var client: DatagramTransportClient?
    
    init(client: DatagramTransportClient) {
        self.client = client
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buffer = self.unwrapInboundIn(data)
        guard let client = client else {
            context.close(promise: nil)
            return
        }
        
        if let delegate = client.delegate {
            context.eventLoop.executeAsync {
                _ = try await delegate.p2pConnection(client, receivedMessage: buffer)
            }.whenFailure { error in
                context.fireErrorCaught(error)
            }
        }
    }
}

#endif
