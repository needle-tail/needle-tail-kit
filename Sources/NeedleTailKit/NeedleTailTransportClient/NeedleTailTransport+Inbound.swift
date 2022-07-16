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
import AsyncIRC

#if canImport(SwiftUI) && canImport(Combine) && (os(macOS) || os(iOS))
extension NeedleTailTransport: AsyncIRCNotificationsDelegate {
    
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
    

    func receivedRegistryRequest(_ messageId: String) async throws {
         
        messenger.plugin.emitter.received = messageId
         
         
//        switch await alertUI() {
//        case .registryRequest:
//            break
//        case .registryRequestAccepted:
//            let encodedState = try BSONEncoder().encode(NewDeviceState.accepted).makeData().base64EncodedString()
//            try await sendMessageTypePacket(.acceptedRegistry(encodedState), nick: nick)
//        case .registryRequestRejected:
//            let encodedState = try BSONEncoder().encode(NewDeviceState.rejected).makeData().base64EncodedString()
//            try await sendMessageTypePacket(.rejectedRegistry(encodedState), nick: nick)
//        default:
//            break
//    }
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
        
        let encodedString = try BSONEncoder().encode(packet).makeData().base64EncodedString()
        guard let channel = await channel else { return }
        let type = TransportMessageType.private(.PRIVMSG([.nickname(nick)], encodedString))
        try await transportMessage(channel, type: type)
}

    
    // 3. The Child Device will call this.
    
     func receivedRegistryResponse(fromMaster deviceState: NewDeviceState, nick: NeedleTailNick) async throws {
        //Temporarily Register Nick to Session
        if deviceState == .accepted {
        try await sendMessageTypePacket(.temporarilyRegisterSession, nick: nick)
        }
        newDeviceState = deviceState
    }
    
