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
    var mediaId: Data?
    var fileUrlString: Data?
    var fileNameBinary: Data
    var fileTypeBinary: Data
    var fileSize: Int?
    var blob: Data?
    
    public init(
        mediaId: Data?,
        fileUrlString: Data? = nil,
        fileNameBinary: Data,
        fileTypeBinary: Data,
        fileSize: Int? = nil,
        blob: Data? = nil
    ) {
        self.mediaId = mediaId
        self.fileUrlString = fileUrlString
        self.fileNameBinary = fileNameBinary
        self.fileTypeBinary = fileTypeBinary
        self.fileSize = fileSize
        self.blob = blob
    }
}

public struct ImageDataToFileMetaData: Codable {
    var mediaId: Data
    var thumbnailUrlString: Data?
    var thumbnailNameBinary: Data
    var thumbnailTypeBinary: Data
    var thumbnailBlob: Data?
    var imageUrlString: Data?
    var imageNameBinary: Data
    var imageTypeBinary: Data
    var imageBlob: Data?
    
    public init(
        mediaId: Data,
        thumbnailUrlString: Data? = nil,
        thumbnailNameBinary: Data,
        thumbnailTypeBinary: Data,
        thumbnailBlob: Data? = nil,
        imageUrlString: Data? = nil,
        imageNameBinary: Data,
        imageTypeBinary: Data,
        imageBlob: Data? = nil
    ) {
        self.mediaId = mediaId
        self.thumbnailUrlString = thumbnailUrlString
        self.thumbnailNameBinary = thumbnailNameBinary
        self.thumbnailTypeBinary = thumbnailTypeBinary
        self.thumbnailBlob = thumbnailBlob
        self.imageUrlString = imageUrlString
        self.imageNameBinary = imageNameBinary
        self.imageTypeBinary = imageTypeBinary
        self.imageBlob = imageBlob
    }
}

public struct MessageDataToFilePlugin: Plugin {

    public static let pluginIdentifier = "@/needletail/data-to-file"


    //When we re-send a message we want to create a file for the media data, add it to the metadata.
        public func onSendMessage(_ message: SentMessageContext) async throws -> SendMessageAction? {
            if message.message.messageType == .media && shouldProceed(message.message.messageSubtype ?? "") {
                if message.message.metadata["blob"] as? Binary == nil {
    //TODO: Create Data on resend
//                    let blob = try await createData(message: message.message, messenger: message.messenger)
//                    try await message.conversation.conversation.modifyMetadata(
//                        ofType: DataToFileMetaData.self,
//                        forPlugin: MessageDataToFilePlugin.self) { metadata in
//                            metadata = DataToFileMetaData(
//                                mediaId: metadata.mediaId,
//                                fileUrlString: nil,
//                                fileNameBinary:  metadata.fileNameBinary,
//                                fileTypeBinary:  metadata.fileTypeBinary,
//                                blob: blob
//                            )
//                        }
                }
                return .saveAndSend
            } else {
                return nil
            }
        }
    
    //When we create the message for the sender we want to modify the meta data in order to remove the media blob, this should prevent the app from consuming unreasonable memory due to large data amounts.
    public func onCreateChatMessage(_ conversation: AnyChatMessage) {
        Task {
            //Do nothing this means our message is not multipart
            if let blob = await conversation.metadata["blob"] as? Binary {
                guard blob.data.count >= 10777216 else { return }
            }
            
            do {
                let subType = await conversation.messageSubtype ?? ""
                if await conversation.messageType == .media && shouldProceed(subType) {
                    
                    if await conversation.messageSubtype == "image/*" {
                        
                        let files = try await createImageFile(
                            messageSubtype: conversation.messageSubtype ?? "",
                            metadata: conversation.metadata,
                            messenger: conversation.messenger
                        )
                        
                        try await conversation.setMetadata(conversation.messenger, sortChats: sortConversations) { props in
                            
                            let document = props.message.metadata
                            let dtf = try! BSONDecoder().decode(ImageDataToFileMetaData.self, from: document)
                            
                            let metadata = ImageDataToFileMetaData(
                                mediaId: dtf.mediaId,
                                thumbnailUrlString: files.1?.data(using: .utf8),
                                thumbnailNameBinary: dtf.thumbnailNameBinary,
                                thumbnailTypeBinary: dtf.thumbnailTypeBinary,
                                thumbnailBlob: nil,
                                imageUrlString: files.0?.data(using: .utf8),
                                imageNameBinary: dtf.imageNameBinary,
                                imageTypeBinary: dtf.imageTypeBinary,
                                imageBlob: nil
                            )
                            
                            return try BSONEncoder().encode(metadata)
                        }
                        
                    } else {
                        
                        let file = try await createFile(
                            messageSubtype: conversation.messageSubtype ?? "",
                            metadata: conversation.metadata,
                            messenger: conversation.messenger
                        )
                            
                            try await conversation.setMetadata(conversation.messenger, sortChats: sortConversations) { props in
                                
                                let document = props.message.metadata
                                let dtf = try BSONDecoder().decode(DataToFileMetaData.self, from: document)
                                
                                let metadata = DataToFileMetaData(
                                    mediaId: dtf.mediaId,
                                    fileUrlString: file?.data(using: .utf8),
                                    fileNameBinary: dtf.fileNameBinary,
                                    fileTypeBinary: dtf.fileTypeBinary,
                                    fileSize: dtf.fileSize,
                                    blob: nil
                                )
                                return try BSONEncoder().encode(metadata)
                            }
                        
                    }
                }
            } catch {
                print("ERROR MODIFYING METADATA", error)
            }
        }
    }
    
