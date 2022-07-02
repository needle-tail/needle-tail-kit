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

extension NeedleTailTransportClient {
    
    /// This method is how all client messages get sent through the client to the server. This is the where they leave the Client.
    /// - Parameters:
    ///   - message: Our IRCMessage
    ///   - chatDoc: Not needed/used for clients and shouldn't be.
    func sendAndFlushMessage(_ message: IRCMessage, chatDoc: ChatDocument?) async {
        do {
            print("Sent message \(message)")
            try await channel?.writeAndFlush(message)
        } catch {
            logger.error("\(error)")
        }
    }
    
    /// This is where we register the transport session
    /// - Parameter regPacket: Our Registration Packet
    @NeedleTailTransportActor
    func registerNeedletailSession(_ regPacket: String?) async {
        guard let channel = channel else { return }
        transportState.transition(to: .registering(
            channel: channel,
            nick: clientContext.nickname,
            userInfo: clientContext.userInfo))
        
        guard case .registering(_, let nick, _) = transportState.current else {
            assertionFailure("called \(#function) but we are not connecting?")
            return
        }
        
        await createNeedleTailMessage(.otherCommand("PASS", [ clientInfo.password ]))
        
        if let regPacket = regPacket {
            let tag = IRCTags(key: "registrationPacket", value: regPacket)
            await createNeedleTailMessage(.NICK(nick), tags: [tag])
        } else {
            
            await createNeedleTailMessage(.NICK(nick))
        }
    }
    
    //I think we want a recipient to be an object representing NeedleTailChannel not the name of that channel. That way we can send the members with the channel.
    public func recipient(conversationType: ConversationType, deviceId: DeviceId?, name: String) async throws -> IRCMessageRecipient {
        switch conversationType {
        case .needleTailChannel, .groupMessage(_):
            guard let name = IRCChannelName(name) else { throw NeedleTailError.nilChannelName }
            //            guard let validatedName = NeedleTailNick(deviceId: deviceId, name: name) else { throw NeedleTailError.nilNickName }
            return .channel(name)
        case .privateMessage:
            guard let validatedName = NeedleTailNick(deviceId: deviceId, name: name) else { throw NeedleTailError.nilNickName }
            return .nickname(validatedName)
        }
    }
    
    @BlobActor
    func publishBlob(_ packet: String) async throws {
        await sendBlobs(.otherCommand("BLOBS", [packet]))
        let date = RunLoop.timeInterval(10)
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
        guard let channel = IRCChannelName(name) else { return }
        //Keys are Passwords for Channels
        await createNeedleTailMessage(.JOIN(channels: [channel], keys: nil), tags: [tag])
    }
    
    
    func partNeedleTailChannel(
        name: String,
        admin: NeedleTailNick,
        organizers: Set<Username>,
        members: Set<Username>,
        permissions: IRCChannelMode,
        message: String
    ) async throws {
        let packet = NeedleTailChannelPacket(
            name: name,
            admin: admin,
            organizers: organizers,
            members: members,
            permissions: permissions,
            destroy: true,
            partMessage: message
        )
        let data = try BSONEncoder().encode(packet).makeData().base64EncodedString()
        let tag = IRCTags(key: "channelPacket", value: data)
        guard let channel = IRCChannelName(name) else { return }
        await createNeedleTailMessage(.PART(channels: [channel]), tags: [tag])
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
        
        let data = try BSONEncoder().encode(packet).makeData()
        do {
            let ircUser = toUser.raw.replacingOccurrences(of: " ", with: "").lowercased()
            let recipient = try await recipient(conversationType: conversationType, deviceId: toDevice, name: "\(ircUser)")
            await sendPrivateMessage(data, to: recipient, tags: nil)
        } catch {
            logger.error("\(error)")
        }
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
        
        let data = try BSONEncoder().encode(packet).makeData()
        do {
            //Channel Recipient
            let recipient = try await recipient(conversationType: conversationType, deviceId: toDevice, name: channelName)
            await sendPrivateMessage(data, to: recipient, tags: nil)
        } catch {
            logger.error("\(error)")
        }
    }
    
    
    // 1. We want to tell the master device that we want to register
    public func sendDeviceRegistryRequest(_ masterNick: NeedleTailNick, childNick: NeedleTailNick) async throws {
        let recipient = IRCMessageRecipient.nickname(masterNick)
        let child = try BSONEncoder().encode(childNick).makeData().base64EncodedString()
        let packet = MessagePacket(
            id: UUID().uuidString,
            pushType: .none,
            type: .requestRegistry(child),
            createdAt: Date(),
            sender: childNick.deviceId,
            recipient: nil,
            message: nil,
            readReceipt: .none
        )
        let message = try BSONEncoder().encode(packet).makeData().base64EncodedString()
        await sendIRCMessage(message, to: recipient, tags: nil)
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
        let message = try BSONEncoder().encode(packet).makeData().base64EncodedString()
        await sendIRCMessage(message, to: recipient, tags: nil)
    }
    
    /// Request from the server a users key bundle
    /// - Parameter packet: Our Authentication Packet
    @NeedleTailTransportActor
    func readKeyBundle(_ packet: String) async -> UserConfig? {
        await sendKeyBundleRequest(.otherCommand("READKEYBNDL", [packet]))
        let date = RunLoop.timeInterval(10)
        var canRun = false
        repeat {
            canRun = true
            if userConfig != nil {
                canRun = false
            }
            /// We just want to run a loop until the userConfig contains a value or stop on the timeout
        } while await RunLoop.execute(date, ack: acknowledgment, canRun: canRun)
        return userConfig
    }
    
    /// Sends a ``NeedleTailNick`` to the server in order to update a users nick name
    /// - Parameter nick: A Nick
    func changeNick(_ nick: NeedleTailNick) async {
        await createNeedleTailMessage(.NICK(nick))
    }
    
    func sendPrivateMessage(_ message: Data, to recipient: IRCMessageRecipient, tags: [IRCTags]? = nil) async {
        await sendIRCMessage(message.base64EncodedString(), to: recipient, tags: tags)
    }
}
