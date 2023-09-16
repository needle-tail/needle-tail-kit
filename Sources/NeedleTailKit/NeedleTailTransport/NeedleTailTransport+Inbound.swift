//
//  IRCClient+Inbound.swift
//
//
//  Created by Cole M on 4/29/22.
//

import CypherMessaging
import NeedleTailHelpers
@_spi(AsyncChannel) import NeedleTailProtocol
@_spi(AsyncChannel) import NIOCore
#if os(macOS)
import AppKit
#endif
#if canImport(Crypto)
import Crypto
#endif
#if canImport(SwiftDTF)
import SwiftDTF
#endif

#if canImport(SwiftUI) && canImport(Combine) && (os(macOS) || os(iOS))
extension NeedleTailTransport {
    public func doNotice(recipients: [IRCMessageRecipient], message: String) async throws {
        await respondToTransportState()
    }
}
#endif

#if (os(macOS) || os(iOS))
extension NeedleTailTransport {
    
    
    /// We receive the messageId via a **QRCode** from the **Child Device** we will emit this id to the **Master's Client** in order to generate an approval **QRCode**.
    /// - Parameter messageId: The message request identity generated by the **Child Device**
    func receivedRegistryRequest(_ messageId: String) async throws {
#if (os(macOS) || os(iOS))
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.messenger.emitter.requestMessageId = messageId
        }
#endif
    }
    
    /// If the approval code matches the code that the requesting device temporarily store it then let the requesting client know that the master devices has approved of the registration of this device.
    func computeApproval(_ code: String) async -> Bool {
        if self.registryRequestId == code {
            self.registryRequestId = ""
            return true
        }
        return false
    }
    
    /// This method is called on the Dispatcher, After the master device adds the new Device locally and then sends it to the server to be saved
    func receivedNewDevice(_ deviceState: NewDeviceState, contacts: [NTKContact]) async throws {
        self.receivedNewDeviceAdded = deviceState
        try await addMasterDevicesContacts(contacts)
#if (os(macOS) || os(iOS))
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.clearNewDeviceState(messenger)
        }
