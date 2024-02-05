//
//  MessageDataToFilePlugin.swift
//  NeedleTail
//
//  Created by Cole M on 8/5/23.
//

import CypherMessaging

// I don't know Why CTK start Decrypting Props from the MainActor, I should put in a PR One day and fix this.
extension AnyChatMessage {
    
    @CryptoActor
    public func setMetadata(_
                            cypher: CypherMessenger,
                            emitter: NeedleTailEmitter,
                            sortChats: @escaping @MainActor (TargetConversation.Resolved, TargetConversation.Resolved) -> Bool,
                            run: @escaping @MainActor (inout ChatMessageModel.SecureProps) throws -> Document
    ) async throws {
        
        try await self.raw.modifyProps { props in
            let doc = try run(&props)
            props.message.metadata = doc
        }

        await MainActor.run {
            emitter.shouldRefreshView = true
        }
        
        try await cypher.updateChatMessage(self.raw)
    }
}
