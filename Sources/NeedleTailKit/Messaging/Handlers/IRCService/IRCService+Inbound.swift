////
////  IRCService+Inbound.swift
////  
////
////  Created by Cole M on 3/4/22.
////
//
//import Foundation
//import CypherMessaging
//import BSON
//import AsyncIRC
//import NeedleTailHelpers
//
////MARK: - Inbound
//extension IRCService {
//    
//    
//    // MARK: - IRCMessages
//    
//    /// This method is used to get extra information from server activity.
//    /// - Parameters:
//    ///   - client: Our ``IRCClient``
//    ///   - info: An array of string info sent back from the server
//    public func client(_ client: IRCClient, info: [String]) async throws {
//    // TODO: Handle Misc. Info
//    }
//    
//    /// **NOTICE**
//    public func client(_       client: IRCClient,
//                       notice message: String,
//                       for recipients: [ IRCMessageRecipient ]
//    ) async {
////        await self.updateConnectedClientState(client)
//
//        // FIXME: this is not quite right, mirror what we do in message
//        //        self.conversationsForRecipients(recipients).forEach {
//        //          $0.addNotice(message)
//        //        }
//    }
//    
//    
////    ???
//    public func client(_ client: IRCClient, received message: IRCMessage) async { }
//
//
//
//    public func client(_ client: IRCClient, messageOfTheDay message: String) async {
////        await self.updateConnectedClientState(client)
//        //        self.messageOfTheDay = message
//    }
//
//
//    // MARK: - Channels
//    public func client(_ client: IRCClient,
//                       user: IRCUserID,
//                       joined channels: [ IRCChannelName ]
//    ) async {
////        await self.updateConnectedClientState(client)
////                channels.forEach { self.registerChannel($0.stringValue) }
//    }
//    
//    
//    public func client(_ client: IRCClient,
//                       user: IRCUserID,
//                       left channels: [ IRCChannelName ],
//                       with message: String?
//    ) async {
////        await self.updateConnectedClientState(client)
//        //        channels.forEach { self.unregisterChannel($0.stringValue) }
//    }
//    
//    
//    public func client(_ client: IRCClient,
//                       changeTopic welcome: String,
//                       of channel: IRCChannelName
//    ) async {
////        await self.updateConnectedClientState(client)
//        // TODO: operation
//    }
//    
////    @NeedleTailActor
////    private func updateConnectedClientState(_ client: IRCClient) async {
////        switch self.transportState.current {
////        case .suspended:
////            assertionFailure("not connecting, still getting connected client info")
////            return
////        case .offline:
////            assertionFailure("not connecting, still getting connected client info")
////            return
////        case .connecting, .registered(channel: let channel, nick: let nick, userInfo: let user):
////            print("going online:", client)
////            userState.transition(to: .online)
////            let channels = await ["#NIO", "Swift"].asyncCompactMap(IRCChannelName.init)
////            await client.sendAndFlushMessage(.init(command: .JOIN(channels: channels, keys: nil)), chatDoc: nil)
////        case .online:
////            break
////        default:
////            break
////        }
////    }
//    
//    // MARK: - Connection
////
//    @NeedleTailActor
//    public func client(_
//                       client: IRCClient,
//                       registered nick: NeedleTailNick,
//                       with userInfo: IRCUserInfo
//    ) async {
////        await self.updateConnectedClientState(client)
//    }
//    
//
//    public func client(_ client: IRCClient, changedNickTo nick: NeedleTailNick) async {
////        await self.updateConnectedClientState(client)
//    }
//
//
//    public func client(_ client: IRCClient, changedUserModeTo mode: IRCUserMode) async {
////        await self.updateConnectedClientState(client)
//    }
////
//    
//    public func clientFailedToRegister(_ newClient: IRCClient) async {
//        switch self.transportState.current {
//        case .suspended, .offline:
//            assertionFailure("not connecting, still get registration failure")
//            return
//        case .connecting, .online:
//            print("Closing client ...")
////            client?.clientDelegate = nil
//            userState.transition(to: .offline)
//            await client?.disconnect()
//        default:
//            break
//        }
//    }
//    
//    
//    public func client(_ client: IRCClient, quit: String?) async {
//        print("QUITING")
//    }
//}
