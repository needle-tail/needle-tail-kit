//
//  NeedleTailTransportClient+Outbound.swift
//  
//
//  Created by Cole M on 4/29/22.
//

import Foundation
import NeedleTailHelpers
import CypherMessaging
import AsyncIRC

extension NeedleTailTransport {

    /// This is where we register the transport session
    /// - Parameter regPacket: Our Registration Packet
    @NeedleTailClientActor
    func registerNeedletailSession(_ regPacket: String?) async throws {
        guard let channel = channel else { return }
        await transportState.transition(to: .registering(
            channel: channel,
            nick: clientContext.nickname,
            userInfo: clientContext.userInfo))
        
        guard case .registering(_, let nick, _) = await transportState.current else {
            assertionFailure("called \(#function) but we are not connecting?")
            return
        }
        
        try await clientMessage(channel, command: .otherCommand("PASS", [ clientInfo.password ]))
        
        if let regPacket = regPacket {
            let tag = IRCTags(key: "registrationPacket", value: regPacket)
            try await clientMessage(channel, command:  .NICK(nick), tags: [tag])
        } else {
            try await clientMessage(channel, command: .NICK(nick))
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
            //            guard let validatedName = NeedleTailNick(deviceId: deviceId, name: name) else { throw NeedleTailError.nilNickName }
            return .channel(name)
        case .privateMessage:
            guard let validatedName = NeedleTailNick(name: name, deviceId: deviceId) else { throw NeedleTailError.nilNickName }
            return .nickname(validatedName)
        }
    }
    
    @BlobActor
    func publishBlob(_ packet: String) async throws {
        guard let channel = await channel else { return }
        try await blobMessage(channel, command: .otherCommand("BLOBS", [packet]))
        let date = RunLoop.timeInterval(1)
        var canRun = false
        repeat {
            canRun = true
            if await channelBlob != nil {
                canRun = false
            }
            /// We just want to run a loop until the channelBlob contains a value or stop on the timeout
        } while await RunLoop.execute(date, canRun: canRun)
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
        let data = try BSONEncoder().encode(packet).makeData().base64EncodedString()
        let tag = IRCTags(key: "channelPacket", value: data)
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
        let data = try BSONEncoder().encode(packet).makeData().base64EncodedString()
        let tag = IRCTags(key: "channelPacket", value: data)
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
        readReceipt: ReadReceiptPacket
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
        
            let encodedString = try BSONEncoder().encode(packet).makeData().base64EncodedString()
            let ircUser = toUser.raw.replacingOccurrences(of: " ", with: "").lowercased()
            let recipient = try await recipient(conversationType: conversationType, deviceId: toDevice, name: "\(ircUser)")
            let type = TransportMessageType.private(.PRIVMSG([recipient], encodedString))
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
        readReceipt: ReadReceiptPacket
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
        
        let encodedString = try BSONEncoder().encode(packet).makeData().base64EncodedString()
        do {
            //Channel Recipient
            let recipient = try await recipient(conversationType: conversationType, deviceId: toDevice, name: channelName)
            let type = TransportMessageType.private(.PRIVMSG([recipient], encodedString))
            guard let channel = await channel else { return }
            try await transportMessage(channel, type: type)
        } catch {
            logger.error("\(error)")
        }
    }

    
    func sendDeviceRegistryRequest(_ masterNick: NeedleTailNick) async throws {
        let recipient = IRCMessageRecipient.nickname(masterNick)
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
        let encodedString = try BSONEncoder().encode(packet).makeData().base64EncodedString()
        let type = TransportMessageType.private(.PRIVMSG([recipient], encodedString))
        guard let channel = await channel else { return }
        try await transportMessage(channel, type: type)
    }
    
    
    // 4.
    func sendFinishRegistryMessage(toMaster
                                   deviceConfig: UserDeviceConfig,
                                   nick: NeedleTailNick
    ) async throws {
        //1. Get Recipient Which should be ourself that we sent from the server
        let recipient = IRCMessageRecipient.nickname(nick)
        let config = try BSONEncoder().encode(deviceConfig).makeData().base64EncodedString()
        //2. Create Packet with the deviceConfig we genereated for ourself
        let packet = MessagePacket(
            id: UUID().uuidString,
            pushType: .none,
            type: .newDevice(config),
            createdAt: Date(),
            sender: nil,
            recipient: nil,
            message: nil,
            readReceipt: .none
        )
        //3. Send our deviceConfig to the registered online master device which should be the recipient we generate from the nick since the nick is the same account as the device we are trying to register and should be the only online device. If we have another device online we will have to filter it by master device on the server.
        let encodedString = try BSONEncoder().encode(packet).makeData().base64EncodedString()
        let type = TransportMessageType.private(.PRIVMSG([recipient], encodedString))
        guard let channel = await channel else { return }
        try await transportMessage(channel, type: type)
    }
    
    /// Request from the server a users key bundle
    /// - Parameter packet: Our Authentication Packet
    @NeedleTailClientActor
    func readKeyBundle(_ packet: String) async throws -> UserConfig? {
        guard let channel = channel else { return nil }
        try await clientMessage(channel, command: .otherCommand("READKEYBNDL", [packet]))
        let date = RunLoop.timeInterval(10)
        var canRun = false
        repeat {
            canRun = true
            if userConfig != nil {
                canRun = false
            }
            /// We just want to run a loop until the userConfig contains a value or stop on the timeout
        } while await RunLoop.execute(date, canRun: canRun)
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