#endif
    }
    
    func addMasterDevicesContacts(_ contactList: [NTKContact]) async throws {
        for contact in contactList {
            let createdContact = try await ntkBundle.cypher?.createContact(byUsername: contact.username)
            try await createdContact?.setNickname(to: contact.nickname)
        }
    }
    
    @MainActor
    private func clearNewDeviceState(_ messenger: NeedleTailMessenger) {
#if (os(macOS) || os(iOS))
        messenger.emitter.qrCodeData = nil
        messenger.emitter.showProgress = false
        messenger.emitter.dismissRegistration = true
#endif
    }
    
    @_spi(AsyncChannel)
    public func sendMessageTypePacket(_ type: MessageType, nick: NeedleTailNick) async throws {
        try await ThrowingTaskGroup<Void, Error>.executeChildTask { [weak self] in
            guard let self else { return }
            let packet = MessagePacket(
                id: UUID().uuidString,
                pushType: .none,
                type: type,
                createdAt: Date(),
                sender: nil,
                recipient: nil,
                message: nil,
                readReceipt: .none
            )
            let encodedData = try BSONEncoder().encode(packet).makeData()
            let type = TransportMessageType.private(.PRIVMSG([.nick(nick)], encodedData.base64EncodedString()))
            let writer = await self.asyncChannel.outboundWriter
            try await self.transportMessage(
                writer,
                origin: self.origin ?? "",
                type: type
            )
        }
    }
    
    @_spi(AsyncChannel)
    public func doMessage(
        sender: IRCUserID?,
        recipients: [ IRCMessageRecipient ],
        message: String,
        tags: [IRCTags]?
    ) async throws {
        guard let data = Data(base64Encoded: message) else { return }
        let buffer = ByteBuffer(data: data)
        let packet = try BSONDecoder().decode(MessagePacket.self, from: Document(buffer: buffer))
        for recipient in recipients {
            switch recipient {
            case .everything:
                break
            case .nick(_):
                switch packet.type {
                case .publishKeyBundle(_):
                    break
                case .registerAPN(_):
                    break
                case .message:
                    // We get the Message from IRC and Pass it off to CypherTextKit where it will enqueue it in a job and save it to the DB where we can get the message from.
                    try await processMessage(
                        packet,
                        sender: sender,
                        recipient: recipient,
                        messageType: .message,
                        ackType: .messageSent
                    )
                case .multiRecipientMessage:
                    break
                case .readReceipt:
                    guard let receipt = packet.readReceipt else { throw NeedleTailError.nilReadReceipt }
                    switch packet.readReceipt?.state {
                    case .displayed:
                        try await ctcDelegate?.receiveServerEvent(
                            .messageDisplayed(
                                by: receipt.sender.username,
                                deviceId: receipt.sender.deviceId,
                                id: receipt.messageId,
                                receivedAt: receipt.receivedAt
                            )
                        )
                    case .received:
                        try await ctcDelegate?.receiveServerEvent(
                            .messageReceived(
                                by: receipt.sender.username,
                                deviceId: receipt.sender.deviceId,
                                id: receipt.messageId,
                                receivedAt: receipt.receivedAt
                            )
                        )
                    default:
                        break
                    }
                case .ack(let ack):
                    let buffer = ByteBuffer(data: ack)
                    let ack = try BSONDecoder().decode(Acknowledgment.self, from: Document(buffer: buffer))
                    store.setAck(ack.acknowledgment)
                    switch store.acknowledgment {
                    case .registered(let bool):
                        guard bool == "true" else { return }
                        switch transportState.current {
                        case .transportRegistered(isActive: let isActive, clientContext: let clientContext):
                            try await ThrowingTaskGroup<Void, Error>.executeChildTask { [weak self] in
                                guard let self else { return }
                                let type = TransportMessageType.standard(.USER(clientContext.userInfo))
                                let writer = await self.asyncChannel.outboundWriter
                                try await self.transportMessage(
                                    writer,
                                    origin: self.origin ?? "",
                                    type: type
                                )
                                await transportState.transition(to: .transportOnline(isActive: isActive, clientContext: clientContext))
                            }
                        default:
                            return
                        }
                    case .quited:
                        quiting = false
                        await ctDelegate?.shutdown()
                        await transportState.transition(to: .transportOffline)
#if os(macOS)
                        await NSApplication.shared.reply(toApplicationShouldTerminate: true)
#endif
                    case .multipartUploadComplete(let packet):
#if (os(macOS) || os(iOS))
                        if packet.size <= 10777216 && packet.size != 0 {
                            try await ThrowingTaskGroup<Void, Error>.executeChildTask { [weak self] in
                                guard let self else { return }
                                let data = try BSONEncoder().encode([packet.name]).makeData()
                                let type = TransportMessageType.standard(.otherCommand(Constants.multipartMediaDownload.rawValue, [data.base64EncodedString()]))
                                let writer = await self.asyncChannel.outboundWriter
                                try await self.transportMessage(
                                    writer,
                                    origin: self.origin ?? "",
                                    type: type
                                )
                            }
                        }
                        
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            self.messenger.emitter.multipartUploadComplete = true
                        }
                        Task { @NeedleTailTransportActor [weak self] in
                            guard let self else { return }
                            hasStarted = false
                        }
#else
                        break
#endif
                    case .multipartDownloadFailed(let error):
#if (os(macOS) || os(iOS))
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            self.messenger.emitter.multipartDownloadFailed = MultipartDownloadFailed(status: true, error: error)
                        }
#else
                        break
#endif
                    default:
                        break
                    }
                case .requestRegistry:
                    switch packet.addDeviceType {
                    case .master:
                        try await receivedRegistryRequest(packet.id)
                    case .child:
                        guard let childDeviceConfig = packet.childDeviceConfig else { return }
                        try await ctcDelegate?.receiveServerEvent(
                            .requestDeviceRegistery(childDeviceConfig)
                        )
                    default:
                        break
                    }
                case .newDevice(let state):
                    guard let contacts = packet.contacts else { return }
                    try await receivedNewDevice(state, contacts: contacts)
                case .notifyContactRemoval:
#if os(iOS) || os(macOS)
                    guard let contact = packet.contacts?.first else { return }
                    guard let foundContact = try await messenger.cypher?.getContact(byUsername: contact.username) else { return }
                    try await messenger.removeMessages(from: foundContact)
                    try await foundContact.remove()
#else
                    return
#endif
                default:
                    return
                }
            case .channel(_):
                switch packet.type {
                case .message:
                    // We get the Message from IRC and Pass it off to CypherTextKit where it will enqueue it in a job and save it to the DB where we can get the message from.
                    try await processMessage(
                        packet,
                        sender: sender,
                        recipient: recipient,
                        messageType: .message,
                        ackType: .messageSent
                    )
                default:
                    return
                }
            }
        }
    }
    
    @_spi(AsyncChannel)
    public func processMessage(_
                               packet: MessagePacket,
                               sender: IRCUserID?,
                               recipient: IRCMessageRecipient,
                               messageType: MessageType,
                               ackType: Acknowledgment.AckType,
                               messagePacket: MultipartMessagePacket? = nil
    ) async throws {
        guard let message = packet.message else { throw NeedleTailError.messageReceivedError }
        guard let deviceId = packet.sender else { throw NeedleTailError.senderNil }
        guard let sender = sender?.nick.name else { throw NeedleTailError.nilNickName }
        do {
            try await ctcDelegate?.receiveServerEvent(
                .messageSent(
                    message,
                    id: packet.id,
                    byUser: Username(sender),
                    deviceId: deviceId
                )
            )
        } catch {
            logger.error("\(error.localizedDescription)")
            return
        }
        
        try await ThrowingTaskGroup<Void, Error>.executeChildTask { [weak self] in
            guard let self else { return }
            let acknowledgement = try await self.createAcknowledgment(ackType, id: packet.id, messagePacket: messagePacket)
            let ackMessage = acknowledgement.base64EncodedString()
            let type = TransportMessageType.private(.PRIVMSG([recipient], ackMessage))
            let writer = await self.asyncChannel.outboundWriter
            try await self.transportMessage(
                writer,
                origin: self.origin ?? "",
                type: type
            )
        }
    }
    
    private func createAcknowledgment(_
                                      ackType: Acknowledgment.AckType,
                                      id: String? = nil,
                                      messagePacket: MultipartMessagePacket? = nil
    ) async throws -> Data {
        //Send message ack
        let received = Acknowledgment(acknowledgment: ackType)
        let ack = try BSONEncoder().encode(received).makeData()
        
        let packet = MessagePacket(
            id: id ?? UUID().uuidString,
            pushType: .none,
            type: .ack(ack),
            createdAt: Date(),
            sender: nil,
            recipient: nil,
            message: nil,
            readReceipt: .none,
            multipartMessage: messagePacket
        )
        
        return try BSONEncoder().encode(packet).makeData()
    }
    
    
    public func doNick(_ newNick: NeedleTailNick) async throws {}
    
    
    public func doMode(nick: NeedleTailNick, add: IRCUserMode, remove: IRCUserMode) async throws {
        var newMode = userMode
        newMode.subtract(remove)
        newMode.formUnion(add)
        if newMode != userMode {
            userMode = newMode
            await respondToTransportState()
        }
    }
    
    
    public func doBlobs(_ blobs: [String]) async throws {
        guard let blob = blobs.first else { throw NeedleTailError.nilBlob }
        self.channelBlob = blob
    }
    
    
    public func doJoin(_ channels: [IRCChannelName], tags: [IRCTags]?) async throws {
        logger.info("Joining channels: \(channels)")
        await respondToTransportState()
        
        guard let tag = tags?.first?.value else { return }
        self.channelBlob = tag
        
        guard let data = Data(base64Encoded: tag) else  { return }
        
        let onlineNicks = try BSONDecoder().decode([NeedleTailNick].self, from: Document(data: data))
        await plugin?.onMembersOnline(onlineNicks)
    }
    
    public func doPart(_ channels: [IRCChannelName], tags: [IRCTags]?) async throws {
        await respondToTransportState()
        
        guard let tag = tags?.first?.value else { return }
        guard let data = Data(base64Encoded: tag) else  { return }
        let channelPacket = try BSONDecoder().decode(NeedleTailChannelPacket.self, from: Document(data: data))
        await plugin?.onPartMessage(channelPacket.partMessage ?? "No Message Specified")
    }
    
    public func doIsOnline(_ nicks: [NeedleTailNick]) async throws {
        for nick in nicks {
            print("IS ONLINE", nick)
        }
    }
    
    public func doModeGet(nick: NeedleTailNick) async throws {
        await respondToTransportState()
    }
    
    
    //Send a PONG Reply to server When We receive a PING MESSAGE FROM SERVER
    @_spi(AsyncChannel)
    public func doPing(_ origin: String, origin2: String? = nil) async throws {
        try await ThrowingTaskGroup<Void, Error>.executeChildTask { [weak self] in
            guard let self else { return }
            try await Task.sleep(until: .now + .seconds(5), tolerance: .seconds(2), clock: .suspending)
            let type = TransportMessageType.standard(.PONG(server: origin, server2: origin2))
            let writer = await self.asyncChannel.outboundWriter
            try await self.transportMessage(
                writer,
                origin: self.origin ?? "",
                type: type
            )
        }
    }
    
    public func respondToTransportState() async {
        switch transportState.current {
        case .clientOffline:
            break
        case .clientConnecting:
            break
        case .clientConnected:
            break
        case .transportRegistering(isActive: _, clientContext: _):
            break
        case .transportOnline(isActive: _, clientContext: _):
            break
        case .transportDeregistering:
            break
        case .transportOffline:
            break
        case .clientDisconnected:
            break
        case .transportRegistered:
            break
        }
    }
    
    
    func handleInfo(_ info: [String]) async {
        logger.info("Server information: \(info.joined())")
    }
    
    
    func handleTopic(_ topic: String, on channel: IRCChannelName) {
        logger.info("Topic: \(topic), on Channel: \(channel)")
    }
    
    func handleServerMessages(_ messages: [String], type: IRCCommandCode) async {
        logger.info("Server Message: \n\(messages.joined(separator: "\n"))- type: \(type)")
    }
    
    public func doMultipartMessageDownload(_ packet: [String]) async throws {
        logger.info("Received multipart packet: \(packet[0]) of: \(packet[1])")
        precondition(packet.count == 4)
        let partNumber = packet[0]
        let totalParts = packet[1]
        let chunk = packet[3]
        guard let data = Data(base64Encoded: chunk) else { return }
        
        multipartData.append(data)
        
        if Int(partNumber) == Int(totalParts) {
            logger.info("Finished receiving parts...")
            logger.info("Starting to process multipart packet...")
            
            try await processMultipartMediaMessage(multipartData)
            multipartData.removeAll()
        }
    }
    
    public func doListBucket(_ packet: [String]) async throws {
        guard let data = Data(base64Encoded: packet[0]) else { return }
        let nameList = try BSONDecoder().decode([String].self, from: Document(data: data))
        var filenames = [Filename]()
        for name in nameList {
            filenames.append(Filename(name))
        }
        await setFileNames(filenames)
    }
    
    @MainActor
    private func setFileNames(_ filenames: [Filename]) async {
        messenger.emitter.listedFilenames = filenames
    }
    
    private func processMultipartMediaMessage(_ multipartData: Data) async throws {
        let decodedData = try BSONDecoder().decode(FilePacket.self, from: Document(data: multipartData))
        guard let cypher = await messenger.cypher else { return }
        //1. Look up message by Id
        if let message = try await messenger.findMessage(from: decodedData.mediaId, cypher: cypher) {
            try await processDownload(message: message, decodedData: decodedData, cypher: cypher)
        } else {
            logger.info("Couldn't find message in order to process media")
        }
    }
    
    private func processDownload(message: AnyChatMessage, decodedData: FilePacket, cypher: CypherMessenger) async throws {
        let mediaId = await message.metadata["mediaId"] as? String
        if mediaId == decodedData.mediaId {
            guard let keyBinary = await message.metadata["symmetricKey"] as? Binary else { return }
            let symmetricKey = try BSONDecoder().decode(SymmetricKey.self, from: Document(data: keyBinary.data))
            try await message.setMetadata(cypher, sortChats: sortConversations, run: { [weak self] props in
                let document = props.message.metadata
                var dtfp = try BSONDecoder().decode(DataToFilePacket.self, from: document)
                guard let self else { return try BSONEncoder().encode(dtfp) }
                guard let fileData = try self.needleTailCrypto.decrypt(data: decodedData.data, symmetricKey: symmetricKey) else { return try BSONEncoder().encode(dtfp) }
                guard let fileBoxData = try cypher.encryptLocalFile(fileData).combined else { return try BSONEncoder().encode(dtfp) }

                switch decodedData.mediaType {
                case .file:
                    let fileLocation = try DataToFile.shared.generateFile(
                        data: fileBoxData,
                        fileName: dtfp.fileName,
                        fileType: dtfp.fileType
                    )
                    dtfp.fileLocation = fileLocation
                    dtfp.fileSize = fileBoxData.count
                case .thumbnail:
                    let fileLocation = try DataToFile.shared.generateFile(
                        data: fileBoxData,
                        fileName: dtfp.thumbnailName,
                        fileType: dtfp.thumbnailType
                    )
                    dtfp.thumbnailLocation = fileLocation
                    dtfp.thumbnailSize = fileBoxData.count
                }
                
                dtfp.fileBlob = nil
                dtfp.thumbnailBlob = nil
                return try BSONEncoder().encode(dtfp)
            })
            await updateMetadata(message)

            var fileName = ""
            var fileType = ""
            switch decodedData.mediaType {
            case .file:
               fileName = await message.metadata["fileName"] as? String ?? ""
               fileType = await message.metadata["fileType"] as? String ?? ""
            case .thumbnail:
                fileName = await message.metadata["thumbnailName"] as? String ?? ""
                fileType = await message.metadata["thumbnailType"] as? String ?? ""
            }
         
           
            guard let senderDeviceId = await messenger.cypher?.deviceId else { return }
            var packet = MessagePacket(
                id: UUID().uuidString,
                pushType: .none,
                type: .ack(Data()),
                createdAt: Date(),
                sender: senderDeviceId,
                recipient: nil,
                multipartMessage: MultipartMessagePacket(
                    id: "\(fileName)_\(senderDeviceId.raw).\(fileType)",
                    sender: clientContext.nickname
                )
            )
            
            let acknowledgement = try await self.createAcknowledgment(.multipartReceived, id: packet.id, messagePacket: packet.multipartMessage)
            packet.type = .ack(acknowledgement)
            let ackMessage = acknowledgement.base64EncodedString()
            let type = TransportMessageType.private(.PRIVMSG([IRCMessageRecipient.nick(clientContext.nickname)], ackMessage))
            let writer = self.asyncChannel.outboundWriter
            try await self.transportMessage(
                writer,
                origin: self.origin ?? "",
                type: type
            )   
        }
    }
    
    @MainActor
    func updateMetadata(_ message: AnyChatMessage?) async {
        messenger.emitter.metadataChanged = message
    }
}


struct FilePacket: Sendable, Codable {
    var mediaId: String
    var mediaType: MediaType
    var name: String
    var data: Data
}

enum MediaType: Sendable, Codable {
    case thumbnail, file
}
#endif
