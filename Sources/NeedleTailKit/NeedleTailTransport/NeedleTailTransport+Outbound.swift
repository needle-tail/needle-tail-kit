//
//  NeedleTailTransportClient+Outbound.swift
//
//
//  Created by Cole M on 4/29/22.
//


import NeedleTailHelpers
import CypherMessaging
@_spi(AsyncChannel) import NeedleTailProtocol
import Algorithms
import DequeModule
import SwiftDTF
import Crypto
@_spi(AsyncChannel) import NIOCore

#if (os(macOS) || os(iOS))
@NeedleTailTransportActor
extension NeedleTailTransport {
    
    /// This is where we register the transport session
    /// - Parameter regPacket: Our Registration Packet
    @_spi(AsyncChannel)
    public func registerNeedletailSession(_ regPacket: Data, _ temp: Bool = false) async throws {
        let isActive = asyncChannel.channel.isActive
        await transportState.transition(to:
                .transportRegistering(
                    isActive: isActive,
                    clientContext: clientContext
                )
        )
        
        guard case .transportRegistering(_, let clientContext) = transportState.current else { throw NeedleTailError.transportationStateError }
        let value = regPacket.base64EncodedString()
        let writer = asyncChannel.outboundWriter
        guard temp == false else {
            try await ThrowingTaskGroup<Void, Error>.executeChildTask { [weak self] in
                guard let self else { return }
                let tag = IRCTags(key: "tempRegPacket", value: value)
                try await self.transportMessage(
                    writer,
                    origin: self.origin ?? "",
                    type: .standard(.NICK(clientContext.nickname)),
                    tags: [tag]
                )
            }
            return
        }
        
        try await withThrowingTaskGroup(of: Void.self, body: { group in
            try Task.checkCancellation()
            group.addTask { [weak self] in
                guard let self else { return }
                try await self.transportMessage(
                    writer,
                    origin: self.origin ?? "",
                    type: .standard(.otherCommand("PASS", [""]))
                )
            }
            _  = try await group.next()
            group.addTask { [weak self] in
                guard let self else { return }
                let tag = IRCTags(key: "registrationPacket", value: value)
                try await transportMessage(
                    writer,
                    origin: self.origin ?? "",
                    type: .standard(.NICK(clientContext.nickname)),
                    tags: [tag]
                )
            }
            _  = try await group.next()
            group.addTask { [weak self] in
                guard let self else { return }
                await self.transportState.transition(to: .transportRegistered(isActive: isActive, clientContext: clientContext))
            }
            _  = try await group.next()
            group.cancelAll()
        })
    }
    
    func sendQuit(_ username: Username, deviceId: DeviceId) async throws {
        quiting = true
        try await ThrowingTaskGroup<Void, Error>.executeChildTask { [weak self] in
            guard let self else { return }
            let writer = await self.asyncChannel.outboundWriter
            let authObject = AuthPacket(
                ntkUser: NTKUser(
                    username: username,
                    deviceId: deviceId
                ),
                tempRegister: false
            )
            let packet = try BSONEncoder().encode(authObject).makeData()
            try await self.transportMessage(
                writer,
                origin: self.origin ?? "",
                type: .standard(.QUIT(packet.base64EncodedString()))
            )
        }
    }
    
    func publishBlob(_ packet: String) async throws {
        try await ThrowingTaskGroup<Void, Error>.executeChildTask { [weak self] in
            guard let self else { return }
            let writer = await self.asyncChannel.outboundWriter
            try await self.transportMessage(
                writer,
                origin: self.origin ?? "",
                type: .standard(.otherCommand("BLOBS", [packet]))
            )
            try await RunLoop.run(20, sleep: 1) { @BlobActor [weak self] in
                guard let strongSelf = self else { return false }
                var running = true
                if await strongSelf.channelBlob != nil {
                    running = false
                }
                return running
            }
        }
    }
    
