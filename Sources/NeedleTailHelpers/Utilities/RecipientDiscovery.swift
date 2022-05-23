//
//  File.swift
//  
//
////  Created by Cole M on 5/15/22.
////
//
//import Foundation
//
//class RecipientDiscovery {
//public var type : ConversationType = .im
//public class func recipient(name: String) async throws -> IRCMessageRecipient {
//    switch type {
//    case .channel:
//        guard let name = IRCChannelName(name) else { throw NeedleTailError.nilChannelName }
//        return .channel(name)
//    case .im:
//        print(name)
//        guard let validatedName = NeedleTailNick(name) else { throw NeedleTailError.nilNickName }
//        return .nickname(validatedName)
//    }
//}
//}
