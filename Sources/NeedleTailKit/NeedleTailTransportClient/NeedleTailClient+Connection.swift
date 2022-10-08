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

@NeedleTailClientActor
extension NeedleTailClient {
    
    func attemptConnection() async throws {
        switch await transportState.current {
        case .clientOffline:
            await transportState.transition(to: .clientConnecting)
            try await startClient()
        default:
            break
        }
    }
    
    func startClient() async throws {
        do {
            self.channel = try await createChannel(host: clientInfo.hostname, port: clientInfo.port)
            self.userInfo = clientContext.userInfo
            await transportState.transition(to: .clientConnected)
        } catch {
            logger.error("Could not start client: \(error)")
            await transportState.transition(to: .clientOffline)
            try await attemptDisconnect(true)
            messenger.authenticated  = .unauthenticated
        }
    }
    
    func createChannel(host: String, port: Int) async throws -> Channel {
        userMode = IRCUserMode()
        return try await createBootstrap()
            .connect(host: host, port: port).get()
    }
    
    private func createBootstrap() async throws -> NIOClientTCPBootstrap {
        return try await groupManager.makeBootstrap(hostname: clientInfo.hostname, useTLS: clientInfo.tls)
            .connectTimeout(.minutes(1))
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET),SO_REUSEADDR), value: 1)
            .channelInitializer { channel in
                channel.eventLoop.executeAsync {
                    let transport = await self.createTransport(channel)
                    try await channel.pipeline.addHandlers([
                        IRCChannelHandler(logger: self.logger),
                        NeedleTailHandler(client: self, transport: transport)
                    ])
                }
            }
    }
    
    func createTransport(_ channel: Channel) async -> NeedleTailTransport {
        let transport = await NeedleTailTransport(
            cypher: self.cypher,
            messenger: self.messenger,
            channel: channel,
            userMode: self.userMode,
            transportState: self.transportState,
            signer: self.signer,
            clientContext: self.clientContext,
            clientInfo: self.clientInfo
        )
        self.transport = transport
        return transport
    }
    
    func attemptDisconnect(_ isSuspending: Bool) async throws {
        
        if isSuspending {
            await transportState.transition(to: .transportDeregistering)
        }
        
        switch await transportState.current {
        case .transportDeregistering:
            
            await transportState.transition(to: .transportOffline)
            messenger.authenticated = .unauthenticated
            
            guard let username = self.messenger.username else { return }
            guard let deviceId = self.messenger.deviceId else { return }
            try await transport?.sendQuit(username, deviceId: deviceId)
        default:
            break
        }
    }
    
}
