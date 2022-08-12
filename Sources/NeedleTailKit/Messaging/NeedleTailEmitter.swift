//
//  NeedleTailEmitter.swift
//  
//
//  Created by Cole M on 4/21/22.
//

import Foundation
import CypherMessaging
import NeedleTailHelpers

#if (os(macOS) || os(iOS))
extension NeedleTailEmitter: ObservableObject {}
#endif

public class NeedleTailEmitter: NeedleTailRepository, Equatable {
    
    public var id = UUID()
#if (os(macOS) || os(iOS))
    @Published public var messageReceived: AnyChatMessage?
    @Published public var contactChanged: Contact?
    @Published public var registered = false
    @Published public var contactAdded: Contact?
    @Published public var contactRemoved: Contact?
    @Published public var nicksOnline: [NeedleTailNick] = []
    @Published public var partMessage = ""
    @Published public var chatMessageChanged: AnyChatMessage?
    @Published public var needleTailNick: NeedleTailNick?
    @Published public var received: String?
    @Published public var qrCodeData: Data?
    @Published public var accountExists: String = ""
    @Published public var showScanner: Bool = false
    @Published public var state: TransportState.State = .clientOffline
#endif
//    public let onRekey = PassthroughSubject<Void, Never>()
//    public let savedChatMessages = PassthroughSubject<AnyChatMessage, Never>()
//    public let chatMessageRemoved = PassthroughSubject<AnyChatMessage, Never>()
//    public let conversationChanged = PassthroughSubject<TargetConversation.Resolved, Never>()
//    public let contactChanged = PassthroughSubject<Contact, Never>()
//    public let userDevicesChanged = PassthroughSubject<Void, Never>()
//    public let customConfigChanged = PassthroughSubject<Void, Never>()
//    public let p2pClientConnected = PassthroughSubject<P2PClient, Never>()
//    public let conversationAdded = PassthroughSubject<AnyConversation, Never>()
    
    public static func == (lhs: NeedleTailEmitter, rhs: NeedleTailEmitter) -> Bool {
        return lhs.id == rhs.id
    }
}
