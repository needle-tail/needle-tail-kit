//
//  NeedleTailEmitter.swift
//  
//
//  Created by Cole M on 4/21/22.
//

import Foundation
import CypherMessaging
import Combine

public class NeedleTailEmitter: NeedleTailHandler, ObservableObject {
    public var id = UUID()
    public let messageReceived = PassthroughSubject<AnyChatMessage, Never>()
    public let contactChanged = PassthroughSubject<Contact, Never>()
    public let registered = PassthroughSubject<Bool, Never>()
    public let contactAdded = PassthroughSubject<Contact, Never>()
    public let contactRemoved = PassthroughSubject<Contact, Never>()
    
    
//    public let onRekey = PassthroughSubject<Void, Never>()
//    public let savedChatMessages = PassthroughSubject<AnyChatMessage, Never>()
    
    public let chatMessageChanged = PassthroughSubject<AnyChatMessage, Never>()
//    public let chatMessageRemoved = PassthroughSubject<AnyChatMessage, Never>()
//    public let conversationChanged = PassthroughSubject<TargetConversation.Resolved, Never>()
//    public let contactChanged = PassthroughSubject<Contact, Never>()
//    public let userDevicesChanged = PassthroughSubject<Void, Never>()
//    public let customConfigChanged = PassthroughSubject<Void, Never>()
//
//    public let p2pClientConnected = PassthroughSubject<P2PClient, Never>()
    
   
//    public let conversationAdded = PassthroughSubject<AnyConversation, Never>()
}
