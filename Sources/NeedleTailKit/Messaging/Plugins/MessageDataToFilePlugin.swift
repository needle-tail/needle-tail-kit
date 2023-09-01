//
//  MessageDataToFilePlugin.swift
//  NeedleTail
//
//  Created by Cole M on 8/5/23.
//

import Foundation
import NeedleTailHelpers
import MessagingHelpers
import CypherMessaging
import SwiftDTF
import Crypto


public struct MessageDataToFilePlugin: Plugin {

    public static let pluginIdentifier = "@/needletail/data-to-file"
    let needletailCrypto = NeedleTailCrypto()

    
    public static func createDataToFileMetadata<T: Codable>(metadata: T) async throws -> Document {
        try BSONEncoder().encode(metadata)
    }
    
    public static func removeFile(with url: URL) async {
            do {
                let fileName = url.lastPathComponent.components(separatedBy: ".")
                //We need to delete unencrypted video file after we play it. We Recreate it on each presentation.
                try DataToFile.shared.removeItem(
                    fileName: fileName[0],
                    fileType: fileName[1]
                )
                print("Removed file at path: \(fileName[0]).\(fileName[1])")
            } catch {
                print("There was an error removing item from Media Directory: Error: ", error)
            }
        }
    }


extension AnyChatMessage {
    
    @CryptoActor public func setMetadata(_
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

