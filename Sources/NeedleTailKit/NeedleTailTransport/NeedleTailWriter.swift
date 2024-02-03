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
import SwiftDTF
import Crypto
import NIOCore
import Logging

#if (os(macOS) || os(iOS))

actor NeedleTailWriter: NeedleTailClientDelegate {
    
    let asyncChannel: NIOAsyncChannel<ByteBuffer, ByteBuffer>
    let writer: NIOAsyncChannelOutboundWriter<ByteBuffer>
    let transportState: TransportState
    let clientContext: ClientContext
    let origin: String
    let logger = Logger(label: "NeedleTailWriter")
    var quiting = false
    var channelBlob: String?
    var registryRequestId = ""
    
    init(asyncChannel: NIOAsyncChannel<ByteBuffer, ByteBuffer>, writer: NIOAsyncChannelOutboundWriter<ByteBuffer>, transportState: TransportState, clientContext: ClientContext) throws {
        self.asyncChannel = asyncChannel
        self.writer = writer
        self.transportState = transportState
        self.clientContext = clientContext
        self.origin = try BSONEncoder().encodeString(clientContext.nickname)
    }
    
    /// This is where we register the transport session
    /// - Parameter regPacket: Our Registration Packet
    public func registerNeedletailSession(_ regPacket: Data, _ temp: Bool = false) async throws {
        await transportState.transition(to: .transportRegistering(clientContext: clientContext))
        guard case .transportRegistering(let clientContext) = await transportState.current else { throw NeedleTailError.transportationStateError }
        let value = regPacket.base64EncodedString()
        guard temp == false else {
            let tag = IRCTags(key: "tempRegPacket", value: value)
            try await self.transportMessage(
                writer,
                origin: self.origin,
                type: .standard(.NICK(clientContext.nickname)),
                tags: [tag]
            )
            return
        }
        
        try await self.transportMessage(
            writer,
            origin: self.origin,
            type: .standard(.otherCommand("PASS", [""]))
        )

        let tag = IRCTags(key: "registrationPacket", value: value)
        try await transportMessage(
            writer,
            origin: self.origin,
            type: .standard(.NICK(clientContext.nickname)),
            tags: [tag]
        )
    }
    
    func setQuiting(_ quiting: Bool) async {
        self.quiting = quiting
    }
    
    func sendQuit(_ username: Username, deviceId: DeviceId) async throws {
        logger.info("Sending Quit Message")
        await setQuiting(true)
        
        let authObject = AuthPacket(
            ntkUser: NTKUser(
                username: username,
                deviceId: deviceId
            ),
            tempRegister: false
        )
        let encodedString = try BSONEncoder().encodeString(authObject)
        try await self.transportMessage(type: .standard(.QUIT(encodedString)))
    }
    
    func publishBlob(_ packet: String) async throws {
        
        try await self.transportMessage(
            writer,
            origin: self.origin,
            type: .standard(.otherCommand("BLOBS", [packet]))
        )
        
        //TODO: AVOID LOOP
        try await RunLoop.run(20, sleep: 1) { [weak self] in
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
            try await self.transportMessage(type: .standard(.otherCommand(Constants.offlineMessages.rawValue, [""])))
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
        let encodedString = try BSONEncoder().encodeString(packet)
        let tag = IRCTags(key: "channelPacket", value: encodedString)
        guard let channelName = IRCChannelName(name) else { return }
        //Keys are Passwords for Channels
        let type = TransportMessageType.standard(.JOIN(channels: [channelName], keys: nil))
        
        try await self.transportMessage(
            writer,
            origin: self.origin,
            type: type,
            tags: [tag]
        )
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
        let encodedString = try BSONEncoder().encodeString(packet)
        let tag = IRCTags(key: "channelPacket", value: encodedString)
        guard let channelName = IRCChannelName(name) else { return }
        let type = TransportMessageType.standard(.PART(channels: [channelName]))
        
        try await self.transportMessage(
            writer,
            origin: self.origin,
            type: type,
            tags: [tag]
        )
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
        // Need to make sure we are not sending if we are not actually multipart, if the job deque contains an item ready to be used it could be multipart
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
        
        let encodedData = try BSONEncoder().encodeData(packet)
        try await sendPrivateMessage(toUser: toUser, type: conversationType, data: encodedData)
#endif
    }
    
    
    private func sendPrivateMessage(toUser: NTKUser, type: ConversationType, data: Data) async throws {
        let ircUser = toUser.username.raw.replacingOccurrences(of: " ", with: "").lowercased()
        let recipient = try await self.recipient(conversationType: type, deviceId: toUser.deviceId, name: "\(ircUser)")
        let type = TransportMessageType.private(.PRIVMSG([recipient], data.base64EncodedString()))
        try await self.transportMessage(type: type)
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
        let encodedString = try BSONEncoder().encodeString(packet)
        let ircUser = toUser.username.raw.replacingOccurrences(of: " ", with: "").lowercased()
        let recipient = try await self.recipient(conversationType: conversationType, deviceId: toUser.deviceId, name: "\(ircUser)")
        let type = TransportMessageType.private(.PRIVMSG([recipient], encodedString))
        try await self.transportMessage(type: type)
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
        let encodedString = try BSONEncoder().encodeString(packet)
        do {
            //Channel Recipient
            let recipient = try await self.recipient(conversationType: conversationType, deviceId: toUser.deviceId, name: channelName)
            let type = TransportMessageType.private(.PRIVMSG([recipient], encodedString))
            try await self.transportMessage(type: type)
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
        
        let encodedString = try BSONEncoder().encodeString(packet)
        let type = TransportMessageType.private(.PRIVMSG([recipient], encodedString))
        try await self.transportMessage(type: type)
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
        let encodedString = try BSONEncoder().encodeString(packet)
        let type = TransportMessageType.private(.PRIVMSG([recipient], encodedString))
        try await self.transportMessage(type: type)
    }
    
    /// Sends a ``NeedleTailNick`` to the server in order to update a users nick name
    /// - Parameter nick: A Nick
    func changeNick(_ nick: NeedleTailNick) async throws {
        let type = TransportMessageType.standard(.NICK(nick))
        try await self.transportMessage(type: type)
    }
    
    func deleteOfflineMessages(from contact: String) async throws {
        let type = TransportMessageType.standard(.otherCommand("DELETEOFFLINEMESSAGE", [contact]))
        try await self.transportMessage(type: type)
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
        let encodedString = try BSONEncoder().encodeString(packet)
        let ircUser = ntkUser.username.raw.replacingOccurrences(of: " ", with: "").lowercased()
        // The recipient is ourself
        let recipient = try await self.recipient(conversationType: .privateMessage, deviceId: ntkUser.deviceId, name: "\(ircUser)")
        let type = TransportMessageType.private(.PRIVMSG([recipient], encodedString))
        
        try await self.transportMessage(type: type)
    }
    
    func transportMessage(type: TransportMessageType) async throws {
        try await transportMessage(
            self.writer,
            origin: self.origin,
            type: type
        )
    }
    
    func requestOnlineNicks(_ nicks: [NeedleTailNick]) async throws {
        let type = TransportMessageType.private(.ISON(nicks))
        print("SENDING REQUEST", type)
        try await self.transportMessage(type: type)
    }
}

struct MultipartObject: Sendable, Codable {
    var partNumber: String
    var totalParts: String
    var data: Data
}
#endif
