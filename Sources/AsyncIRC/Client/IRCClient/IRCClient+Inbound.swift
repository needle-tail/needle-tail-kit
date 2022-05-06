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

extension IRCClient {

//TODO: JUST LIKE MESSAGE
    public func doNotice(recipients: [ IRCMessageRecipient ], message: String) async throws {
//        await clientDelegate?.client(self, notice: message, for: recipients)
        await respondToUserState()
    }
    
    @NeedleTailActor
    public func doReadKeyBundle(_ keyBundle: [String]) async throws {
        guard let keyBundle = keyBundle.first else { return }
        guard let data = Data(base64Encoded: keyBundle) else { return }
        let buffer = ByteBuffer(data: data)
        let config = try BSONDecoder().decode(UserConfig.self, from: Document(buffer: buffer))
        self.userConfig = config
    }
    
    @NeedleTailActor
    public func doMessage(
        sender: IRCUserID?,
        recipients: [ IRCMessageRecipient ],
        message: String,tags: [IRCTags]?,
        userStatus: UserStatus
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
                                byUser: Username(sender!.nick.stringValue),
                                deviceId: deviceId
                            )
                        )
                        
                        //Send message ack
                        let received = Acknowledgment(acknowledgment: .messageSent(packet.id))
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
                        
                        let data = try BSONEncoder().encode(packet).makeData()
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
                        
                        switch userState.state {
                        case .registering(channel: let channel, nick: let nick, userInfo: let user):
                        userState.transition(to: .registered(channel: channel, nick: nick, userInfo: user))
                            
                            userState.transition(to: .online)
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
    
    public func doNick(_ newNick: NeedleTailNick) async throws {
        switch userState.state {
        case .registering(let channel, let nick, let info):
            guard nick != newNick else { return }
            userState.transition(to: .registering(channel: channel, nick: newNick, userInfo: info))
        case .registered(let channel, let nick, let info):
            guard nick != newNick else { return }
            userState.transition(to: .registered(channel: channel, nick: newNick, userInfo: info))
            
        default: return // hmm
        }
//        await clientDelegate?.client(self, changedNickTo: newNick)
        await respondToUserState()
    }
    
    
    public func doMode(nick: NeedleTailNick, add: IRCUserMode, remove: IRCUserMode) async throws {
        guard let myNick = self.nick, myNick == nick else {
            return
        }
        
        var newMode = userMode
        newMode.subtract(remove)
        newMode.formUnion(add)
        if newMode != userMode {
            userMode = newMode
//            await clientDelegate?.client(self, changedUserModeTo: newMode)
            await respondToUserState()
        }
    }
    
    public func doJoin(_ channels: [IRCChannelName]) async throws {
        print("DO JOINING CHANNELS", channels)
        await respondToUserState()
    }
    
    public func doModeGet(nick: NeedleTailNick) async throws {
        print("DO MODE GET - NICK: \(nick)")
        await respondToUserState()
    }
    
    public func doPing(_ server: String, server2: String? = nil) async throws {
        let msg: IRCMessage
        
        msg = IRCMessage(origin: origin, // probably wrong
                         command: .PONG(server: server, server2: server))
        await sendAndFlushMessage(msg, chatDoc: nil)
    }
    
    @NeedleTailActor
    private func respondToUserState() async  {
        switch userState.state {
        case .connecting:
            break
        case .registering(channel: _, nick: _, userInfo: _):
            break
        case .registered(channel: _, nick: _, userInfo: _):
            print("going online:", self)
            userState.transition(to: .online)
            let channels = await ["#NIO", "Swift"].asyncCompactMap(IRCChannelName.init)
            await sendAndFlushMessage(.init(command: .JOIN(channels: channels, keys: nil)), chatDoc: nil)
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
