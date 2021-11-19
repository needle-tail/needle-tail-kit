//
//  File.swift
//  
//
//  Created by Cole M on 11/5/21.
//

import Foundation
import NIOIRC
import CypherProtocol
import CypherMessaging
import Crypto



public final class IRCConversation: Identifiable, Hashable, IRCConversationDelegate {
    public var id: UUID?
    internal var store: ConnectionKitIRCStore?
    internal let databaseEncryptionKey: SymmetricKey
    internal private(set) var service: IRCService
    public let model: DecryptedModel<IRCConversationModel>
    var recipient: IRCMessageRecipient?
    
    init(
        databaseEncryptionKey: SymmetricKey,
        model: DecryptedModel<IRCConversationModel>,
        service: IRCService
    ) {
        self.databaseEncryptionKey = databaseEncryptionKey
        self.model = model
        self.service = service
    }
    
    public static func == (lhs: IRCConversation, rhs: IRCConversation) -> Bool {
        return lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    // MARK: - Subscription Changes
    
    internal func userDidLeaveChannel() {
        // have some state reflecting that?
    }
    
    
    // MARK: - Connection Changes
    
    internal func serviceDidGoOffline() async {
        guard let last = model.timeline.last else { return }
        if case .disconnect = last.model.payload { return }
        
        let timeline = TimelineEntryModel.SecureProps(date: Date(), payload: .disconnect, metadata: [:])
        try? await self.store?.createTimeline(TimelineEntryModel(props: timeline, encryptionKey: self.databaseEncryptionKey))
        
//        model.timeline.append(TimelineEntryModel.SecureProps(date: Date(), payload: .disconnect, metadata: [:]))
    }
    internal func serviceDidGoOnline() async {
        guard let last = model.timeline.last else { return }
        
        switch last.model.payload {
        case .reconnect, .message, .notice, .ownMessage:
            return
        case .disconnect:
            break
        }
        let timeline = TimelineEntryModel.SecureProps(date: Date(), payload: .reconnect, metadata: [:])
        try? await self.store?.createTimeline(TimelineEntryModel(props: timeline, encryptionKey: self.databaseEncryptionKey))
//        model.timeline.append(.init(date: Date(), payload: .reconnect))
    }
    
    
    // MARK: - Sending Messages
    
    @discardableResult
    public func sendMessage(_ message: String) async -> Bool {
        guard let recipient = model.recipient else { return false }
        guard service.sendMessage(message, to: recipient) else { return false }
        let timeline = TimelineEntryModel.SecureProps(payload: .ownMessage(message), metadata: [:])
        try? await self.store?.createTimeline(TimelineEntryModel(props: timeline, encryptionKey: self.databaseEncryptionKey))
//        model.timeline.append(.init(payload: .ownMessage(message)))
        return true
    }
    
    
    // MARK: - Receiving Messages
    
    public func addMessage(_ message: String, from sender: IRCUserID) async {
        let timeline = TimelineEntryModel.SecureProps(date: Date(), payload: .message(message, sender), metadata: [:])
        try? await self.store?.createTimeline(TimelineEntryModel(props: timeline, encryptionKey: self.databaseEncryptionKey))
//        model.timeline.append(.init(payload: .message(message, sender)))
    }
    public func addNotice(_ message: String) async {
        let timeline = TimelineEntryModel.SecureProps(date: Date(), payload: .notice(message), metadata: [:])
        try? await self.store?.createTimeline(TimelineEntryModel(props: timeline, encryptionKey: self.databaseEncryptionKey))
//        model.timeline.append(.init(payload: .notice(message)))
    }
}
