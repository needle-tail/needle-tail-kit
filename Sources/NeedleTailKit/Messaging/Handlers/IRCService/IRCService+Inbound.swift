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
    
    /// This method is used to get extra information from server activity, For instance in our case we are using it to send back acknowledgements of different types of activity.
    /// - Parameters:
    ///   - client: Our ``IRCClient``
    ///   - info: An array of string info sent back from the server
    public func client(_ client: IRCClient, info: [String]) async throws {
        guard let info = info.first else { return }
        guard let data = Data(base64Encoded: info) else { return }
        let buffer = ByteBuffer(data: data)
        let ack = try BSONDecoder().decode(Acknowledgment.self, from: Document(buffer: buffer))
        acknowledgment = ack.acknowledgment
        logger.info("INFO RECEIVED - ACK: - \(acknowledgment)")
    }
    
    public func client(_ client: IRCClient, keyBundle: [String]) async throws {
        guard let keyBundle = keyBundle.first else { return }
        guard let data = Data(base64Encoded: keyBundle) else { return }
        let buffer = ByteBuffer(data: data)
        let config = try BSONDecoder().decode(UserConfig.self, from: Document(buffer: buffer))
        self.userConfig = config
    }
    
    
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
    
    
    //This is where we receive messages from server via AsyncIRC
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
                        
                    case .message:
                        // We get the Message from IRC and Pass it off to CypherTextKit where it will queue it in a job and save
                        // it to the DB where we can get the message from
                        try await self.transportDelegate?.receiveServerEvent(
                            .messageSent(
                                packet.message,
                                id: packet.id,
                                byUser: Username(sender.nick.stringValue),
                                deviceId: packet.sender
                            )
                        )
                        //Send message ack
                        let received = Acknowledgment(acknowledgment: .messageSent(packet.id))
                        let ack = try BSONEncoder().encode(received).makeData().base64EncodedString()
                        await client.acknowledgeMessageReceived(ack)
                        
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
                    case .ack:
                        ()
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
        //        channels.forEach { self.registerChannel($0.stringValue) }
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
            await client.sendMessage(.init(command: .JOIN(channels: channels, keys: nil)), chatDoc: nil)
        case .online:
            break
            // TODO: update state (nick, userinfo, etc)
        }
    }
    
    // MARK: - Connection
    
    
    public func client(_ client        : IRCClient,
                       registered nick : IRCNickName,
                       with   userInfo : IRCUserInfo
    ) async {
        await self.updateConnectedClientState(client)
    }
    
    
    public func client(_ client: IRCClient, changedNickTo nick: IRCNickName) async {
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
        }
    }
    
    
    public func client(_ client: IRCClient, quit: String?) async {
        print("QUITING")
    }
}
