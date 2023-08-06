//
//  NeedleTailTransportClient+Outbound.swift
//
//
//  Created by Cole M on 4/29/22.
//


import NeedleTailHelpers
import CypherMessaging
import NeedleTailProtocol
import Algorithms
import DequeModule
@_spi(AsyncChannel) import NIOCore

@NeedleTailTransportActor
extension NeedleTailTransport {
    
    /// This is where we register the transport session
    /// - Parameter regPacket: Our Registration Packet
    @_spi(AsyncChannel)
    public func registerNeedletailSession(_ regPacket: Data, _ temp: Bool = false) async throws {
        let isActive = await asyncChannel.channel.isActive
        await transportState.transition(to:
                .transportRegistering(
                    isActive: isActive,
                    clientContext: clientContext
                )
        )
        
        guard case .transportRegistering(_, let clientContext) = transportState.current else { throw NeedleTailError.transportationStateError }
        let value = regPacket.base64EncodedString()
        guard temp == false else {
            let tag = IRCTags(key: "tempRegPacket", value: value)
            try await clientMessage(.NICK(clientContext.nickname), tags: [tag])
            return
        }
        
        try await clientMessage(.otherCommand("PASS", [""]))
        let tag = IRCTags(key: "registrationPacket", value: value)
        try await clientMessage(.NICK(clientContext.nickname), tags: [tag])
        
        await transportState.transition(to: .transportRegistered(isActive: isActive, clientContext: clientContext))
    }
    
    func sendQuit(_ username: Username, deviceId: DeviceId) async throws {
        quiting = true
        let authObject = AuthPacket(
            ntkUser: NTKUser(
                username: username,
                deviceId: deviceId
            ),
            tempRegister: false
        )
        let packet = try BSONEncoder().encode(authObject).makeData()
        try await clientMessage(.QUIT(packet.base64EncodedString()))
    }
    
    @BlobActor
    func publishBlob(_ packet: String) async throws {
        try await blobMessage(.otherCommand("BLOBS", [packet]))
        try await RunLoop.run(20, sleep: 1) { @BlobActor [weak self] in
            guard let strongSelf = self else { return false }
            var running = true
            if await strongSelf.channelBlob != nil {
                running = false
            }
            return running
        }
    }
    
    func requestOfflineMessages() async throws {
        if !quiting {
            try await clientMessage(.otherCommand("OFFLINEMESSAGES", [""]))
        }
    }
    
    //I think we want a recipient to be an object representing NeedleTailChannel not the name of that channel. That way we can send the members with the channel.
    public func recipient(
        conversationType: ConversationType,
        deviceId: DeviceId?,
        name: String
    ) async throws -> IRCMessageRecipient {
        switch conversationType {
        case .groupMessage(_):
            guard let name = IRCChannelName(name) else { throw NeedleTailError.nilChannelName }
            return .channel(name)
        case .privateMessage:
            guard let validatedName = NeedleTailNick(name: name, deviceId: deviceId) else { throw NeedleTailError.nilNickName }
            return .nick(validatedName)
        }
    }
    
    func createNeedleTailChannel(
        name: String,
        admin: NeedleTailNick,
        organizers: Set<Username>,
        members: Set<Username>,
        permissions: IRCChannelMode
    ) async throws {
        let packet = NeedleTailChannelPacket(
            name: name,
            admin: admin,
            organizers: organizers,
            members: members,
            permissions: permissions
        )
        let data = try BSONEncoder().encode(packet).makeData()
        let tag = IRCTags(key: "channelPacket", value: data.base64EncodedString())
        guard let channelName = IRCChannelName(name) else { return }
        //Keys are Passwords for Channels
        let type = TransportMessageType.standard(.JOIN(channels: [channelName], keys: nil))
        try await transportMessage(type, tags: [tag])
    }
    
