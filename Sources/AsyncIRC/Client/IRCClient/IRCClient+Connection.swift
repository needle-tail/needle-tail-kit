//
//  File.swift
//  
//
//  Created by Cole M on 3/4/22.
//

import NIO


extension IRCClient {

    internal func _connect(host: String, port: Int) async throws -> Channel {
        messageOfTheDay = ""
        userMode = IRCUserMode()
        state    = .connecting
        retryInfo.attempt += 1
        
        return try await clientBootstrap()
            .connect(host: host, port: port).get()
    }
    
    //Shutdown the program
    public func disconnect() async {
        await close()
    }
    
    private func clientBootstrap() async throws -> NIOClientTCPBootstrap {
        let bootstrap: NIOClientTCPBootstrap
        guard let host = options.hostname else {
            throw Error.notImplemented
        }

        if !options.tls {
            bootstrap = try groupManager.makeBootstrap(hostname: host, useTLS: false)
        } else {
            bootstrap = try groupManager.makeBootstrap(hostname: host, useTLS: true)
        }
        let store = self.store
        return bootstrap
            .connectTimeout(.hours(1))
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET),
                                                 SO_REUSEADDR), value: 1)
            .channelInitializer { channel in
                return channel.pipeline
                    .addHandlers([
//                        ByteToMessageHandler(LineBasedFrameDecoder()),
                        IRCChannelHandler(logger: self.logger, needleTailStore: store),
                        Handler(client: self)
                    ])
            }
    }
    
    
    public func connecting(_ regPacket: String?) async throws -> Channel? {
        var channel: Channel?
        do {
            channel = try await _connect(host: options.hostname ?? "localhost", port: options.port)
            await self.retryInfo.registerSuccessfulConnect()
            guard case .connecting = self.state else {
                assertionFailure("called \(#function) but we are not connecting?")
                return channel
            }
            self.state = .registering(channel: channel!,
                                      nick:     self.options.nickname,
                                      userInfo: self.options.userInfo)
            await self._register(regPacket)
        } catch {
            await self.close()
        }
        assert(channel != nil, "channel is nil")
        return channel
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
            stop(error: IRCClientError.ConnectionQuit)
        }
    }
#endif
    
    
    func handlerDidDisconnect(_ context: ChannelHandlerContext) async {
        switch state {
        case .error:
            break
        case .quit:
            break
        case .registering, .connecting:
            await  delegate?.clientFailedToRegister(self)
            state = .disconnected
        default:
            state = .disconnected
        }
    }
    
    func handlerCaughtError(_ error: Swift.Error,
                            in context: ChannelHandlerContext) {
        retryInfo.lastSocketError = error
        state = .error(.channelError(error))
        
        print("IRCClient error:", error)
    }
}
