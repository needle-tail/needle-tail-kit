//
//  MessageDataToFilePlugin.swift
//  NeedleTail
//
//  Created by Cole M on 8/5/23.
//

import CypherMessaging

extension AnyChatMessage {
    
    @CryptoActor
    public func setMetadata(_
                            cypher: CypherMessenger,
                            sortChats: @escaping @MainActor (TargetConversation.Resolved, TargetConversation.Resolved) -> Bool,
                            run: @Sendable @escaping(inout ChatMessageModel.SecureProps) throws -> Document
    ) async throws {
        try await self.raw.modifyProps { props in
            let doc = try run(&props)
            props.message.metadata = doc
        }
        try await cypher.updateChatMessage(self.raw)
        await cypher.emptyCaches()
    }
}