    func partNeedleTailChannel(
        name: String,
        admin: NeedleTailNick,
        organizers: Set<Username>,
        members: Set<Username>,
        permissions: IRCChannelMode,
        message: String,
        blobId: String?
    ) async throws {
        let packet = NeedleTailChannelPacket(
            name: name,
            admin: admin,
            organizers: organizers,
            members: members,
            permissions: permissions,
            destroy: true,
            partMessage: message,
            blobId: blobId
        )
        let data = try BSONEncoder().encode(packet).makeData()
        let tag = IRCTags(key: "channelPacket", value: data.base64EncodedString())
        guard let channelName = IRCChannelName(name) else { return }
        let type = TransportMessageType.standard(.PART(channels: [channelName]))
        try await transportMessage(type, tags: [tag])
    }
    
    
    func createPrivateMessage(
        messageId: String,
        pushType: PushType,
        message: RatchetedCypherMessage,
        toUser: NTKUser,
        fromUser: NTKUser,
        messageType: MessageType,
        conversationType: ConversationType,
        readReceipt: ReadReceipt?
    ) async throws {
#if (os(macOS) || os(iOS))
        try await withThrowingTaskGroup(of: Void.self) { group in
            
            //Multipart is about to happen we need to create transport messages for each device
            if await !NeedleTail.shared.chatJobQueue.jobDeque.isEmpty {
                group.addTask { [weak self] in
                    guard let self else { return }
                    //We need to configure the multipart message packet if we are going to need to do a multipart message
                    var jobs = try await NeedleTail.shared.chatJobQueue.checkForExistingJobs { [weak self] job in
                        guard let self else { return job }
                        let subtype = await self.parseFilename(job.multipartMessage.fileName)
                        
                        var message = ""
                        switch subtype {
                        case .text:
                            message = "You have a message you can download. Long press to download..."
                        case .audio:
                            message = "You have an audio message you can download. Long press to download..."
                        case .image:
                            message = "You have an image you can download. Long press to download..."
                        case .doc:
                            message = "You have a document you can download. Long press to download..."
                        default:
                            break
                        }
                        
                        try await processMultipartDumbnail(with: message, from: job)
                        return job
                    }
                    jobs.removeAll()
                }
                
                _ = try await group.next()
            }
            
            
            let dataCount = try BSONEncoder().encode(message).makeData().count
            // Need to make sure we are not sending if we are not actually multipart, if the job deque contains an item ready to be used it could be multipart
            if dataCount >= 10777216 {
                if await !transportJobQueue.jobDeque.isEmpty {
                    group.addTask { [weak self] in
                        guard let self else { return }
                        // In theory we should have only 1 message but just in case we queue messges to be sent. Theoretically each time this method is called our job should be synchronized with the data inside of this method the CTK gives us. if there is no data it means we did not send the message from the application, so we create basically a dummy job so we can send the message in the same logic flow without needing to recreate the message packet in different areas
                        var jobs = try await transportJobQueue.checkForExistingJobs { [weak self] job in
                            guard let self else { return nil }
                            return await self.configureMultipartMessagePacket(
                                job,
                                username: toUser.username.raw,
                                deviceId: toUser.deviceId
                            )
                        }
                        
                        guard let configuredMessage = jobs.popLast() else { return }
                        let packet = MessagePacket(
                            id: messageId,
                            pushType: pushType,
                            type: messageType,
                            createdAt: Date(),
                            sender: fromUser.deviceId,
                            recipient: toUser.deviceId,
                            message: message,
                            readReceipt: readReceipt,
                            multipartMessage: configuredMessage
                        )
                        
                        let encodedData = try BSONEncoder().encode(packet).makeData()

                        var packetCount = 0
                        let packets = encodedData.chunks(ofCount: 10777216)

                        for packet in packets {
                            packetCount += 1
                            try await multipartMessage(.otherCommand(
                                Constants.multipartMediaUpload.rawValue,
                                [
                                    String(packetCount),
                                    String(packets.map{$0}.count),
                                    packet.base64EncodedString()
                                ]
                            ), tags: nil)
                        }
                        
                        await transportJobQueue.transferTransportJobs()
                        await NeedleTail.shared.chatJobQueue.transferTransportJobs()
                    }
                }
            } else {
                group.addTask { [weak self] in
                    guard let self else { return }
                    let packet = MessagePacket(
                        id: messageId,
                        pushType: pushType,
                        type: messageType,
                        createdAt: Date(),
                        sender: fromUser.deviceId,
                        recipient: toUser.deviceId,
                        message: message,
                        readReceipt: readReceipt
                    )
                    
                    let encodedData = try BSONEncoder().encode(packet).makeData()
                    try await sendPrivateMessage(toUser: toUser, type: conversationType, data: encodedData)
                }
            }
        }
#endif
    }
    
