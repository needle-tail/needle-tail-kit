//
//  NeedleTailPlugin.swift
//  
//
//  Created by Cole M on 4/15/22.
//
#if canImport(SwiftUI) && canImport(Combine) && (os(macOS) || os(iOS))
import Foundation
import MessagingHelpers
import CypherMessaging
import SwiftUI
import Combine

//Our Store for loading receiving messages in real time
public class NeedleTailPlugin: Plugin {
    
    public static let pluginIdentifier = "needletail"
    private var emitter: NeedleTailEmitter
    
    public init(emitter: NeedleTailEmitter) {
        self.emitter = emitter
    }
    
    public func onCreateChatMessage(_ messsage: AnyChatMessage) {
        NotificationCenter.default.post(name: .newChat, object: nil)
        emitter.messageReceived.send(messsage)
    }
    
    public func onCreateContact(_ contact: Contact, messenger: CypherMessenger) {
        emitter.contactAdded.send(contact)
    }
    
    public func onContactChange(_ contact: Contact) {
        emitter.contactChanged.send(contact)
    }
    
    @MainActor public func onRemoveContact(_ contact: Contact) {
//        emitter.contacts.removeAll { $0.id == contact.id }
        emitter.contactRemoved.send(contact)
        print(contact.username.raw, "removed...")
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
    public func onDeviceRegistery(_ deviceId: DeviceId, messenger: CypherMessenger) async throws {
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
#endif