    private func shouldProceed(_ messageSubtype: String) -> Bool {
        if messageSubtype == "video/*" ||
            messageSubtype == "audio/*" ||
            messageSubtype == "image/*" ||
            messageSubtype == "videoThumbnail/*" ||
            messageSubtype == "doc/*" {
            return true
        } else {
            return false
        }
    }
    
    private func createFile(
        messageSubtype: String,
        metadata: Document,
        messenger: CypherMessenger
    ) async throws -> String? {
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
            guard let fileType = String(data: fileTypeData, encoding: .utf8) else { return nil }
            
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
    
    private func createImageFile(
        messageSubtype: String,
        metadata: Document,
        messenger: CypherMessenger
    ) async throws -> (String?, String?) {
        if shouldProceed(messageSubtype) {
            
            let imageBinary = metadata["imageBlob"] as? Binary
            guard let imageData = imageBinary?.data else { return (nil, nil) }
            
            let thumbnailBinary = metadata["thumbnailBlob"] as? Binary
            guard let thumbnailData = thumbnailBinary?.data else { return (nil, nil) }
            
            //Encrypt
            let imageBox = try messenger.encryptLocalFile(imageData)
            guard let imageCombinedBoxData = imageBox.combined else { return (nil, nil) }
            
            //Encrypt
            let thumbnailBox = try messenger.encryptLocalFile(thumbnailData)
            guard let thumbnailCombinedBoxData = thumbnailBox.combined else { return (nil, nil) }
            
            let imageNameBinary = metadata["imageNameBinary"] as? Binary
            guard let imageNameData = imageNameBinary?.data else { return (nil, nil) }
            guard let imageName = String(data: imageNameData, encoding: .utf8) else { return (nil, nil) }
            
            let imageTypeBinary = metadata["imageTypeBinary"] as? Binary
            guard let imageTypeData = imageTypeBinary?.data else { return (nil, nil) }
            guard let imageType = String(data: imageTypeData, encoding: .utf8) else { return (nil, nil) }
            
            
            let thumbnailNameBinary = metadata["thumbnailNameBinary"] as? Binary
            guard let thumbnailNameData = thumbnailNameBinary?.data else { return (nil, nil) }
            guard let thumbnailName = String(data: thumbnailNameData, encoding: .utf8) else { return (nil, nil) }
            
            let thumbnailTypeBinary = metadata["thumbnailTypeBinary"] as? Binary
            guard let thumbnailTypeData = thumbnailTypeBinary?.data else { return (nil, nil) }
            guard let thumbnailType = String(data: thumbnailTypeData, encoding: .utf8) else { return (nil, nil) }
            
            //We save data that will not be able to be read as the intended file type. We must pull the data from the file decrypt it and then reconstruct the data and place it back into the file with the right file type
            let imageURLString = try await DataToFile.shared.generateFile(
                data: imageCombinedBoxData,
                fileName: imageName,
                fileType:  imageType
            )
            
            let thumbnailURLString = try await DataToFile.shared.generateFile(
                data: thumbnailCombinedBoxData,
                fileName: thumbnailName,
                fileType: thumbnailType
            )
            return (imageURLString, thumbnailURLString)
        } else {
            return (nil, nil)
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
    
    public static func decryptFileData(_ fileData: Data, cypher: CypherMessenger) async throws -> Data {
        guard let fileName = String(data: fileData, encoding: .utf8) else { fatalError("Could not generate blob") }
        guard let blob = try await DataToFile.shared.generateData(from: fileName) else { fatalError("Could not generate blob") }
        let data = try cypher.decryptLocalFile(AES.GCM.SealedBox(combined: blob))
        return data
    }
    
    public static func createDataToFileMetadata<T: Codable>(metadata: T) async throws -> Document {
        try BSONEncoder().encode(metadata)
    }
    
    public static func removeFile(with url: URL) async {
            do {
                let fileName = url.lastPathComponent.components(separatedBy: ".")
                //We need to delete unencrypted video file after we play it. We Recreate it on each presentation.
                try await DataToFile.shared.removeItem(
                    fileName: fileName[0],
                    fileType: fileName[1]
                )
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