    private func processMultipartDumbnail(with message: String, from job: ChatPacketJob) async throws {
#if (os(macOS) || os(iOS))
        // We check for the expected chat multipart job and do the following
        //1. Add the multipartMessage to the transport job
        //2. Send the message with the correct chat from the job queue
        //3. Throw away the job
        
        let new = await !transportJobQueue.newDeque.contains(where: { $0.fileName == job.multipartMessage.fileName })
        if await !transportJobQueue.jobDeque.contains(where: { $0.fileName == job.multipartMessage.fileName }) && new
        {
            await transportJobQueue.addJob(job.multipartMessage)
            
            if job.messageSubType != "video/*", job.messageSubType != "videoThumbnail/*" {
                var metadata = Document()
                
                if job.messageSubType == "image/*" {
                    if let thumbnailBinary = job.metadata["blob"] as? Binary {
                        metadata.append([
                            "blob": thumbnailBinary
                        ])
                    }
                }
                metadata.append([
                    "messageId": job.multipartMessage.id
                ])
                try await self.emitter?.sendMessage(
                    chat: job.chat,
                    type: job.type,
                    messageSubtype: job.messageSubType,
                    text: message,
                    metadata: metadata,
                    conversationType: job.conversationType,
                    sender: job.multipartMessage.sender
                )
            }
        }
#endif
    }
    
    
    private func sendPrivateMessage(toUser: NTKUser, type: ConversationType, data: Data) async throws {
        let ircUser = toUser.username.raw.replacingOccurrences(of: " ", with: "").lowercased()
        let recipient = try await self.recipient(conversationType: type, deviceId: toUser.deviceId, name: "\(ircUser)")
        let type = TransportMessageType.private(.PRIVMSG([recipient], data.base64EncodedString()))
        try await self.transportMessage(type)
    }
    
    func parseFilename(_ name: String) -> MessageSubType? {
        let components = name.components(separatedBy: "_")
        guard let subType = components.first?.dropLast(2) else { return nil }
        return MessageSubType(rawValue: String(subType))
    }
    
    func configureMultipartMessagePacket(_
                                         multipartMessagePacket: MultipartMessagePacket,
                                         username: String,
                                         deviceId: DeviceId
    ) async -> MultipartMessagePacket {
        var multipartMessagePacket = multipartMessagePacket
        multipartMessagePacket.recipient = NeedleTailNick(name: username, deviceId: deviceId)
        return multipartMessagePacket
    }
    
    func createReadReceiptMessage(
        pushType: PushType,
        toUser: NTKUser,
        messageType: MessageType,
        conversationType: ConversationType,
        readReceipt: ReadReceipt
    ) async throws {
        let packet = MessagePacket(
            id: UUID().uuidString,
            pushType: pushType,
            type: messageType,
            createdAt: Date(),
            sender: readReceipt.sender.deviceId,
            recipient: toUser.deviceId,
            message: nil,
            readReceipt: readReceipt
        )
        let encodedData = try BSONEncoder().encode(packet).makeData()
        let ircUser = toUser.username.raw.replacingOccurrences(of: " ", with: "").lowercased()
        let recipient = try await recipient(conversationType: conversationType, deviceId: toUser.deviceId, name: "\(ircUser)")
        let type = TransportMessageType.private(.PRIVMSG([recipient], encodedData.base64EncodedString()))
        try await transportMessage(type)
    }
    
