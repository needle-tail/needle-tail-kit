//
//  NeedleTailPlugin.swift
//
//
//  Created by Cole M on 4/15/22.
//

import MessagingHelpers
import CypherMessaging
import NeedleTailHelpers
import AsyncAlgorithms
import SwiftDTF
#if os(iOS)
import UIKit
#elseif os(macOS)
import Cocoa
#endif

#if os(iOS) || os(macOS)
//Our Store for loading receiving messages in real time(TOP LEVEL)
public final class NeedleTailPlugin: Plugin, Sendable {
    
    public static let pluginIdentifier = "@/needletail"
    
    let messenger: NeedleTailMessenger
    let priorityActor = PriorityActor()
    public init(messenger: NeedleTailMessenger) {
        self.messenger = messenger
    }
    
    @MainActor
    public func onCreateChatMessage(_ message: AnyChatMessage) {
        
#if os(iOS)
        //        UIApplication.shared.applicationIconBadgeNumber += 1
#elseif os(macOS)
#endif
        
#if (os(macOS) || os(iOS))
        print("CREATED MESSAGE", message.text)
        self.messenger.emitter.messageReceived = message
        Task {
            await priorityActor.queueThrowingAction(with: .background) { [weak self] in
                guard let self else { return }
                try await updateDeliveryStatus(message: message)
            }
            if let stream = await self.messenger.cypherTransport?.configuration.client?.stream {
                for try await result in NeedleTailAsyncSequence(consumer: stream.multipartMessageConsumer) {
                    switch result {
                    case .success(let filePacket):
                        if let cypher = await self.messenger.cypher, let message = try await self.messenger.findMessage(from: filePacket.mediaId, cypher: cypher) {
                            try await stream.processDownload(message: message, decodedData: filePacket, cypher: cypher)
                        } else {
                            print("Tried Queued Message, but still cannot find message in order to process download, we will erase the message from chat")
                        }
                    case .consumed:
                        return
                    }
                }
            }
        }
#endif
    }
    
    @MainActor
    public func onRemoveChatMessage(_ message: AnyChatMessage) {
        print("REMOVED MESSAGE", message.text)
#if (os(macOS) || os(iOS))
        messenger.emitter.messageRemoved = message
#endif
    }
    
    @MainActor
    func updateDeliveryStatus(message: AnyChatMessage) async throws {
        switch message.raw.deliveryState {
        case .none:
            break
        case .read:
            break
        case .revoked:
            break
        case .received:
            await priorityActor.queueThrowingAction(with: .background) { [weak self] in
                guard let self else { return }
                try await self.messenger.sendReadMessages(count: 1)
            }
        case .undelivered:
         break
        }
    }
    
    @MainActor
    public func onMessageChange(_ message: AnyChatMessage) {
#if os(iOS)
        Task { @PriorityActor [weak self] in
            guard let self else { return }
            try await self.updateDeliveryStatus(message: message)
        }
#elseif os(macOS)
#endif
        
#if (os(macOS) || os(iOS))
        messenger.emitter.messageChanged = message
#endif
    }
    @MainActor
    public func onCreateContact(_ contact: Contact, cypher: CypherMessenger) {
#if (os(macOS) || os(iOS))
        print("CREATED CONTACT")
        messenger.emitter.contactAdded = contact
#endif
    }
    
    @MainActor
    public func onContactChange(_ contact: Contact) {
#if (os(macOS) || os(iOS))
        print("CONTACT CHANGED")
        deleteOfflineMessage(contact)
        messenger.emitter.contactChanged = contact
#endif
    }
    
    @MainActor public func onRemoveContact(_ contact: Contact) {
#if (os(macOS) || os(iOS))
        print("REMOVED CONTACT")
        Task {
            let conversations = try await messenger.fetchConversations(messenger.cypher!)
            for conversation in conversations {
                switch conversation {
                case .privateChat(let privateChat):
                    if privateChat.conversationPartner == contact.username {
                        messenger.emitter.conversationToDelete = privateChat.conversation
                    }
                case .groupChat(let groupChat):
                    try await groupChat.kickMember(contact.username)
                case .internalChat(_):
                    ()
                }
            }
        }
        deleteOfflineMessage(contact, removedContact: true)
        //Tell other devieces we want to delete the contact
        notifyContactRemoved(contact)
        messenger.emitter.contactRemoved = contact
#endif
    }
    
    //If a user is not friends, we blocked them, or we deleted them as a contact we will delete all the stored messages that maybe online. Since we no long want to communicate with them.
    func deleteOfflineMessage(_ contact: Contact, removedContact: Bool = false) {
#if (os(macOS) || os(iOS))
        Task { @PriorityActor [weak self] in
            guard let self else { return }
            await self.priorityActor.queueThrowingAction(with: .background) { [weak self] in
                guard let self else { return }
                let blocked = await contact.ourFriendshipState == .blocked
                let notFriend = await contact.ourFriendshipState == .notFriend
                if blocked || notFriend {
                    try await messenger.deleteOfflineMessages(from: contact.username.raw)
                } else if removedContact {
                    try await messenger.deleteOfflineMessages(from: contact.username.raw)
                }
            }
        }
#endif
    }
    
    func notifyContactRemoved(_ contact: Contact) {
#if (os(macOS) || os(iOS))
        Task { @PriorityActor [weak self] in
            guard let self else { return }
            await self.priorityActor.queueThrowingAction(with: .background) { [weak self] in
                guard let self else { return }
                try await self.messenger.notifyContactRemoved(contact.username)
            }
        }
#endif
    }
    
    @MainActor public func onMembersOnline(_ nick: [NeedleTailNick]) {
#if (os(macOS) || os(iOS))
        messenger.emitter.nicksOnline = nick
#endif
    }
    
    @MainActor public func onPartMessage(_ message: String) {
#if (os(macOS) || os(iOS))
        messenger.emitter.partMessage = message
#endif
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
    
    /// This method is called when we send a PRIVMSG Packet that is specified as a .requestDeviceRegistery Packet. We then call it on our inbound handler. This is only called when the device created is not a master device.
    public func onDeviceRegisteryRequest(_ config: UserDeviceConfig, messenger: CypherMessenger) async throws {
        print(#function)
        try await messenger.addDevice(config)
    }
    public func onDeviceRegistery(_ deviceId: DeviceId, cypher: CypherMessenger) {
#if os(iOS)
        Task {
            try await cypher.renameCurrentDevice(to: UIDevice.current.name)
        }
#elseif os(macOS)
        Task {
            try await cypher.renameCurrentDevice(to: Host.current().localizedName ?? "No Device Name")
        }
#endif
    }
    
    public func onOtherUserDeviceRegistery(username: Username, deviceId: DeviceId, messenger: CypherMessenger) {
        
    }
    
    @MainActor
    public func onConversationChange(_ viewModel: AnyConversation) async {
#if (os(macOS) || os(iOS))
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.messenger.emitter.conversationChanged = await viewModel.resolveTarget()
        }
#endif
    }
    
    @MainActor
    public func onCreateConversation(_ viewModel: AnyConversation) {
#if (os(macOS) || os(iOS))
        self.messenger.emitter.conversationAdded = viewModel
#endif
    }
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
#endif
