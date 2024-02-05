//
//  File.swift
//  
//
//  Created by Cole M on 9/4/23.
//

import CypherMessaging
import NeedleTailHelpers

public final class MostRecentMessage<Chat: AnyConversation> {
    
#if (os(macOS) || os(iOS))
    @Published public var message: AnyChatMessage?
#else
    public var message: AnyChatMessage?
#endif
    let chat: Chat
    
    public init(chat: Chat) async throws {
        self.chat = chat
        let cursor = try await chat.cursor(sortedBy: .descending)
        let message = try await cursor.getNext()
        
        if message?.raw.encrypted.conversationId == chat.conversation.id {
            self.message = message
        }
    }
}

#if (os(macOS) || os(iOS))
extension MostRecentMessage: ObservableObject {}
#endif
