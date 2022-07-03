//
//  NeedleTailPlugin.swift
//  
//
//  Created by Cole M on 4/15/22.
//

import Foundation
import MessagingHelpers
import CypherMessaging
import NeedleTailHelpers

//Our Store for loading receiving messages in real time
public class NeedleTailPlugin: Plugin {
    
    public static let pluginIdentifier = "needletail"
    var emitter: NeedleTailEmitter
    
    public init(emitter: NeedleTailEmitter) {
        self.emitter = emitter
    }
    
    public func onCreateChatMessage(_ message: AnyChatMessage) {
        emitter.messageReceived = message
    }
    
    public func onCreateContact(_ contact: Contact, cypher: CypherMessenger) {
        emitter.contactAdded = contact
    }
    
    public func onContactChange(_ contact: Contact) {
        emitter.contactChanged = contact
    }
    
    @MainActor public func onRemoveContact(_ contact: Contact) {
//        emitter.contacts.removeAll { $0.id == contact.id }
        emitter.contactRemoved = contact
        print(contact.username.raw, "removed...")
    }
    
    @MainActor public func onMembersOnline(_ nick: [NeedleTailNick]) {
        emitter.nicksOnline = nick
    }
    
    @MainActor public func onPartMessage(_ message: String) {
        emitter.partMessage = message
    }
//    public func onRekey(
//        withUser username: Username,
//        deviceId: DeviceId,
//        messenger: CypherMessenger
//    ) async throws {
//        DispatchQueue.main.async {
//            emitter.onRekey.send()
//        }
//    }
//
    
//    public func onDeviceRegisteryRequest(_ config: UserDeviceConfig, messenger: CypherMessenger) async throws {
//
//    }
    public func onDeviceRegistery(_ deviceId: DeviceId, cypher: CypherMessenger) async throws {
        DispatchQueue.main.async {
//            emitter.userDevicesChanged.send()
        }
    }
//
//    public func onMessageChange(_ message: AnyChatMessage) {
//        DispatchQueue.main.async {
//            emitter.chatMessageChanged.send(message)
//        }
//    }
//
//    public func onConversationChange(_ viewModel: AnyConversation) {
//        Task.detached {
//            let viewModel = await viewModel.resolveTarget()
//            DispatchQueue.main.async {
//                emitter.conversationChanged.send(viewModel)
//            }
//        }
//    }
//
//    public func onContactChange(_ contact: Contact) {
//        emitter.contactChanged.send(contact)
//    }
//
//    public func onCreateContact(_ contact: Contact, messenger: CypherMessenger) {
//        emitter.contacts.append(contact)
//        emitter.contactAdded.send(contact)
//    }
//
//    public func onCreateConversation(_ viewModel: AnyConversation) {
//        emitter.conversationAdded.send(viewModel)
//    }
    
//    public func onRemoveContact(_ contact: Contact) {
//        self.emitter.contacts.removeAll { $0.id == contact.id }
//    }
//
//    public func onRemoveChatMessage(_ message: AnyChatMessage) {
//        self.emitter.chatMessageRemoved.send(message)
//    }
//
//    public func onP2PClientOpen(_ client: P2PClient, messenger: CypherMessenger) {
//        emitter.p2pClientConnected.send(client)
//    }
//
//    public func onCustomConfigChange() {
//        emitter.customConfigChanged.send()
//    }
    
}


extension PrivateChat: Hashable, Identifiable {
    public var id: ObjectIdentifier {
        ObjectIdentifier(conversation)
    }
    
    public static func == (lhs: PrivateChat, rhs: PrivateChat) -> Bool {
        lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher) {
        id.hash(into: &hasher)
    }
}

extension GroupChat: Hashable, Identifiable {
    public var id: ObjectIdentifier {
        ObjectIdentifier(conversation)
    }
    
    public static func == (lhs: GroupChat, rhs: GroupChat) -> Bool {
        lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher) {
        id.hash(into: &hasher)
    }
}

extension AnyChatMessage: Hashable, Identifiable {
    public var id: UUID {
        raw.id
    }
    
    public static func == (lhs: AnyChatMessage, rhs: AnyChatMessage) -> Bool {
        lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher) {
        id.hash(into: &hasher)
    }
}
