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
        retryInfo.attempt += 1
        
        return try await createBootstrap()
            .connect(host: host, port: port).get()
    }
    
    @NeedleTailActor
    public func disconnect() async {
        await shutdownClient()
    }
    
    @NeedleTailActor
    private func createBootstrap() async throws -> NIOClientTCPBootstrap {
        let bootstrap: NIOClientTCPBootstrap
        guard let host = options.hostname else {
            throw IRCClientErrors.notImplemented
        }
        
        if !options.tls {
            bootstrap = try groupManager.makeBootstrap(hostname: host, useTLS: false)
        } else {
            bootstrap = try groupManager.makeBootstrap(hostname: host, useTLS: true)
        }
        return bootstrap
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
            channel = try await createChannel(host: options.hostname ?? "localhost", port: options.port)
            self.retryInfo.registerSuccessfulConnect()
           userState.transition(to: .registering(
                        channel: channel!,
                        nick: NeedleTailNick(deviceId: nil, nick: self.options.nickname),
                        userInfo: self.options.userInfo))
            
            self.nick?.nick = self.options.nickname
            self.channel = channel
            self.userInfo = self.options.userInfo
            
            await self.registerNeedletailSession(regPacket)
        } catch {
            await self.shutdownClient()
        }
        assert(channel != nil, "channel is nil")
    }
    
    // MARK: - Retry
#if false // TODO: finish Noze port
    private func retryConnectAfterFailure() {
        let retryHow : IRCRetryResult
        
        if let cb = options.retryStrategy {
            retryHow = cb(retryInfo)
        }
        else {
            if retryInfo.attempt < 10 {
                retryHow = .retryAfter(TimeInterval(retryInfo.attempt) * 0.200)
            }
            else {
                retryHow = .stop
            }
        }
        
        switch retryHow {
        case .retryAfter(let timeout):
            // TBD: special Retry status?
            if state != .connecting {
                state = .connecting
                group.scheduleTask(in: .milliseconds(timeout * 1000.0)) {
                    self.state = .disconnected
                    self.connect()
                }
            }
            
        case .error(let error):
            stop(error: error)
            
        case .stop:
            stop(error: NeedleTailError.ConnectionQuit)
        }
    }
#endif
    
    
    func handlerDidDisconnect(_ context: ChannelHandlerContext) async {
        switch userState.state {
        case .error:
            break
        case .quit:
            break
        case .registering, .connecting:
//            await clientDelegate?.clientFailedToRegister(self)
           userState.transition(to: .disconnect)
        default:
            userState.transition(to: .disconnect)
        }
    }
    
    func handlerCaughtError(_ error: Swift.Error,
                            in context: ChannelHandlerContext) {
        retryInfo.lastSocketError = error
//        state = .error(.channelError(error))
        
        
        print("IRCClient error:", error)
    }
}
