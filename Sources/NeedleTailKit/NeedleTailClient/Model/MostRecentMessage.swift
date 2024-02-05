//
//  File.swift
//  
//
//  Created by Cole M on 9/4/23.
//

import CypherMessaging
import NeedleTailHelpers

public final class MostRecentMessage<Chat: AnyConversation> {
    
    @Published public var message: AnyChatMessage?
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
