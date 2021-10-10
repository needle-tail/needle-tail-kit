//
//  File.swift
//  
//
//  Created by Cole M on 10/9/21.
//

import Foundation
import NIOCore
import NIOIRC

extension NIOHandler {
    
    
    internal func connect(promise: EventLoopPromise<Channel>) -> EventLoopFuture<Channel> {
//        guard eventLoop.inEventLoop else { return eventLoop.execute(self.connect) }
        
//        guard state.canStartConnection else { return }
        
        
        _ = try? _connect(host: options.host ?? "localhost", port: options.port)
            .map { c in
                promise.succeed(c)
            }
            .whenFailure({ error in
                promise.fail(error)
            })
        
        return promise.futureResult
    }
    
    internal func _connect(host: String, port: Int) throws -> EventLoopFuture<Channel> {
        assert(eventLoop.inEventLoop,    "threading issue")
        assert(state.canStartConnection, "cannot start connection!")
        
        userMode = IRCUserMode()
        state    = .connecting
        retryInfo.attempt += 1
        
        return try clientBootstrap()
            .connect(host: host, port: port)
            .map { channel -> Channel in
                              self.retryInfo.registerSuccessfulConnect()
              
                              guard case .connecting = self.state else {
                                  assertionFailure("called \(#function) but we are not connecting?")
                                  return channel
                              }
                              self.state = .registering(channel: channel,
                                                        nick:     self.options.host ?? "",
                                                        userInfo: self.options.userInfo)
                              self._register()
                
                              return channel
            }
    }
    
    //Shutdown the program
    public func disconnect() {
        do {
//            try groupManager.syncShutdown()
        } catch {
            print("Could not gracefully shutdown, Forcing the exit (\(error)")
            exit(0)
        }
        print("closed server")
    }
    
    // MARK: - Connect
    private func _register() {
        assert(eventLoop.inEventLoop, "threading issue")
        
        guard case .registering(_, let nick, let user) = state else {
            assertionFailure("called \(#function) but we are not connecting?")
            return
        }
        
        if let pwd = options.password {
//            send(.otherCommand("PASS", [ pwd ]))
        }
        
//        send(.NICK(nick))
//        send(.USER(user))
    }
}