    func requestOfflineMessages() async throws {
        if !quiting {
            
            try await ThrowingTaskGroup<Void, Error>.executeChildTask { [weak self] in
                guard let self else { return }
                let writer = await self.asyncChannel.outboundWriter
                try await self.transportMessage(
                    writer,
                    origin: self.origin ?? "",
                    type: .standard(.otherCommand(Constants.offlineMessages.rawValue, [""]))
                )
            }
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
        try await ThrowingTaskGroup<Void, Error>.executeChildTask { [weak self] in
            guard let self else { return }
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
            let writer = await self.asyncChannel.outboundWriter
            try await self.transportMessage(
                writer,
                origin: self.origin ?? "",
                type: type,
                tags: [tag]
            )
        }
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
        try await ThrowingTaskGroup<Void, Error>.executeChildTask { [weak self] in
            guard let self else { return }
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
            let writer = await self.asyncChannel.outboundWriter
            try await self.transportMessage(
                writer,
                origin: self.origin ?? "",
                type: type,
                tags: [tag]
            )
        }
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
            try Task.checkCancellation()
            // Need to make sure we are not sending if we are not actually multipart, if the job deque contains an item ready to be used it could be multipart
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
#endif
    }
    
    
    private func sendPrivateMessage(toUser: NTKUser, type: ConversationType, data: Data) async throws {
        try await ThrowingTaskGroup<Void, Error>.executeChildTask { [weak self] in
            guard let self else { return }
            let ircUser = toUser.username.raw.replacingOccurrences(of: " ", with: "").lowercased()
            let recipient = try await self.recipient(conversationType: type, deviceId: toUser.deviceId, name: "\(ircUser)")
            let type = TransportMessageType.private(.PRIVMSG([recipient], data.base64EncodedString()))
            let writer = await self.asyncChannel.outboundWriter
            try await self.transportMessage(
                writer,
                origin: self.origin ?? "",
                type: type
            )
        }
    }
    
    func parseFilename(_ name: String) -> MessageSubType? {
        let components = name.components(separatedBy: "_")
        guard let subType = components.first?.dropLast(2) else { return nil }
        return MessageSubType(rawValue: String(subType))
    }

    func createReadReceiptMessage(
        pushType: PushType,
        toUser: NTKUser,
        messageType: MessageType,
        conversationType: ConversationType,
        readReceipt: ReadReceipt
    ) async throws {
        try await ThrowingTaskGroup<Void, Error>.executeChildTask { [weak self] in
            guard let self else { return }
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
            let recipient = try await self.recipient(conversationType: conversationType, deviceId: toUser.deviceId, name: "\(ircUser)")
            let type = TransportMessageType.private(.PRIVMSG([recipient], encodedData.base64EncodedString()))
            let writer = await self.asyncChannel.outboundWriter
            try await self.transportMessage(
                writer,
                origin: self.origin ?? "",
                type: type
            )
        }
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
        try await ThrowingTaskGroup<Void, Error>.executeChildTask { [weak self] in
            guard let self else { return }
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
                let recipient = try await self.recipient(conversationType: conversationType, deviceId: toUser.deviceId, name: channelName)
                let type = TransportMessageType.private(.PRIVMSG([recipient], encodedData.base64EncodedString()))
                let writer = await self.asyncChannel.outboundWriter
                try await self.transportMessage(
                    writer,
                    type: type
                )
            } catch {
                logger.error("\(error)")
            }
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
        
        try await ThrowingTaskGroup<Void, Error>.executeChildTask { [weak self] in
            guard let self else { return }
            let encodedData = try BSONEncoder().encode(packet).makeData()
            let type = TransportMessageType.private(.PRIVMSG([recipient], encodedData.base64EncodedString()))
            let writer = await self.asyncChannel.outboundWriter
            try await transportMessage(
                writer,
                origin: self.origin ?? "",
                type: type
            )
        }
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
        try await ThrowingTaskGroup<Void, Error>.executeChildTask { [weak self] in
            guard let self else { return }
            let encodedData = try BSONEncoder().encode(packet).makeData()
            let type = TransportMessageType.private(.PRIVMSG([recipient], encodedData.base64EncodedString()))
            let writer = await self.asyncChannel.outboundWriter
            try await transportMessage(
                writer,
                origin: self.origin ?? "",
                type: type
            )
        }
    }
    
    /// Sends a ``NeedleTailNick`` to the server in order to update a users nick name
    /// - Parameter nick: A Nick
    func changeNick(_ nick: NeedleTailNick) async throws {
        try await ThrowingTaskGroup<Void, Error>.executeChildTask { [weak self] in
            guard let self else { return }
            let type = TransportMessageType.standard(.NICK(nick))
            let writer = await self.asyncChannel.outboundWriter
            try await transportMessage(
                writer,
                origin: self.origin ?? "",
                type: type
            )
        }
    }
    
    func deleteOfflineMessages(from contact: String) async throws {
        try await ThrowingTaskGroup<Void, Error>.executeChildTask { [weak self] in
            guard let self else { return }
            let type = TransportMessageType.standard(.otherCommand("DELETEOFFLINEMESSAGE", [contact]))
            let writer = await self.asyncChannel.outboundWriter
            try await transportMessage(
                writer,
                origin: self.origin ?? "",
                type: type
            )
        }
    }
    
    /// We send contact removal notifications to our self on the server and then route them to the other devices if they are online
    func notifyContactRemoved(_ ntkUser: NTKUser, removed contact: Username) async throws {
        try await ThrowingTaskGroup<Void, Error>.executeChildTask { [weak self] in
            guard let self else { return }
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
            let recipient = try await self.recipient(conversationType: .privateMessage, deviceId: ntkUser.deviceId, name: "\(ircUser)")
            let type = TransportMessageType.private(.PRIVMSG([recipient], encodedData.base64EncodedString()))
            let writer = await self.asyncChannel.outboundWriter
            try await self.transportMessage(
                writer,
                origin: self.origin ?? "",
                type: type
            )
        }
    }
}

struct MultipartObject: Sendable, Codable {
    var partNumber: String
    var totalParts: String
    var data: Data
}
#endif

extension ThrowingTaskGroup {
    
    static func executeChildTask(work: @Sendable @escaping () async throws -> Void) async throws {
        try await withThrowingTaskGroup(of: Void.self, body: { group in
            try Task.checkCancellation()
            group.addTask {
                try await work()
            }
            _ = try await group.next()
            group.cancelAll()
        })
    }
    
}
