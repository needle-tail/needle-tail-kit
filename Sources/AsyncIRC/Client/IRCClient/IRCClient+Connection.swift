//
//  IRCClient+Connection.swift
//  
//
//  Created by Cole M on 3/4/22.
//

import NIO
import NeedleTailHelpers

enum IRCClientErrors: Error {
    case notImplemented
}

extension IRCClient {
    
    @NeedleTailActor
    internal func createChannel(host: String, port: Int) async throws -> Channel {
        messageOfTheDay = ""
        userMode = IRCUserMode()
        return try await createBootstrap()
            .connect(host: host, port: port).get()
    }
    
    @NeedleTailActor
    public func disconnect() async {
        await shutdownClient()
    }
    
    @NeedleTailActor
    private func createBootstrap() async throws -> NIOClientTCPBootstrap {
        return try groupManager.makeBootstrap(hostname: clientInfo.hostname, useTLS: clientInfo.tls)
            .connectTimeout(.hours(1))
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET),
                                                 SO_REUSEADDR), value: 1)
            .channelInitializer { channel in
                return channel.pipeline
                    .addHandlers([
                        IRCChannelHandler(logger: self.logger),
                        Handler(client: self)
                    ])
            }
    }
    
    @NeedleTailActor
    public func startClient(_ regPacket: String?) async throws {
        var channel: Channel?
        do {
            channel = try await createChannel(host: clientInfo.hostname, port: clientInfo.port)
           transportState.transition(to: .registering(
                        channel: channel!,
                        nick: clientContext.nickname,
                        userInfo: clientContext.userInfo))
            
            self.channel = channel
            self.userInfo = clientContext.userInfo
            await self.registerNeedletailSession(regPacket)
        } catch {
            await self.shutdownClient()
        }
        assert(channel != nil, "channel is nil")
    }
    
    
    
    func handlerDidDisconnect(_ context: ChannelHandlerContext) async {
        switch transportState.current {
        case .error:
            break
        case .quit:
            break
        case .registering, .connecting:
//            await clientDelegate?.clientFailedToRegister(self)
           transportState.transition(to: .disconnect)
        default:
            transportState.transition(to: .disconnect)
        }
    }
    
    func handlerCaughtError(_ error: Swift.Error,
                            in context: ChannelHandlerContext) {
        print("IRCClient error:", error)
    }
}
