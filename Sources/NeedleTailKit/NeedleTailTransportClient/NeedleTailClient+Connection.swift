//
//  NeedleTailTransportClient+Connection.swift
//  
//
//  Created by Cole M on 3/4/22.
//

import NIO
import NeedleTailProtocol
import NeedleTailHelpers
import BSON

enum IRCClientErrors: Error {
    case notImplemented
}

extension NeedleTailClient {
    
    func startClient() async throws {
       var channel: Channel?
       do {
           channel = try await createChannel(host: clientInfo.hostname, port: clientInfo.port)
           self.channel = channel
           self.transport?.channel = channel
           self.userInfo = clientContext.userInfo
           transportState.transition(to: .clientConnected)
       } catch {
           logger.error("Could not start client: \(error)")
           transportState.transition(to: .clientOffline)
           await self.shutdownClient()
           messenger.authenticated  = .authenticated
       }
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
    
//    func handlerDidDisconnect(_ context: ChannelHandlerContext) async {
//        switch transportState.current {
//        case .error:
//            break
//        case .quit:
//            break
//        case .registering, .connecting:
//           transportState.transition(to: .disconnect)
//        default:
//            transportState.transition(to: .disconnect)
//        }
//    }
    
    func attemptConnection() async throws {
        switch transportState.current {
        case .clientOffline:
            transportState.transition(to: .clientConnecting)
            try await startClient()
        default:
            break
        }
    }

     func attemptDisconnect(_ isSuspending: Bool) async {
        if isSuspending {
            transportState.transition(to: .transportDeregistering)
        }
         switch transportState.current {
         case .transportDeregistering:
             transportState.transition(to: .clientOffline)
             messenger.authenticated = .unauthenticated
            await shutdownClient()
         default:
             break
         }
    }
    
    //We must make sure shutdown client is called before the NeedleTailClient is deinitialized
    func shutdownClient() async {
        do {
            guard let username = self.messenger.username else { return }
            guard let deviceId = self.messenger.deviceId else { return }
            try await transport?.sendQuit(username, deviceId: deviceId)
           _ = try await channel?.close(mode: .all).get()
            try await self.groupManager.shutdown()
        } catch {
            print("Could not gracefully shutdown, Forcing the exit (\(error)")
            exit(0)
        }
        logger.info("disconnected from server")
        messenger.isConnected = false
    }
}