    //TODO: LINUX STUFF
//    @MainActor
//    func alertUI() async {
//#if (os(macOS) || os(iOS))
//        print("Alerting UI")
////        await messenger.plugin.emitter.received = .registryRequest
////        while await proceedNewDeivce == false {}
//#endif
////        return await alertType
//    }
    
    
     func respond(to alert: AlertType) async {
        switch alert {
        case .registryRequestAccepted:
            proceedNewDeivce = true
            alertType = .registryRequestAccepted
            newDeviceState = .accepted
        case .registryRequestRejected:
            proceedNewDeivce = true
            alertType = .registryRequestRejected
            newDeviceState = .rejected
        default:
            break
        }
    }
    
    
     func doMessage(
        sender: IRCUserID,
        recipients: [ IRCMessageRecipient ],
        message: String,tags: [IRCTags]?,
        onlineStatus: OnlineStatus
    ) async throws {
        for recipient in recipients {
            switch recipient {
            case .everything:
                break
                //              self.conversations.values.forEach {
                //                $0.addMessage(message, from: sender)
                //              }
            case .nickname(let nick):
                    guard let data = Data(base64Encoded: message) else { return }
                    let buffer = ByteBuffer(data: data)
                    let packet = try BSONDecoder().decode(MessagePacket.self, from: Document(buffer: buffer))
                    switch packet.type {
                    case .publishKeyBundle(_):
                        break
                    case .registerAPN(_):
                        break
                    case .message, .beFriend:
                        // We get the Message from IRC and Pass it off to CypherTextKit where it will enqueue it in a job and save it to the DB where we can get the message from.
                        guard let message = packet.message else { return }
                        guard let deviceId = packet.sender else { return }
                        try await self.transportDelegate?.receiveServerEvent(
                            .messageSent(
                                message,
                                id: packet.id,
                                byUser: Username(sender.nick.stringValue),
                                deviceId: deviceId
                            )
                        )
                        
                        let encodedString = try await createAcknowledgment(.messageSent(packet.id)).base64EncodedString()
                        guard let channel = await channel else { return }
                        let type = TransportMessageType.private(.PRIVMSG([recipient], encodedString))
                        try await transportMessage(channel, type: type)
                        
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
                        case .registering(channel: let channel, nick: let nick, userInfo: let user):
                            await transportState.transition(to: .registered(channel: channel, nick: nick, userInfo: user))
                            let type = TransportMessageType.standard(.USER(user))
                            try await transportMessage(channel, type: type)
                            await transportState.transition(to: .online)

                            // Everyone can join administrator, this primarily will be used for beta for report issues
                            let channelName = "#AdministratorChannel2"
                            try await messenger.createLocalChannel(
                                name: channelName,
                                admin: Username(nick.stringValue),
                                organizers: [Username(nick.stringValue)],
                                members: [Username(nick.stringValue)],
                                permissions: .channelOperator
                            )
                        default:
                            break
                        }
                    case .blockUnblock:
                        break
                    case .requestRegistry:
                        try await receivedRegistryRequest(packet.id)
                    case .acceptedRegistry(let status), .rejectedRegistry(let status), .isOffline(let status):
                        guard let data = Data(base64Encoded: status) else { return }
                        let buffer = ByteBuffer(data: data)
                        let registryStatus = try BSONDecoder().decode(NewDeviceState.self, from: Document(buffer: buffer))
                        try await receivedRegistryResponse(fromMaster: registryStatus, nick: nick)
                    case .temporarilyRegisterSession:
                        break
                    case .newDevice(let config):
                        //Master Device Calls this
                        guard let data = Data(base64Encoded: config) else { return }
                        let buffer = ByteBuffer(data: data)
                        let deviceConfig = try BSONDecoder().decode(UserDeviceConfig.self, from: Document(buffer: buffer))
                        try await messenger.delegate?.receiveServerEvent(.requestDeviceRegistery(deviceConfig))
                    }
            case .channel(let channelName):
                guard let data = Data(base64Encoded: message) else { return }
                let buffer = ByteBuffer(data: data)
                let packet = try BSONDecoder().decode(MessagePacket.self, from: Document(buffer: buffer))
                switch packet.type {
                case .message:
                // We get the Message from IRC and Pass it off to CypherTextKit where it will enqueue it in a job and save it to the DB where we can get the message from.
                guard let message = packet.message else { return }
                guard let deviceId = packet.sender else { return }
                try await self.transportDelegate?.receiveServerEvent(
                    .messageSent(
                        message,
                        id: packet.id,
                        byUser: Username(sender.nick.stringValue),
                        deviceId: deviceId
                    )
                )
                
                    let encodedString = try await createAcknowledgment(.messageSent(packet.id)).base64EncodedString()
                    let type = TransportMessageType.private(.PRIVMSG([recipient], encodedString))
                    guard let channel = await channel else { return }
                    try await transportMessage(channel, type: type)
                default:
                    break
                }
            }
        }
    }
    
    
    private func createAcknowledgment(_ ackType: Acknowledgment.AckType) async throws -> Data {
        //Send message ack
        let received = Acknowledgment(acknowledgment: ackType)
        let ack = try BSONEncoder().encode(received).makeData()
        
        let packet = MessagePacket(
            id: UUID().uuidString,
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
        case .registering(let channel, let nick, let info):
            guard nick != newNick else { return }
            await transportState.transition(to: .registering(channel: channel, nick: newNick, userInfo: info))
        case .registered(let channel, let nick, let info):
            guard nick != newNick else { return }
            await transportState.transition(to: .registered(channel: channel, nick: newNick, userInfo: info))
            
        default: return // hmm
        }
        //        await clientDelegate?.client(self, changedNickTo: newNick)
        await respondToTransportState()
    }
    
    
     func doMode(nick: NeedleTailNick, add: IRCUserMode, remove: IRCUserMode) async throws {
        //        guard let myNick = self.nick?.name, myNick == nick.name else {
        //            return
        //        }
        
        var newMode = userMode
        newMode.subtract(remove)
        newMode.formUnion(add)
        if newMode != userMode {
            userMode = newMode
            //            await clientDelegate?.client(self, changedUserModeTo: newMode)
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
        case .connecting:
            break
        case .registering(channel: _, nick: _, userInfo: _):
            break
        case .registered(channel: _, nick: _, userInfo: _):
            await transportState.transition(to: .online)
            registrationPacket = ""
        case .online:
            break
        case .suspended:
            break
        case .offline:
            break
        case .disconnect:
            break
        case .error(error: let error):
            print(error)
            break
        case .quit:
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
