//
//  MessageDataToFilePlugin.swift
//  NeedleTail
//
//  Created by Cole M on 8/5/23.
//

import Foundation
import MessagingHelpers
import CypherMessaging
import SwiftDTF
import Crypto

public struct DataToFileMetaData: Codable {
    var mediaId: Data
    var fileUrlString: Data?
    var fileNameBinary: Data
    var fileTypeBinary: Data
    var blob: Data?
    
    public init(
        mediaId: Data,
        fileUrlString: Data? = nil,
        fileNameBinary: Data,
        fileTypeBinary: Data,
        blob: Data? = nil
    ) {
        self.mediaId = mediaId
        self.fileUrlString = fileUrlString
        self.fileNameBinary = fileNameBinary
        self.fileTypeBinary = fileTypeBinary
        self.blob = blob
    }
}

public struct MessageDataToFilePlugin: Plugin {

    public static let pluginIdentifier = "@/needletail/data-to-file"

    public static func createDataToFileMetadata(metadata: DataToFileMetaData) async throws -> Document {
        try BSONEncoder().encode(metadata)
    }

    //When we re-send a message we want to create a file for the media data, add it to the metadata.
    //    public func onSendMessage(_ message: SentMessageContext) async throws -> SendMessageAction? {
    //        //TODO: What if we have already done this once?
    //        if message.message.messageType == .media && shouldProceed(message.message.messageSubtype ?? "") {
    //            if message.message.metadata["blob"] as? Binary == nil {
    //
    //                let blob = try await createData(message: message.message, messenger: message.messenger)
    //                try await message.conversation.conversation.modifyMetadata(
    //                    ofType: DataToFileMetaData.self,
    //                    forPlugin: MessageDataToFilePlugin.self) { metadata in
    //                        metadata = DataToFileMetaData(
    //                            mediaId: metadata.mediaId,
    //                            fileUrlString: nil,
    //                            fileNameBinary:  metadata.fileNameBinary,
    //                            fileTypeBinary:  metadata.fileTypeBinary,
    //                            blob: blob
    //                        )
    //                    }
    //            }
    //            return .saveAndSend
    //        } else {
    //            return nil
    //        }
    //    }
    
    //When we create the message for the sender we want to modify the meta data in order to remove the media blob, this should prevent the app from consuming unreasonable memory due to large data amounts.
    public func onCreateChatMessage(_ conversation: AnyChatMessage) {
        Task {
            do {
                let subType = await conversation.messageSubtype ?? ""
                print("SYBTYPE___", subType)
                if await conversation.messageType == .media && shouldProceed(subType) {
                    let urlString = try await createFile(
                        messageSubtype: conversation.messageSubtype ?? "",
                        metadata: conversation.metadata,
                        messenger: conversation.messenger
                    )
                    //TODO: FEED CYPHER MESSENGER IN PLACE OF EMITTER AND SORT MESSAGES
                    try await conversation.setMetadata(conversation.messenger, sortChats: sortConversations) { props in
                        
                        let document = props.message.metadata
                        let dtf = try BSONDecoder().decode(DataToFileMetaData.self, from: document)
                        
                        let metadata = DataToFileMetaData(
                            mediaId: dtf.mediaId,
                            fileUrlString: urlString?.data(using: .utf8),
                            fileNameBinary: dtf.fileNameBinary,
                            fileTypeBinary: dtf.fileTypeBinary,
                            blob: nil
                        )
                        
                        return try BSONEncoder().encode(metadata)
                    }
                    
                }
            } catch {
                print("ERROR MODIFYING METADATA", error)
            }
        }
    }
    
    private func shouldProceed(_ messageSubtype: String) -> Bool {
        if messageSubtype == "video/*" ||
            messageSubtype == "image/*" ||
            messageSubtype == "videoThumbnail/*" ||
            messageSubtype == "doc/*" {
            return true
        } else {
            return false
        }
    }
    
    private func createFile(messageSubtype: String, metadata: Document, messenger: CypherMessenger) async throws -> String? {
        if shouldProceed(messageSubtype) {
            let multipartBinary = metadata["blob"] as? Binary
            guard let multipartData = multipartBinary?.data else { return nil }
            
            //Encrypt
            let box = try messenger.encryptLocalFile(multipartData)
            guard let combinedBoxData = box.combined else { return nil }
            
            let fileNameBinary = metadata["fileNameBinary"] as? Binary
            guard let fileNameData = fileNameBinary?.data else { return nil }
            guard let fileName = String(data: fileNameData, encoding: .utf8) else { return nil }
            
            let fileTypeBinary = metadata["fileTypeBinary"] as? Binary
            guard let fileTypeData = fileTypeBinary?.data else { return nil }
            guard let fileTypeString = String(data: fileTypeData, encoding: .utf8) else { return nil }
            guard let fileType = DataToFile.FileType(rawValue: fileTypeString) else { return nil }
            
            //We save data that will not be able to be read as the intended file type. We must pull the data from the file decrypt it and then reconstruct the data and place it back into the file with the right file type
            return try await DataToFile.shared.generateFile(
                data: combinedBoxData,
                fileName: fileName,
                fileType:  fileType
            )
        } else {
            return nil
        }
    }
    
    private func createData(message: SingleCypherMessage, messenger: CypherMessenger) async throws -> Data {
        let fileURLStringBinary = message.metadata["fileUrlString"] as? Binary
        guard let fileNameData = fileURLStringBinary?.data else { fatalError("Could not generate blob") }
        guard let fileName = String(data: fileNameData, encoding: .utf8) else { fatalError("Could not generate blob") }
        guard let blob = try await DataToFile.shared.generateData(from: fileName) else { fatalError("Could not generate blob") }
        
        //Decrypt
        return try messenger.decryptLocalFile(AES.GCM.SealedBox(combined: blob))
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
    }
}
