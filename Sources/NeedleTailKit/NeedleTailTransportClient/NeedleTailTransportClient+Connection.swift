//
//  NeedleTailTransportClient+Connection.swift
//  
//
//  Created by Cole M on 3/4/22.
//

import NIO
import AsyncIRC
import NeedleTailHelpers

enum IRCClientErrors: Error {
    case notImplemented
}

extension NeedleTailTransportClient {
    
    func createChannel(host: String, port: Int) async throws -> Channel {
        messageOfTheDay = ""
        userMode = IRCUserMode()
        return try await createBootstrap()
            .connect(host: host, port: port).get()
    }
    
     func disconnect() async {
        await shutdownClient()
    }
    
    private func createBootstrap() async throws -> NIOClientTCPBootstrap {
        return try groupManager.makeBootstrap(hostname: clientInfo.hostname, useTLS: clientInfo.tls)
            .connectTimeout(.hours(1))
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET),
                                                 SO_REUSEADDR), value: 1)
            .channelInitializer { channel in
                return channel.pipeline
                    .addHandlers([
                        IRCChannelHandler(logger: self.logger),
                        NeedleTailInboundHandler(client: self)
                    ])
            }
    }
    
     func startClient(_ regPacket: String?) async throws {
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
    
     func attemptConnection(_ regPacket: String? = nil) async throws {
        switch transportState.current {
        case .registering(channel: _, nick: _, userInfo: _):
            break
        case .registered(channel: _, nick: _, userInfo: _):
            break
        case .connecting:
            break
        case .online:
            break
        case .suspended, .offline:
            transportState.transition(to: .connecting)
            try await startClient(regPacket)
        case .disconnect:
            break
        case .error:
            break
        case .quit:
            break
        }
    }

     func attemptDisconnect(_ isSuspending: Bool) async {
        if isSuspending {
            transportState.transition(to: .suspended)
        }
        switch transportState.current {
        case .registering(channel: _, nick: _, userInfo: _):
            break
        case .registered(channel: _, nick: _, userInfo: _):
            break
        case .connecting:
            break
        case .online:
            await disconnect()
            authenticated = .unauthenticated
        case .suspended, .offline:
            return
        case .disconnect:
            break
        case .error:
            break
        case .quit:
            break
        }
    }
}