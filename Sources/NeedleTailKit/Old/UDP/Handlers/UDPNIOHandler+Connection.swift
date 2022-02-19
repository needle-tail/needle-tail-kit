////
////  UDPNIOHandler+Connection.swift  
////
////  Created by Cole M on 10/9/21.
////
//
//import Foundation
//import NIOCore
//import NIOIRC
//
//extension UDPNIOHandler {
//    
//    
//    internal func connect(promise: EventLoopPromise<Channel>) -> EventLoopFuture<Channel> {
//        let future = try? _connect(host: options.host ?? "localhost", port: options.port)
//        future?.whenComplete { switch $0 {
//        case .success(let channel):
//            promise.succeed(channel)
//        case .failure(let error):
//            try? self.groupManager.syncShutdown()
//            promise.fail(error)
//        }
//        }
//        return promise.futureResult
//    }
//    
//    internal func _connect(host: String, port: Int) throws -> EventLoopFuture<Channel> {
//        
//        userMode = IRCUserMode()
////        state    = .connecting
//        retryInfo.attempt += 1
//        
//        return try clientBootstrap()
//            .connect(host: host, port: port)
////            .map { channel -> Channel in
////                self.retryInfo.registerSuccessfulConnect()
////                
////                guard case .connecting = self.state else {
////                    assertionFailure("called \(#function) but we are not connecting?")
////                    return channel
////                }
////                self.state = .registering(channel: channel,
////                                          nick:     self.options.host ?? "",
////                                          userInfo: self.options.userInfo)
////                self._register()
////                
////                return channel
////            }
//    }
//    
//    //Shutdown the program
//    public func disconnect() {
//        do {
//            try groupManager.syncShutdown()
//        } catch {
//            print("Could not gracefully shutdown, Forcing the exit (\(error)")
//            exit(0)
//        }
//        print("closed server")
//    }
//    
//    // MARK: - Connect
//    private func _register() {
////        assert(eventLoop.inEventLoop, "threading issue")
////        
////        guard case .registering(_, let nick, let user) = state else {
////            assertionFailure("called \(#function) but we are not connecting?")
////            return
////        }
////        
////        if let pwd = options.password {
////                        send(.otherCommand("PASS", [ pwd ]))
////        }
////        
////                send(.NICK(nick))
////                send(.USER(user))
//    }
//}
