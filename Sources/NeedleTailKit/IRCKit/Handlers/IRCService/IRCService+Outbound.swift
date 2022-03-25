//
//  IRCService.swift
//  
//
//  Created by Cole M on 3/4/22.
//

import Foundation
import CypherMessaging
import AsyncIRC

//MARK: - Outbound
extension IRCService {
    
    //TODO: Handle ACK
    internal func publishKeyBundle(_ keyBundle: String) async {
        await client?.publishKeyBundle(keyBundle)
    }
    
    internal func readKeyBundle(_ packet: String) async -> UserConfig? {
        await client?.readKeyBundle(packet)
        var config: UserConfig?
        repeat {
            config = try? await self.stream?.next()
        } while config == nil
        return config
    }
    
    //TODO: Handle ACK
    internal func registerAPN(_ packet: String) async {
        await client?.registerAPN(packet)
    }
    
    //MARK: - CypherMessageAPI
    public func registerPrivateChat(_ name: String) async throws -> DecryptedModel<ConversationModel>? {
        let id = name.lowercased()
        let conversation = self.conversations?.first { $0.id.uuidString == id }
        if let c = conversation { return c }
        let chat = try? await self.messenger?.createPrivateChat(with: Username(name))
        return chat?.conversation
    }
    
    public func registerGroupChat(_ name: String) async throws -> DecryptedModel<ConversationModel>? {
        let id = name.lowercased()
        let conversation = self.conversations?.first { $0.id.uuidString == id }
        if let c = conversation { return c }
        let chat = try? await self.messenger?.createGroupChat(with: [])
        return chat?.conversation
    }
    
    public func conversationWithID(_ id: UUID) async -> DecryptedModel<ConversationModel>? {
        return try? await self.messenger?.getConversation(byId: id)?.conversation
    }
    
    public func conversationForRecipient(_ recipient: IRCMessageRecipient, create: Bool = false) async -> GroupChat? {
        return try? await self.messenger?.getGroupChat(byId: GroupChatId(recipient.stringValue))
    }
    
    public func sendMessage(_ message: Data, to recipient: IRCMessageRecipient, tags: [IRCTags]?) async throws -> Bool {
        //        guard case .online = userState.state else { return false }
        await client?.sendMessage(message.base64EncodedString(), to: recipient, tags: tags)
        return true
    }
}
