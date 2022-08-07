//
//  IRCClient+Inbound.swift
//  
//
//  Created by Cole M on 4/29/22.
//

import Foundation
import CypherMessaging
import BSON
import NeedleTailHelpers
import NeedleTailProtocol

#if canImport(SwiftUI) && canImport(Combine) && (os(macOS) || os(iOS))
extension NeedleTailTransport {
     func doNotice(recipients: [IRCMessageRecipient], message: String) async throws {
        await respondToTransportState()
    }
}
#endif

extension NeedleTailTransport {
    
    @NeedleTailClientActor
     func doReadKeyBundle(_ keyBundle: [String]) async throws {
        guard let keyBundle = keyBundle.first else { return }
        guard let data = Data(base64Encoded: keyBundle) else { return }
        let buffer = ByteBuffer(data: data)
        let config = try BSONDecoder().decode(UserConfig.self, from: Document(buffer: buffer))
        self.userConfig = config
    }
    

    // We receive the messageId via a QRCode from the requesting device we will emmit this id to the masters client in order to generate an approval QRCode.
    func receivedRegistryRequest(_ messageId: String) async throws {
#if (os(macOS) || os(iOS))
        messenger.plugin.emitter.received = messageId
#endif
        }
    
    // If the approval code matches the code that the requesting device temporarily store then let the requesting client know that the master devices has approved of the registration of this device.
    func computeApproval(_ code: String) async -> Bool {
        if self.registryRequestId == code {
            self.registryRequestId = ""
        }
        return true
    }
    
    // This method is called on the Dispatcher, After the master device adds the new Device locally and then sends it to the server to be saved
    func receivedNewDevice(_ deviceState: NewDeviceState) async {
#if (os(macOS) || os(iOS))
        messenger.plugin.emitter.qrCodeData = nil
#endif
        self.receivedNewDeviceAdded = deviceState
    }
    
    private func sendMessageTypePacket(_ type: MessageType, nick: NeedleTailNick) async throws {
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
        guard let channel = await channel else { return }
        let type = TransportMessageType.private(.PRIVMSG([.nick(nick)], encodedData.base64EncodedString()))
        try await transportMessage(channel, type: type)
}
    
