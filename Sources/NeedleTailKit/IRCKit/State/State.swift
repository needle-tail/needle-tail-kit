////
////  File.swift
////  
////
////  Created by Cole M on 9/19/21.
////
//
//import Foundation
//import NIOIRC
//import NIO
//
//internal enum IRCState : CustomStringConvertible {
//    case disconnected
//    case connecting
//    case registering(channel: Channel, nick: IRCNickName, userInfo: IRCUserInfo)
//    case registered (channel: Channel, nick: IRCNickName, userInfo: IRCUserInfo)
//    case error      (IRCClientError)
//    case requestedQuit
//    case quit
//    
//    var isRegistered : Bool {
//        switch self {
//        case .registered: return true
//        default:          return false
//        }
//    }
//    
//    var nick : IRCNickName? {
//        @inline(__always) get {
//            switch self {
//            case .registering(_, let v, _): return v
//            case .registered (_, let v, _): return v
//            default: return nil
//            }
//        }
//    }
//    
//    var userInfo : IRCUserInfo? {
//        @inline(__always) get {
//            switch self {
//            case .registering(_, _, let v): return v
//            case .registered (_, _, let v): return v
//            default: return nil
//            }
//        }
//    }
//    
//    var channel : Channel? {
//        @inline(__always) get {
//            switch self {
//            case .registering(let channel, _, _): return channel
//            case .registered (let channel, _, _): return channel
//            default: return nil
//            }
//        }
//    }
//    
//    var canStartConnection : Bool {
//        switch self {
//        case .disconnected, .error: return true
//        case .connecting:           return false
//        case .registering:          return false
//        case .registered:           return false
//        case .requestedQuit, .quit: return false
//        }
//    }
//    
//    var description : String {
//        switch self {
//        case .disconnected:                return "disconnected"
//        case .connecting:                  return "connecting..."
//        case .registering(_, let nick, _): return "registering<\(nick)>..."
//        case .registered (_, let nick, _): return "registered<\(nick)>"
//        case .error      (let error):      return "error<\(error)>"
//        case .requestedQuit:               return "quitting..."
//        case .quit:                        return "quit"
//        }
//    }
//}
