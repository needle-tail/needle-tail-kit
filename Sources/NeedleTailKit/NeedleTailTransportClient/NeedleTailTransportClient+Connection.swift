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
    
    private func createBootstrap() async throws -> NIOClientTCPBootstrap {
        return try groupManager.makeBootstrap(hostname: clientInfo.hostname, useTLS: clientInfo.tls)
            .connectTimeout(.hours(1))
            .channelOption(ChannelOptions.socket(
                SocketOptionLevel(SOL_SOCKET),SO_REUSEADDR),
                value: 1
            )
            .channelInitializer { channel in
                return channel.pipeline
                    .addHandlers([
                        IRCChannelHandler(logger: self.logger),
                        NeedleTailInboundHandler(client: self)
                    ])
            }
    }
    
     func startClient() async throws {
        var channel: Channel?
        do {
            channel = try await createChannel(host: clientInfo.hostname, port: clientInfo.port)
            self.channel = channel
            self.userInfo = clientContext.userInfo
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
    
     func attemptConnection() async throws {
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
            try await startClient()
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
            await shutdownClient()
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
    
    func shutdownClient() async {
        do {
            _ = try await channel?.close(mode: .all).get()
            try await self.groupManager.shutdown()
            messageOfTheDay = ""
        } catch {
            print("Could not gracefully shutdown, Forcing the exit (\(error)")
            exit(0)
        }
        logger.info("disconnected from server")
    }
}
