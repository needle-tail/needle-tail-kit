//
//  NeedleTailTransportClient+Outbound.swift
//  
//
//  Created by Cole M on 4/29/22.
//

import Foundation
import NeedleTailHelpers
import CypherMessaging
import NeedleTailProtocol

extension NeedleTailTransport {
    
    /// This is where we register the transport session
    /// - Parameter regPacket: Our Registration Packet
    @NeedleTailClientActor
    func registerNeedletailSession(_ regPacket: Data, _ temp: Bool = false) async throws {
        await messenger.clientServerState = .clientRegistering
        guard let channel = channel else { return }
        await transportState.transition(to: .transportRegistering(
            channel: channel,
            nick: clientContext.nickname,
            userInfo: clientContext.userInfo))
        
        guard case .transportRegistering(_, let nick, _) = await transportState.current else { return }
        let value = regPacket.base64EncodedString()
        guard temp == false else {
            let tag = IRCTags(key: "tempRegPacket", value: value)
            try await clientMessage(channel, command:  .NICK(nick), tags: [tag])
            return
        }
        
        try await clientMessage(channel, command: .otherCommand("PASS", [""]))
        let tag = IRCTags(key: "registrationPacket", value: value)
        try await clientMessage(channel, command: .NICK(nick), tags: [tag])
    }
    
    func sendQuit(_ username: Username, deviceId: DeviceId) async throws {
        guard let channel = await channel else { return }
        let authObject = AuthPacket(
            username: username,
            deviceId: deviceId,
            tempRegister: false
        )
        let packet = try BSONEncoder().encode(authObject).makeData()
        try await clientMessage(channel, command: .QUIT(packet.base64EncodedString()))
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
    
    @BlobActor
    func publishBlob(_ packet: String) async throws {
        guard let channel = await channel else { return }
        try await blobMessage(channel, command: .otherCommand("BLOBS", [packet]))
        try await RunLoop.run(240, sleep: 1) {
            var running = true
            if await channelBlob != nil {
                running = false
            }
            return running
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
        guard let channel = await channel else { return }
        //Keys are Passwords for Channels
        let type = TransportMessageType.standard(.JOIN(channels: [channelName], keys: nil))
        try await transportMessage(channel, type: type, tags: [tag])
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
        guard let channel = await channel else { return }
        let type = TransportMessageType.standard(.PART(channels: [channelName]))
        try await transportMessage(channel, type: type, tags: [tag])
    }
    
    func createPrivateMessage(
        messageId: String,
        pushType: PushType,
        message: RatchetedCypherMessage,
        fromDevice: DeviceId,
        toUser: Username,
        toDevice: DeviceId,
        messageType: MessageType,
        conversationType: ConversationType,
        readReceipt: ReadReceiptPacket?
    ) async throws {
        let packet = MessagePacket(
            id: messageId,
            pushType: pushType,
            type: messageType,
            createdAt: Date(),
            sender: fromDevice,
            recipient: toDevice,
            message: message,
            readReceipt: readReceipt
        )
        
        let encodedData = try BSONEncoder().encode(packet).makeData()
        let ircUser = toUser.raw.replacingOccurrences(of: " ", with: "").lowercased()
        let recipient = try await recipient(conversationType: conversationType, deviceId: toDevice, name: "\(ircUser)")
        let type = TransportMessageType.private(.PRIVMSG([recipient], encodedData.base64EncodedString()))
        guard let channel = await channel else { return }
        try await transportMessage(channel, type: type)
    }
    
    func createGroupMessage(
        messageId: String,
        pushType: PushType,
        message: RatchetedCypherMessage,
        channelName: String,
        fromDevice: DeviceId,
        toUser: Username,
        toDevice: DeviceId,
        messageType: MessageType,
        conversationType: ConversationType,
        readReceipt: ReadReceiptPacket?
    ) async throws {
        
        //We look up all device identities on the server and create the NeedleTailNick there
        let packet = MessagePacket(
            id: messageId,
            pushType: pushType,
            type: messageType,
            createdAt: Date(),
            sender: fromDevice,
            recipient: toDevice,
            message: message,
            readReceipt: readReceipt,
            channelName: channelName
        )
        
        let encodedData = try BSONEncoder().encode(packet).makeData()
        do {
            //Channel Recipient
            let recipient = try await recipient(conversationType: conversationType, deviceId: toDevice, name: channelName)
            let type = TransportMessageType.private(.PRIVMSG([recipient], encodedData.base64EncodedString()))
            guard let channel = await channel else { return }
            try await transportMessage(channel, type: type)
        } catch {
            logger.error("\(error)")
        }
    }
    
    //The requesting device sends this packet while setting the request identity until we hear back from the master device via a QR Code
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
            readReceipt: .none
        )
        
        //Store UUID Temporarily
        self.registryRequestId = packet.id
        
        let encodedData = try BSONEncoder().encode(packet).makeData()
        let type = TransportMessageType.private(.PRIVMSG([recipient], encodedData.base64EncodedString()))
        guard let channel = await channel else { return }
        try await transportMessage(channel, type: type)
    }
    
    /// Request from the server a users key bundle
    /// - Parameter packet: Our Authentication Packet
    @NeedleTailClientActor
    func readKeyBundle(_ packet: String) async throws -> UserConfig? {
        guard let channel = channel else { return nil }
        try await clientMessage(channel, command: .otherCommand("READKEYBNDL", [packet]))
        try await RunLoop.run(10, sleep: 1, stopRunning: {
            var running = true
            if userConfig != nil {
                running = false
            }
            return running
        })
        return userConfig
    }
    
    /// Sends a ``NeedleTailNick`` to the server in order to update a users nick name
    /// - Parameter nick: A Nick
    func changeNick(_ nick: NeedleTailNick) async throws {
        let type = TransportMessageType.standard(.NICK(nick))
        guard let channel = await channel else { return }
        try await transportMessage(channel, type: type)
    }
}