     func doMessage(
        sender: IRCUserID?,
        recipients: [ IRCMessageRecipient ],
        message: String,
        tags: [IRCTags]?,
        onlineStatus: OnlineStatus
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
                        print("Recieved Message from server", packet)
                        guard let message = packet.message else { throw NeedleTailError.messageReceivedError }
                        guard let deviceId = packet.sender else { throw NeedleTailError.senderNil }
                        guard let sender = sender?.nick.name else { throw NeedleTailError.nilNickName }
                        print("The Following values should be received from the sender")
                        print(message)
                        print(packet.id)
                        print(sender)
                        print(deviceId)//ddcceefd-25f5-4df5-8a69-f8e3af3f822e
                        print("AUTHENTICATION_STATE", messenger.authenticated )
                        
                        try await self.transportDelegate?.receiveServerEvent(
                            .messageSent(
                                message,
                                id: packet.id,
                                byUser: Username(sender),
                                deviceId: deviceId
                            )
                        )
                        
//                        let acknowledgement = try await createAcknowledgment(.messageSent, id: packet.id)
//                        let ackMessage = acknowledgement.base64EncodedString()
//                        guard let channel = await channel else { return }
//                        let type = TransportMessageType.private(.PRIVMSG([recipient], ackMessage))
//                        try await transportMessage(channel, type: type)
                        
                    case .multiRecipientMessage:
                        break
                    case .readReceipt:
                        switch packet.readReceipt?.state {
                        case .displayed:
                            break
                        case .received:
                            break
                        case .none:
                            break
                        }
                    case .ack(let ack):
                        guard let data = Data(base64Encoded: ack) else { return }
                        let buffer = ByteBuffer(data: data)
                        let ack = try BSONDecoder().decode(Acknowledgment.self, from: Document(buffer: buffer))
                        acknowledgment = ack.acknowledgment
                        logger.info("INFO RECEIVED - ACK: - \(acknowledgment)")
                        
                        switch await transportState.current {
                        case .transportRegistering(channel: let channel, nick: let nick, userInfo: let user):
                            let type = TransportMessageType.standard(.USER(user))
                            try await transportMessage(channel, type: type)
                            await transportState.transition(to: .transportOnline(channel: channel, nick: nick, userInfo: user))
                        default:
                            break
                        }
                    case .requestRegistry:
                        try await receivedRegistryRequest(packet.id)
                    case .newDevice(let state):
                        await receivedNewDevice(state)
                    default:
                        break
                    }
            case .channel(_):
                switch packet.type {
                case .message:
                // We get the Message from IRC and Pass it off to CypherTextKit where it will enqueue it in a job and save it to the DB where we can get the message from.
                guard let message = packet.message else { return }
                guard let deviceId = packet.sender else { return }
                guard let sender = sender?.nick.stringValue else { return }
                try await self.transportDelegate?.receiveServerEvent(
                    .messageSent(
                        message,
                        id: packet.id,
                        byUser: Username(sender),
                        deviceId: deviceId
                    )
                )
                
                    let acknowledgement = try await createAcknowledgment(.messageSent, id: packet.id)
                    let ackMessage = acknowledgement.base64EncodedString()
                    let type = TransportMessageType.private(.PRIVMSG([recipient], ackMessage))
                    guard let channel = await channel else { return }
                    try await transportMessage(channel, type: type)
                default:
                    break
                }
            }
        }
    }
    
    
    private func createAcknowledgment(_ ackType: Acknowledgment.AckType, id: String? = nil) async throws -> Data {
        //Send message ack
        let received = Acknowledgment(acknowledgment: ackType)
        let ack = try BSONEncoder().encode(received).makeData()
        
        let packet = MessagePacket(
            id: id ?? UUID().uuidString,
            pushType: .none,
            type: .ack(ack.base64EncodedString()),
            createdAt: Date(),
            sender: nil,
            recipient: nil,
            message: nil,
            readReceipt: .none
        )
        
        return try BSONEncoder().encode(packet).makeData()
    }
    
    
     func doNick(_ newNick: NeedleTailNick) async throws {
        switch await transportState.current {
        case .transportRegistering(let channel, let nick, let info):
            guard nick != newNick else { return }
            await transportState.transition(to: .transportOnline(channel: channel, nick: newNick, userInfo: info))
        default:
            return
        }
        await respondToTransportState()
    }
    
    
     func doMode(nick: NeedleTailNick, add: IRCUserMode, remove: IRCUserMode) async throws {
        var newMode = userMode
        newMode.subtract(remove)
        newMode.formUnion(add)
        if newMode != userMode {
            userMode = newMode
            await respondToTransportState()
        }
    }
    
    
    func doBlobs(_ blobs: [String]) async throws {
        guard let blob = blobs.first else { throw NeedleTailError.nilBlob }
        self.channelBlob = blob
    }

    
    func doJoin(_ channels: [IRCChannelName], tags: [IRCTags]?) async throws {
        logger.info("Joining channels: \(channels)")
        await respondToTransportState()
        
        guard let tag = tags?.first?.value else { return }
        self.channelBlob = tag
        
        guard let data = Data(base64Encoded: tag) else  { return }
        
        let onlineNicks = try BSONDecoder().decode([NeedleTailNick].self, from: Document(data: data))
        await messenger.plugin.onMembersOnline(onlineNicks)
    }
    
    func doPart(_ channels: [IRCChannelName], tags: [IRCTags]?) async throws {
        print("PARTING CHANNEL")
        await respondToTransportState()
        
        guard let tag = tags?.first?.value else { return }
        guard let data = Data(base64Encoded: tag) else  { return }
        let channelPacket = try BSONDecoder().decode(NeedleTailChannelPacket.self, from: Document(data: data))
        await messenger.plugin.onPartMessage(channelPacket.partMessage ?? "No Message Specified")
    }
    
     func doModeGet(nick: NeedleTailNick) async throws {
        print("DO MODE GET - NICK: \(nick)")
        await respondToTransportState()
    }
    
    
     func doPing(_ server: String, server2: String? = nil) async throws {
        let msg = IRCMessage(origin: origin, command: .PONG(server: server, server2: server))
        guard let channel = await channel else { return }
       try await sendAndFlushMessage(channel, message: msg)
    }
    
    
    private func respondToTransportState() async  {
        switch await transportState.current {
        case .clientOffline:
            break
        case .clientConnecting:
            break
        case .clientConnected:
            break
        case .transportRegistering(channel: _, nick: _, userInfo: _):
            break
        case .transportOnline(channel: _, nick: _, userInfo: _):
            break
        case .transportDeregistering:
            break
        case .transportOffline:
            break
        case .clientDisconnected:
            break
        }
    }
    
    
    func handleInfo(_ info: [String]) {
        for message in info {
            print("Handle Info", message)
        }
    }
    
    
    func handleTopic(_ topic: String, on channel: IRCChannelName) {
            print("Handle Topic \(topic), on channel \(channel)")
    }
    
    func handleServerMessages(_ messages: [String], type: IRCCommandCode) {
        var serverMessage = ""
        switch type {
        case .replyWelcome:
                let stringArray = messages.map{ String($0) }
            serverMessage = stringArray.joined(separator: ",")
            print("REPLY_WELCOME", serverMessage)
        case .replyMyInfo:
            let stringArray = messages.map{ String($0) }
        serverMessage = stringArray.joined(separator: ",")
            print("REPLY_MY_INFO", serverMessage)
        case .replyInfo:
            let stringArray = messages.map{ String($0) }
        serverMessage = stringArray.joined(separator: ",")
            print("REPLY_INFO", serverMessage)
        default:
            break
        }
    }
}
