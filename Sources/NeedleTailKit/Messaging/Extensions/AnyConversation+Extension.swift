//
//  AnyConversation+Extension.swift
//  
//
//  Created by Cole M on 9/2/23.
//

#if os(iOS) || os(macOS)
import CypherMessaging
import MessagingHelpers

private struct ChatMetadata: Codable {
    var isPinned: Bool?
    var isMarkedUnread: Bool?
}

struct PinnedChatsPlugin: Plugin {
    static let pluginIdentifier = "pinned-chats"
    
    func createPrivateChatMetadata(withUser otherUser: Username, messenger: CypherMessenger) async throws -> Document {
        try BSONEncoder().encode(ChatMetadata(isPinned: false, isMarkedUnread: false))
    }
}

extension AnyConversation {

    @MainActor
    func isPinned() -> Bool {
        do {
            guard let isPinned = try self.conversation.getProp(
                ofType: ChatMetadata.self,
                forPlugin: PinnedChatsPlugin.self,
                run: \.isPinned
            ) else {
                return false
            }
            return isPinned
        } catch {
            print(error)
            return false
        }
    }
    
//    @MainActor
//    public var isPinned: Bool {
//        (try? self.conversation.getProp(
//            ofType: ChatMetadata.self,
//            forPlugin: PinnedChatsPlugin.self,
//            run: \.isPinned
//        )) ?? false
//    }

    @MainActor
    public var isMarkedUnread: Bool {
        (try? self.conversation.getProp(
            ofType: ChatMetadata.self,
            forPlugin: PinnedChatsPlugin.self,
            run: \.isMarkedUnread
        )) ?? false
    }
    
    public func pin() async throws {
        try await modifyMetadata(
            ofType: ChatMetadata.self,
            forPlugin: PinnedChatsPlugin.self
        ) { metadata in
            metadata.isPinned = true
        }
    }
    
    public func unpin() async throws {
        try await modifyMetadata(
            ofType: ChatMetadata.self,
            forPlugin: PinnedChatsPlugin.self
        ) { metadata in
            metadata.isPinned = false
        }
    }
    
    @MainActor
    public func markUnread() async throws {
        try await modifyMetadata(
            ofType: ChatMetadata.self,
            forPlugin: PinnedChatsPlugin.self
        ) { metadata in
            metadata.isMarkedUnread = true
        }
    }
    
    @MainActor
    public func unmarkUnread() async throws {
        try await modifyMetadata(
            ofType: ChatMetadata.self,
            forPlugin: PinnedChatsPlugin.self
        ) { metadata in
            metadata.isMarkedUnread = false
        }
    }
}
public struct ModifyMessagePlugin: Plugin {
    public static let pluginIdentifier = "@/messaging/mutate-history"
    
    @MainActor public func onReceiveMessage(_ message: ReceivedMessageContext) async throws -> ProcessMessageAction? {
        guard
            message.message.messageType == .magic,
            var subType = message.message.messageSubtype,
            subType.hasPrefix("@/messaging/mutate-history/")
        else {
            return nil
        }
        
        subType.removeFirst("@/messaging/mutate-history/".count)
        let remoteId = message.message.text
        let sender = message.sender.username
        
        switch subType {
        case "revoke":
            let message = try await message.conversation.message(byRemoteId: remoteId)
            if message.sender == sender {
                // Message was sent by this user, so the action is permitted
                try await message.remove()
            }
            
            return .ignore
        default:
            return .ignore
        }
    }
    
    @CryptoActor public func onSendMessage(
        _ message: SentMessageContext
    ) async throws -> SendMessageAction? {
        guard
            message.message.messageType == .magic,
            let subType = message.message.messageSubtype,
            subType.hasPrefix("@/messaging/mutate-history/")
        else {
            return nil
        }
        
        return .send
    }
}
#endif
