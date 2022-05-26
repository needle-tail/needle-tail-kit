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

#if canImport(SwiftUI) && canImport(Combine) && (os(macOS) || os(iOS))
extension IRCClient: AsyncIRCNotificationsDelegate {
    
    public func doNotice(recipients: [ IRCMessageRecipient ], message: String) async throws {
        await respondToTransportState()
    }
}
#endif

extension IRCClient {
    
    @NeedleTailActor
    public func doReadKeyBundle(_ keyBundle: [String]) async throws {
        guard let keyBundle = keyBundle.first else { return }
        guard let data = Data(base64Encoded: keyBundle) else { return }
        let buffer = ByteBuffer(data: data)
        let config = try BSONDecoder().decode(UserConfig.self, from: Document(buffer: buffer))
        self.userConfig = config
    }
    
    //Sent to ourself in order to create the UserDeviceConfig, We then send it to the master device in order to add the device to the Masters UserConfig. We then can register into that User.
    //TODO: Not being called
    @NeedleTailActor
    public func doNewDevice(_ info: [String]) async throws {
        print("INFO_COUNT___", info.count)
        if info.count == 1 {
            //This will only be called as a response from the server telling ourself to start the new device process
            guard let config = try await cypher?.createDeviceRegisteryRequest() else { return }
            print("CREATE DEVICE CONFIG", config)
            let data = try BSONEncoder().encode(config).makeData().base64EncodedString()
            try await addNewDevice(data, nick: info[0])
        } else if info.count == 3 {
            print("We received the request from our other device___")
            //5. We received the request from our other device, lets approve of the request and finish adding the device.
            //This will be fired by the recipient AKA the Master device
            //First alert the master device that it has another device that wants to be added.
            await alertUI()
            if alertType == .registryRequestRejected {
                print("REJECTED REQUEST")
                // We need to tell the server who was rejected
                guard let data = Data(base64Encoded: info[2]) else { return }
                let buffer = ByteBuffer(data: data)
                let rejectedNick = try BSONDecoder().decode(NeedleTailNick.self, from: Document(buffer: buffer))
                let message = try await createAcknowledgment(.registryRequestRejected(rejectedNick.name, rejectedNick.deviceId?.raw ?? ""))
                guard let needletail = NeedleTailNick(self.cypher?.username.raw ?? "") else { return }
                await sendPrivateMessage(message, to: .nickname(needletail), tags: nil)
                return
            }
            guard let data = Data(base64Encoded: info[1]) else { return }
            let buffer = ByteBuffer(data: data)
            let config = try BSONDecoder().decode(UserDeviceConfig.self, from: Document(buffer: buffer))
            // When we add an extra device the CTK will publish the config for us on the server.
            try await cypher?.addDevice(config)
            //6. We then need to let the new device know it can finish logging in a new session the the same needletailnick
            print("ATTEMPTING NEW DEVICE REGISTRATION___")
            await registerNeedletailSession(registrationPacket)
            
        }
    }
    
//TODO: LINUX STUFF
    @NeedleTailActor
    func alertUI() async {
#if canImport(SwiftUI) && canImport(Combine) && (os(macOS) || os(iOS))
        print("Alerting UI")
        notifications.received.send(.registryRequest)
        NotificationCenter.default.post(name: .registryRequest, object: nil)
        while proceedNewDeivce == false {}
#endif
    }

    
    @NeedleTailActor
    public func respond(to alert: AlertType) async {
        switch alert {
        case .registryRequestAccepted:
            proceedNewDeivce = true
            alertType = .registryRequestAccepted
        case .registryRequestRejected:
            proceedNewDeivce = true
            alertType = .registryRequestRejected
        default:
            break
        }
    }
    
    @NeedleTailActor
    public func doMessage(
        sender: IRCUserID,
        recipients: [ IRCMessageRecipient ],
        message: String,tags: [IRCTags]?,
        onlineStatus: OnlineStatus
    ) async throws {
        for recipient in recipients {
            switch recipient {
            case .channel(let name):
                print(name)
                //              if let c = self.registerChannel(name.stringValue) {
                //                c.addMessage(message, from: sender)
                //              }
                break
            case .nickname:
                
                do {
                    guard let data = Data(base64Encoded: message) else { return }
                    let buffer = ByteBuffer(data: data)
                    let packet = try BSONDecoder().decode(MessagePacket.self, from: Document(buffer: buffer))
                    switch packet.type {
                    case .newDevice(let config):
                        guard let data = Data(base64Encoded: config) else { return }
                        let buffer = ByteBuffer(data: data)
                        let deviceConfig = try BSONDecoder().decode(UserDeviceConfig.self, from: Document(buffer: buffer))
                        try await cypher?.addDevice(deviceConfig)
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
                            
                            transportState.transition(to: .online)
                            let channels = await ["#NIO", "Swift"].asyncCompactMap(IRCChannelName.init)
                            await sendAndFlushMessage(.init(command: .JOIN(channels: channels, keys: nil)), chatDoc: nil)
                        default:
                            break
                        }
                    case .blockUnblock:
                        break
                    }
                } catch {
                    print(error)
                }
                
                break
            case .everything:
                break
                //              self.conversations.values.forEach {
                //                $0.addMessage(message, from: sender)
                //              }
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
    
    public func doNick(_ newNick: NeedleTailNick) async throws {
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
    
    
    public func doMode(nick: NeedleTailNick, add: IRCUserMode, remove: IRCUserMode) async throws {
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
    
    public func doJoin(_ channels: [IRCChannelName]) async throws {
        print("DO JOINING CHANNELS", channels)
        await respondToTransportState()
    }
    
    public func doModeGet(nick: NeedleTailNick) async throws {
        print("DO MODE GET - NICK: \(nick)")
        await respondToTransportState()
    }
    
    public func doPing(_ server: String, server2: String? = nil) async throws {
        let msg: IRCMessage
        
        msg = IRCMessage(origin: origin, // probably wrong
                         command: .PONG(server: server, server2: server))
        await sendAndFlushMessage(msg, chatDoc: nil)
    }
    
    @NeedleTailActor
    private func respondToTransportState() async  {
        switch transportState.current {
        case .connecting:
            break
        case .registering(channel: _, nick: _, userInfo: _):
            break
        case .registered(channel: _, nick: _, userInfo: _):
            print("going online:", self)
            transportState.transition(to: .online)
            let channels = await ["#NIO", "Swift"].asyncCompactMap(IRCChannelName.init)
            await sendAndFlushMessage(.init(command: .JOIN(channels: channels, keys: nil)), chatDoc: nil)
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
