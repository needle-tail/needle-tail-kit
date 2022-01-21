////
////  VideoSession.swift
////  
////
////  Created by Cole M on 10/9/21.
////
//
//import Foundation
//import NIOIRC
//
//public final class VideoSession: Identifiable {
//    
//    internal enum SessionType: Equatable {
//        case groupSession
//        case privateSession
//    }
//    
//    internal var sessionType                        : SessionType
////    internal private(set) weak var serviceDelegate  : VideoKit?
//    internal var name                               : String
//    public var id                                   : String  { return name }
////    private var timeline = [ TimelineEntry ]()
//    
//    
//    init(
////        serviceDelegate: VideoKit,
//        groupSessionName: IRCChannelName
//    ) {
//        self.sessionType = .groupSession
//        self.name = groupSessionName.stringValue
//        self.serviceDelegate = serviceDelegate
//    }
//    
//    init?(
////        serviceDelegate: VideoKit,
//        nickname: String
//    ) {
//        self.sessionType = .privateSession
//        self.name = nickname
//        self.serviceDelegate = serviceDelegate
//    }
//    
//    convenience init?(serviceDelegate: VideoKit, groupSessionName: String) {
//        guard let name = IRCChannelName(groupSessionName) else { return nil }
//        self.init(serviceDelegate: serviceDelegate, groupSessionName: name)
//    }
//    
//    // MARK: - Subscription Changes
//    
//    internal func userDidLeaveChannel() {
//      // have some state reflecting that?
//    }
//    
//    
//    internal var session: IRCMessageRecipient? {
//        switch sessionType {
//        case .groupSession:
//            guard let name = IRCChannelName(name) else { return nil }
//            return .channel(name)
//        case .privateSession:
//            guard let name = IRCNickName(name) else { return nil }
//            return  .nickname(name)
//        }
//    }
//    
//    // MARK: - Connection Changes
//    
//    internal func serviceDidGoOffline() {
////      guard let last = timeline.last else { return }
////      if case .disconnect = last.payload { return }
////
////      timeline.append(.init(date: Date(), payload: .disconnect))
//    }
//    internal func serviceDidGoOnline() {
////      guard let last = timeline.last else { return }
////
////      switch last.payload {
////        case .reconnect, .message, .notice, .ownMessage:
////          return
////        case .disconnect:
////          break
////      }
////
////      timeline.append(.init(date: Date(), payload: .reconnect))
//    }
//}
//
//extension VideoSession: CustomStringConvertible {
//  public var description: String { "<Session: \(sessionType) \(name)>" }
//}