    func createGroupMessage(
        messageId: String,
        pushType: PushType,
        message: RatchetedCypherMessage,
        channelName: String,
        toUser: NTKUser,
        fromUser: NTKUser,
        messageType: MessageType,
        conversationType: ConversationType,
        readReceipt: ReadReceipt?
    ) async throws {
        
        //We look up all device identities on the server and create the NeedleTailNick there
        let packet = MessagePacket(
            id: messageId,
            pushType: pushType,
            type: messageType,
            createdAt: Date(),
            sender: fromUser.deviceId,
            recipient: toUser.deviceId,
            message: message,
            readReceipt: readReceipt,
            channelName: channelName
        )
        let encodedData = try BSONEncoder().encode(packet).makeData()
        do {
            //Channel Recipient
            let recipient = try await recipient(conversationType: conversationType, deviceId: toUser.deviceId, name: channelName)
            let type = TransportMessageType.private(.PRIVMSG([recipient], encodedData.base64EncodedString()))
            try await transportMessage(type)
        } catch {
            logger.error("\(error)")
        }
    }
    
    /// The **CHILD DEVICE** sends this packet while setting the request identity until we hear back from the **Master Device** via a **QR Code**
    func sendDeviceRegistryRequest(_ masterNick: NeedleTailNick) async throws {
        let recipient = IRCMessageRecipient.nick(masterNick)
        let packet = MessagePacket(
            id: UUID().uuidString,
            pushType: .none,
            type: .requestRegistry,
            createdAt: Date(),
            sender: nil,
            recipient: nil,
            message: nil,
            readReceipt: .none,
            addDeviceType: .master
        )
        
        //Store UUID Temporarily
        self.registryRequestId = packet.id
        let encodedData = try BSONEncoder().encode(packet).makeData()
        let type = TransportMessageType.private(.PRIVMSG([recipient], encodedData.base64EncodedString()))
        try await transportMessage(type)
    }
    
    func sendChildDeviceConfig(_ masterNick: NeedleTailNick, config: UserDeviceConfig) async throws {
        let recipient = IRCMessageRecipient.nick(masterNick)
        let packet = MessagePacket(
            id: UUID().uuidString,
            pushType: .none,
            type: .requestRegistry,
            createdAt: Date(),
            sender: nil,
            recipient: nil,
            message: nil,
            readReceipt: .none,
            addDeviceType: .child,
            childDeviceConfig: config
        )
        
        //Store UUID Temporarily
        self.registryRequestId = packet.id
        let encodedData = try BSONEncoder().encode(packet).makeData()
        let type = TransportMessageType.private(.PRIVMSG([recipient], encodedData.base64EncodedString()))
        try await transportMessage(type)
    }
    
    /// Sends a ``NeedleTailNick`` to the server in order to update a users nick name
    /// - Parameter nick: A Nick
    func changeNick(_ nick: NeedleTailNick) async throws {
        let type = TransportMessageType.standard(.NICK(nick))
        try await transportMessage(type)
    }
    
    func deleteOfflineMessages(from contact: String) async throws {
        let type = TransportMessageType.standard(.otherCommand("DELETEOFFLINEMESSAGE", [contact]))
        try await transportMessage(type)
    }
    
    /// We send contact removal notifications to our self on the server and then route them to the other devices if they are online
    func notifyContactRemoved(_ ntkUser: NTKUser, removed contact: Username) async throws {
        let packet = MessagePacket(
            id: UUID().uuidString,
            pushType: .custom("contact-removed"),
            type: .notifyContactRemoval,
            createdAt: Date(),
            sender: ntkUser.deviceId,
            recipient: nil,
            message: nil,
            readReceipt: .none,
            contacts: [
                NTKContact(
                    username: contact,
                    nickname: contact.raw
                )
            ]
        )
        let encodedData = try BSONEncoder().encode(packet).makeData()
        let ircUser = ntkUser.username.raw.replacingOccurrences(of: " ", with: "").lowercased()
        // The recipient is ourself
        let recipient = try await recipient(conversationType: .privateMessage, deviceId: ntkUser.deviceId, name: "\(ircUser)")
        let type = TransportMessageType.private(.PRIVMSG([recipient], encodedData.base64EncodedString()))
        try await transportMessage(type)
    }
}

struct MultipartObject: Sendable, Codable {
    var partNumber: String
    var totalParts: String
    var data: Data
}
