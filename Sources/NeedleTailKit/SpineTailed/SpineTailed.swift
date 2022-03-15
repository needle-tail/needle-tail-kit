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
#endif


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

enum SpineTailedErrors: Error {
    case reconnectionFailed, socketCreationFailed, timeout
}

public class SpineTailed: P2PTransportClientFactory {
    public weak var delegate: P2PTransportFactoryDelegate?
    
    // We want to set up a P2P connection. Sending the needed information about each client. When a user recieves an offer they send the answer and once an agreement is made we can send our UDP Data P2P.
    public let transportLayerIdentifier: String = "_udp"
    var group: EventLoopGroup
    var eventLoop: EventLoop
    let stun: StunConfig?
    
    public init(stun: StunConfig? = nil) {
#if canImport(Network)
        group = NIOTSEventLoopGroup()
#else
        group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
#endif
        self.stun = stun
        self.eventLoop = group.next()
    }
    
    deinit {
        try? self.group.syncShutdownGracefully()
    }
    
    private func findAddress() async throws -> SocketAddress {
        if let stun = stun {
            do {
                let stunClient = try await StunClient.connect(to: stun.server)
                return try await stunClient.requestBinding(addressFamily: .ipv6)
            } catch {
                //Route Via Server
            }
        }
        
    findInterface: do {
        let interfaces = try System.enumerateDevices()
        
        for interface in interfaces {
            if
                let address = interface.address,
                address.protocol == .inet6,
                let foundIpAddress = address.ipAddress,
                !foundIpAddress.hasPrefix("fe80"),
                !foundIpAddress.contains("::1")
            {
                return try SocketAddress(ipAddress: foundIpAddress, port: 0)
            }
        }
        throw SpineTailedErrors.socketCreationFailed
    } catch {
        print("Failed to create P2PIPv6 Session", error)
        throw error
    }
    }
    
    
    public func receiveMessage(_ text: String, metadata: Document, handle: P2PTransportFactoryHandle) async throws -> P2PTransportClient? {
        guard
            let host = metadata["ip"] as? String,
            let port = metadata["port"] as? Int
        else {
            throw SpineTailedErrors.socketCreationFailed
        }
        
#if canImport(Network)
        return try await NIOTSDatagramBootstrap(group: group)
            .connectTimeout(.seconds(30))
            .connect(host: host, port: port)
            .flatMap({ channel in
                DatagramTransportClient.initialize(state: handle.state, channel: channel)
            }).get()
#else
        return try await DatagramBootstrap(group: group)
            .bind(host: host, port: port)
            .flatMap({ channel in
                DatagramTransportClient.initialize(state: handle.state, channel: channel)
            }).get()
#endif
    }
    
    
    
    
    public func createConnection(handle: P2PTransportFactoryHandle) async throws -> P2PTransportClient? {
        let address = try await findAddress()
        let promise = eventLoop.makePromise(of: Optional<P2PTransportClient>.self)
        
        ServerBootstrap(group: group)
            .childChannelInitializer { channel in
                return DatagramTransportClient.initialize(
                    state: handle.state,
                    channel: channel
                ).map { client in
                    promise.succeed(client)
                }.flatMapErrorThrowing { error in
                    promise.fail(error)
                    throw error
                }
            }
            .bind(to: address)
            .flatMap { channel -> EventLoopFuture<Void> in
                self.eventLoop.scheduleTask(in: .seconds(30), {
                    promise.fail(SpineTailedErrors.timeout)
                    channel.close(promise: nil)
                })
                
                
                guard
                    let localAddress = channel.localAddress,
                    let port = localAddress.port
                else {
                    promise.fail(SpineTailedErrors.socketCreationFailed)
                    return self.eventLoop.makeFailedFuture(SpineTailedErrors.socketCreationFailed)
                }
                
                return channel.eventLoop.executeAsync {
                    try await handle.sendMessage("", metadata: [
                        "ip": address.ipAddress,
                        "port": port
                    ])
                }
            }.whenFailure { error in
                promise.fail(error)
            }
        return try await promise.futureResult.get()
    }
    
    
    //UDP Stuff
#if canImport(Network)
    private func spinedTailClientBootstrap(handle: P2PTransportFactoryHandle) async throws -> NIOTSDatagramBootstrap {
        let bootstrap: NIOTSDatagramBootstrap
        group = NIOTSEventLoopGroup()
        bootstrap = NIOTSDatagramBootstrap(group: group)
        return bootstrap
    }
#else
    private func spinedTailClientBootstrap(handle: P2PTransportFactoryHandle) async throws -> DatagramBootstrap {
        let bootstrap: DatagramBootstrap
        group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        bootstrap = DatagramBootstrap(group: group)
        return bootstrap
    }
#endif
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
        throw SpineTailedErrors.reconnectionFailed
    }
    
    func disconnect() async {
        do {
            try await channel.close()
        } catch {}
    }
    
    func sendMessage(_ buffer: ByteBuffer) async throws {
        try await channel.writeAndFlush(buffer)
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

public struct StunCredentials {
    enum _Credentials {
        case none
        case password(String)
        case tuple(username: String, realm: String, password: String)
    }
    
    let _credentials: _Credentials
    
    public init() {
        _credentials = .none
    }
    
    public init(password: String) {
        _credentials = .password(password)
    }
    
    public init(username: String, realm: String, password: String) {
        _credentials = .tuple(username: username, realm: realm, password: password)
    }
}

public struct StunConfig {
    let server: SocketAddress
    let credentials: StunCredentials?
    
    public init(
        server: SocketAddress,
        credentials: StunCredentials = StunCredentials()
    ) {
        self.server = server
        self.credentials = credentials
    }
}
