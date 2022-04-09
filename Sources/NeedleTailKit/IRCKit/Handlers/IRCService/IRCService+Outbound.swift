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
    
    
    internal func publishKeyBundle(_ keyBundle: String) async {
        await client?.publishKeyBundle(keyBundle)
    }
    
    
    //TODO: - we need to suspend the read if it fails and wait until we get a userConfig back from the server, otherwise we will just indefinietly loop through the method because we will never receive the server event.
    
    //I think we need a central place that manages KeyBundleState...
    @OutboundActor
    internal func readKeyBundle(_ packet: String) async -> UserConfig? {
        await client?.readKeyBundle(packet)
        repeat {
            userConfig = try? await self.stream?.next()
//            try? await Task.sleep(nanoseconds: 10_000_000_000)
//            waitCount += 1
        } while await shouldRunCount()
        
        return userConfig
    }
    
//    internal func readBundle(from packet: String, returning: @escaping (UserConfig) async throws -> UserConfig?) async {
//        await client?.readKeyBundle(packet)
//        repeat {
//            userConfig = try? await self.stream?.next()
//        } while userConfig == nil
//
//        try? await returning(userConfig!)
//    }
    @OutboundActor
    internal func readBundle(from packet: String, returning: @escaping (UserConfig?) async throws -> UserConfig) async throws -> UserConfig? {
//        repeat {
                userConfig = try? await self.stream?.next()
//        } while await shouldRunCount()

        return try await returning(userConfig)
    }
    
    func fireAnotherFunctionToWait() {
        
    }
    
    private func shouldRunCount() async -> Bool {
        guard stream?.bundle == nil else {
            return false
        }
//        guard waitCount <= 100 else {
//            return false
//        }
        return true
    }
    
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
        print(message.base64EncodedString())
        await client?.sendMessage(message.base64EncodedString(), to: recipient, tags: tags)
        return true
    }
}
