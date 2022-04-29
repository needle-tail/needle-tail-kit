//
//  IRCService+Inbound.swift
//  
//
//  Created by Cole M on 3/4/22.
//

import Foundation
import CypherMessaging
import BSON
import AsyncIRC
import NeedleTailHelpers

//MARK: - Inbound
extension IRCService: IRCClientDelegate {
    
    
    // MARK: - IRCMessages
    
    /// This method is used to get extra information from server activity.
    /// - Parameters:
    ///   - client: Our ``IRCClient``
    ///   - info: An array of string info sent back from the server
    public func client(_ client: IRCClient, info: [String]) async throws {
    // TODO: Handle Misc. Info
    }
    
    public func client(_ client: IRCClient, keyBundle: [String]) async throws {
        guard let keyBundle = keyBundle.first else { return }
        guard let data = Data(base64Encoded: keyBundle) else { return }
        let buffer = ByteBuffer(data: data)
        let config = try BSONDecoder().decode(UserConfig.self, from: Document(buffer: buffer))
        self.userConfig = config
    }
    
    /// **NOTICE**
    public func client(_       client: IRCClient,
                       notice message: String,
                       for recipients: [ IRCMessageRecipient ]
    ) async {
        await self.updateConnectedClientState(client)
        
        // FIXME: this is not quite right, mirror what we do in message
        //        self.conversationsForRecipients(recipients).forEach {
        //          $0.addNotice(message)
        //        }
    }
    
    
    /// **PRIVMSG** This is where we receive messages from server via AsyncIRC
    public func client(_
                       client: IRCClient,
                       message: String,
                       from sender: IRCUserID,
                       for recipients: [ IRCMessageRecipient ]
    ) async {
        await self.updateConnectedClientState(client)
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
                    case .message:
                        // We get the Message from IRC and Pass it off to CypherTextKit where it will queue it in a job and save
                        // it to the DB where we can get the message from
                        guard let message = packet.message else { return }
                        guard let deviceId = packet.sender else { return }
                        print("Message__", message)
                        print("ID___", packet.id)
                        print("SENDER", sender.nick.stringValue)
                        print("DEVICEID___", deviceId)
                        try await self.transportDelegate?.receiveServerEvent(
                            .messageSent(
                                message,
                                id: packet.id,
                                byUser: Username(sender.nick.stringValue),
                                deviceId: deviceId
                            )
                        )
                        
                        //Send message ack
                        let received = Acknowledgment(acknowledgment: .messageSent(packet.id))
                        let ack = try BSONEncoder().encode(received).makeData().base64EncodedString()
    
                        let packet = MessagePacket(
                            id: UUID().uuidString,
                            pushType: .none,
                            type: .ack(ack),
                            createdAt: Date(),
                            sender: nil,
                            recipient: nil,
                            message: nil,
                            readReceipt: .none
                        )
                        
                        let data = try BSONEncoder().encode(packet).makeData()
                        _ = try await sendNeedleTailMessage(data, to: recipient, tags: nil)
                        
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
    
    
    //???
    public func client(_ client: IRCClient, received message: IRCMessage) async { }
    
    
    
    public func client(_ client: IRCClient, messageOfTheDay message: String) async {
        await self.updateConnectedClientState(client)
        //        self.messageOfTheDay = message
    }
    
    
    // MARK: - Channels
    public func client(_ client: IRCClient,
                       user: IRCUserID,
                       joined channels: [ IRCChannelName ]
    ) async {
        await self.updateConnectedClientState(client)
//                channels.forEach { self.registerChannel($0.stringValue) }
    }
    
    
    public func client(_ client: IRCClient,
                       user: IRCUserID,
                       left channels: [ IRCChannelName ],
                       with message: String?
    ) async {
        await self.updateConnectedClientState(client)
        //        channels.forEach { self.unregisterChannel($0.stringValue) }
    }
    
    
    public func client(_ client: IRCClient,
                       changeTopic welcome: String,
                       of channel: IRCChannelName
    ) async {
        await self.updateConnectedClientState(client)
        // TODO: operation
    }
    
    
    private func updateConnectedClientState(_ client: IRCClient) async {
        switch self.userState.state {
        case .suspended:
            assertionFailure("not connecting, still getting connected client info")
            return
        case .offline:
            assertionFailure("not connecting, still getting connected client info")
            return
        case .connecting:
            print("going online:", client)
            self.userState.transition(to: .online)
            let channels = await ["#NIO", "Swift"].asyncCompactMap(IRCChannelName.init)
            await client.sendAndFlushMessage(.init(command: .JOIN(channels: channels, keys: nil)), chatDoc: nil)
        case .online:
            break
        default:
            break
        }
    }
    
    // MARK: - Connection
    
    
    public func client(_
                       client: IRCClient,
                       registered nick: NeedleTailNick,
                       with userInfo: IRCUserInfo
    ) async {
        await self.updateConnectedClientState(client)
    }
    
    
    public func client(_ client: IRCClient, changedNickTo nick: NeedleTailNick) async {
        await self.updateConnectedClientState(client)
    }
    
    
    public func client(_ client: IRCClient, changedUserModeTo mode: IRCUserMode) async {
        await self.updateConnectedClientState(client)
    }
    
    
    public func clientFailedToRegister(_ newClient: IRCClient) async {
        switch self.userState.state {
        case .suspended, .offline:
            assertionFailure("not connecting, still get registration failure")
            return
        case .connecting, .online:
            print("Closing client ...")
            client?.delegate = nil
            self.userState.transition(to: .offline)
            await client?.disconnect()
        default:
            break
        }
    }
    
    
    public func client(_ client: IRCClient, quit: String?) async {
        print("QUITING")
    }
}
