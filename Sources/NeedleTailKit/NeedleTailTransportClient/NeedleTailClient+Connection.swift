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

extension NeedleTailClient {
    
    func startClient() async throws {
       var channel: Channel?
       do {
           channel = try await createChannel(host: clientInfo.hostname, port: clientInfo.port)
           self.channel = channel
           self.userInfo = clientContext.userInfo
       } catch {
           logger.error("Could not start client: \(error)")
           transportState.transition(to: .offline)
           self.authenticated = .authenticationFailure
           await self.shutdownClient()
       }
       assert(channel != nil, "channel is nil")
   }
    
    func createChannel(host: String, port: Int) async throws -> Channel {
//        messageOfTheDay = ""
        userMode = IRCUserMode()
        return try await createBootstrap()
            .connect(host: host, port: port).get()
    }
    
    private func createBootstrap() async throws -> NIOClientTCPBootstrap {
        guard let group = self.eventLoop else { throw NeedleTailError.nilElG }
        
        self.transport = await NeedleTailTransport(
            cypher: cypher,
            messenger: messenger,
            channel: channel,
            userMode: userMode,
            transportState: transportState,
            signer: signer,
            authenticated: authenticated,
            clientContext: clientContext,
            clientInfo: clientInfo,
            transportDelegate: transportDelegate
        )
        guard let transport = transport else { throw NeedleTailError.transportNotIntitialized }
        return try await groupManager.makeBootstrap(hostname: clientInfo.hostname, useTLS: clientInfo.tls)
            .connectTimeout(.minutes(1))
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET),SO_REUSEADDR), value: 1)
            .channelInitializer { channel in
                let promise = group.next().makePromise(of: Void.self)
                promise.completeWithTask {
                    try await channel.pipeline.addHandlers([
                        IRCChannelHandler(logger: self.logger),
                        NeedleTailHandler(client: self, transport: transport)
                    ])
                }
                return promise.futureResult
            }
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
            return
        case .suspended, .offline:
            await shutdownClient()
            authenticated = .unauthenticated
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
            channel = nil
            eventLoop = nil
            cypher = nil
//            messageOfTheDay = ""
        } catch {
            print("Could not gracefully shutdown, Forcing the exit (\(error)")
            exit(0)
        }
        logger.info("disconnected from server")
    }
}