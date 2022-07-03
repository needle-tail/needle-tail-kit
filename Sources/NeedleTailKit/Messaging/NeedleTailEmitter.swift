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

public class NeedleTailEmitter: NeedleTailHandler {
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
    @Published public var received: AlertType = .none {
        didSet {
#if os(macOS)
            NeedleTail.shared.showRegistryRequestAlert()
#endif
        }
    }
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
}
