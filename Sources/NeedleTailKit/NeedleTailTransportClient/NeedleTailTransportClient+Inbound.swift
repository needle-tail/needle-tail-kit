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
extension NeedleTailTransportClient: AsyncIRCNotificationsDelegate {
    
     func doNotice(recipients: [IRCMessageRecipient], message: String) async throws {
        await respondToTransportState()
    }
}
#endif

extension NeedleTailTransportClient {
    
     func doReadKeyBundle(_ keyBundle: [String]) async throws {
        guard let keyBundle = keyBundle.first else { return }
        guard let data = Data(base64Encoded: keyBundle) else { return }
        let buffer = ByteBuffer(data: data)
        let config = try BSONDecoder().decode(UserConfig.self, from: Document(buffer: buffer))
        self.userConfig = config
    }
    
    // 2. When this is called, we are the master device we want to send our decision which should be the newDeviceState to the child device
     func receivedRegistryRequest(fromChild nick: NeedleTailNick) async throws {
        switch await alertUI() {
        case .registryRequest:
            break
        case .registryRequestAccepted:
            let encodedState = try BSONEncoder().encode(NewDeviceState.accepted).makeData().base64EncodedString()
            try await sendMessageTypePacket(.acceptedRegistry(encodedState), nick: nick)
        case .registryRequestRejected:
            let encodedState = try BSONEncoder().encode(NewDeviceState.rejected).makeData().base64EncodedString()
            try await sendMessageTypePacket(.rejectedRegistry(encodedState), nick: nick)
    }
    }
    
    private func sendMessageTypePacket(_ type: MessageType, nick: NeedleTailNick) async throws {
    var message: Data?
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
        
        message = try BSONEncoder().encode(packet).makeData()
        guard let message = message else { return }
        await sendPrivateMessage(message, to: .nickname(nick), tags: nil)
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
    func alertUI() async -> AlertType {
#if canImport(SwiftUI) && canImport(Combine) && (os(macOS) || os(iOS))
        print("Alerting UI")
        notifications.received.send(.registryRequest)
        NotificationCenter.default.post(name: .registryRequest, object: nil)
        while proceedNewDeivce == false {}
#endif
        return alertType
    }
    
    
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
                do {
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
                        
                        let data = try await createAcknowledgment(.messageSent(packet.id))
                        _ = await sendPrivateMessage(data, to: recipient, tags: nil)
                        
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
                        
                        switch transportState.current {
                        case .registering(channel: let channel, nick: let nick, userInfo: let user):
                            transportState.transition(to: .registered(channel: channel, nick: nick, userInfo: user))
                            await createNeedleTailMessage(.USER(user))
                            
                            transportState.transition(to: .online)

                            // Everyone can join administrator, this primarily will be used for beta for report issues
                            let channels = await ["#Administrator"].asyncCompactMap(IRCChannelName.init)
                            await createNeedleTailMessage(.JOIN(channels: channels, keys: nil))
                        default:
                            break
                        }
                    case .blockUnblock:
                        break
                    case .requestRegistry(let childNick):
                        print("receivedRegistry____")
                        guard let data = Data(base64Encoded: childNick) else { return }
                        let buffer = ByteBuffer(data: data)
                        let nick = try BSONDecoder().decode(NeedleTailNick.self, from: Document(buffer: buffer))
                        try await receivedRegistryRequest(fromChild: nick)
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
//                        try await cypher?.addDevice(deviceConfig)
                        try await cypher?.transport.delegate?.receiveServerEvent(.requestDeviceRegistery(deviceConfig))
                    }
                } catch {
                    print(error)
                }
                
                break
            case .channel(let channelName):
                print(channelName)
                
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
                
                let data = try await createAcknowledgment(.messageSent(packet.id))
                _ = await sendPrivateMessage(data, to: recipient, tags: nil)
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
        switch transportState.current {
        case .registering(let channel, let nick, let info):
            guard nick != newNick else { return }
            transportState.transition(to: .registering(channel: channel, nick: newNick, userInfo: info))
        case .registered(let channel, let nick, let info):
            guard nick != newNick else { return }
            transportState.transition(to: .registered(channel: channel, nick: newNick, userInfo: info))
            
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
    
    func doJoin(_ channels: [IRCChannelName], tags: [IRCTags]?) async throws {
        print("DO JOINING CHANNELS", channels)
        await respondToTransportState()
    }
    
     func doModeGet(nick: NeedleTailNick) async throws {
        print("DO MODE GET - NICK: \(nick)")
        await respondToTransportState()
    }
    
     func doPing(_ server: String, server2: String? = nil) async throws {
        let msg: IRCMessage
        
        msg = IRCMessage(origin: origin, // probably wrong
                         command: .PONG(server: server, server2: server))
        await sendAndFlushMessage(msg, chatDoc: nil)
    }
    
    private func respondToTransportState() async  {
        switch transportState.current {
        case .connecting:
            break
        case .registering(channel: _, nick: _, userInfo: _):
            break
        case .registered(channel: _, nick: _, userInfo: _):
            print("going online:", self)
            transportState.transition(to: .online)
//            let channels = await ["#NIO", "Swift"].asyncCompactMap(IRCChannelName.init)
//            print("Respond To State")
//            await sendAndFlushMessage(.init(command: .JOIN(channels: channels, keys: nil)), chatDoc: nil)
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
}
