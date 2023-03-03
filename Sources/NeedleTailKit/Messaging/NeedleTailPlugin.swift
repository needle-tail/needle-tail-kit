//
//  NeedleTailPlugin.swift
//
//
//  Created by Cole M on 4/15/22.
//

import MessagingHelpers
import CypherMessaging
import NeedleTailHelpers

//Our Store for loading receiving messages in real time(TOP LEVEL)
public class NeedleTailPlugin: Plugin {
    
    public static let pluginIdentifier = "needletail"
    var store: NeedleTailStore
    
    public init(store: NeedleTailStore) {
        self.store = store
    }
    
    public func onCreateChatMessage(_ message: AnyChatMessage) {
#if (os(macOS) || os(iOS))
        store.emitter?.messageReceived = message
#endif
    }
    
    public func onRemoveChatMessage(_ message: AnyChatMessage) {
#if (os(macOS) || os(iOS))
        store.emitter?.messageRemoved = message
#endif
    }
    public func onMessageChange(_ message: AnyChatMessage) {
#if (os(macOS) || os(iOS))
        store.emitter?.messageChanged = message
#endif
    }
    
    public func onCreateContact(_ contact: Contact, cypher: CypherMessenger) {
#if (os(macOS) || os(iOS))
        store.emitter?.contactAdded = contact
#endif
    }
    
    public func onContactChange(_ contact: Contact) {
#if (os(macOS) || os(iOS))
        store.emitter?.contactChanged = contact
#endif
    }
    
    @MainActor public func onRemoveContact(_ contact: Contact) {
#if (os(macOS) || os(iOS))
        store.emitter?.contactRemoved = contact
#endif
    }
    
    @MainActor public func onMembersOnline(_ nick: [NeedleTailNick]) {
#if (os(macOS) || os(iOS))
        store.emitter?.nicksOnline = nick
#endif
    }
    
    @MainActor public func onPartMessage(_ message: String) {
#if (os(macOS) || os(iOS))
        store.emitter?.partMessage = message
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
    public func onDeviceRegistery(_ deviceId: DeviceId, cypher: CypherMessenger) async throws {
        //        DispatchQueue.main.async {
        //            emitter.userDevicesChanged.send()
        //        }
    }
    
    
        public func onConversationChange(_ viewModel: AnyConversation) {
            store.emitter?.conversationChanged = viewModel
//            Task.detached {
//                let viewModel = await viewModel.resolveTarget()
//                DispatchQueue.main.async {
//                    emitter.conversationChanged.send(viewModel)
//                }
//            }
        }
        public func onCreateConversation(_ viewModel: AnyConversation) {
//            emitter.conversationAdded.send(viewModel)
            store.emitter?.conversationAdded = viewModel
        }
    
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
