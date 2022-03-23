//
//  IRCService+Inbound.swift
//  
//
//  Created by Cole M on 3/4/22.
//

import Foundation
import AsyncIRC
import CypherMessaging
import BSON

//MARK: - Inbound
extension IRCService: IRCClientDelegate {
    //MARK: - CypherMessageAPI
        func fetchConversations() async {
            for chat in try! await messenger!.listConversations(
                includingInternalConversation: true,
                increasingOrder: { _, _ in return true }
            ) {
                print(chat.conversation)
            }
        }
    
    // MARK: - IRCMessages
    public func client(_ client: IRCClient, info: [String]) async throws {
        guard let info = info.first else { return }
        guard let data = Data(base64Encoded: info) else { return }
        let buffer = ByteBuffer(data: data)
        registedNewUser = try BSONDecoder().decode(RegistrationAck.self, from: Document(buffer: buffer)).registered
    }
    
    
    public func client(_ client: IRCClient, keyBundle: [String]) async throws {
        guard let userConfig = keyBundle.first else { return }
        guard let data = Data(base64Encoded: userConfig) else { return }
        let buffer = ByteBuffer(data: data)
        let c = try BSONDecoder().decode(UserConfig.self, from: Document(buffer: buffer))
        self.stream = KeyBundleSequence(bundle: c).makeAsyncIterator()
    }
    
    public func client(_       client : IRCClient,
                       notice message : String,
                       for recipients : [ IRCMessageRecipient ]
    ) async {
        await self.updateConnectedClientState(client)
        
        // FIXME: this is not quite right, mirror what we do in message
//        self.conversationsForRecipients(recipients).forEach {
//          $0.addNotice(message)
//        }
      }
      
    
    //This is where we receive messages from server via AsyncIRC
    public func client(_       client : IRCClient,
                       message        : String,
                       from    sender : IRCUserID,
                       for recipients : [ IRCMessageRecipient ]
    ) async {
        await self.updateConnectedClientState(client)
        
        // FIXME: We need this because for DMs we use the sender as the
        //        name
        for recipient in recipients {
          switch recipient {
            case .channel(let name):
              print(name)
//              if let c = self.registerChannel(name.stringValue) {
//                c.addMessage(message, from: sender)
//              }
              break
            case .nickname: // name should be us
              print("DATA RECEIVED: \(client)")
              print("DATA RECEIVED: \(message)")
              print("DATA RECEIVED: \(sender)")
              print("DATA RECEIVED: \(recipients)")
//              if let c = self.registerDirectMessage(sender.nick.stringValue) {
//                c.addMessage(message, from: sender)
//              }
              break
            case .everything:
break
//              self.conversations.values.forEach {
//                $0.addMessage(message, from: sender)
//              }
          }
        }
      }

    
    
    public func client(_ client: IRCClient, received message: IRCMessage) async {

        struct Packet: Codable {
            let id: ObjectId
            let type: MessageType
            let body: Document
        }
        
        switch message.command {

        case .PRIVMSG(_, let data):
            Task.detached {
                print("DATA", data)
                do {
                    let buffer = ByteBuffer(data: Data(base64Encoded: data)!)
                    print("BUFFER", buffer)
                    let packet = try BSONDecoder().decode(Packet.self, from: Document(buffer: buffer))
                    print("MY PACKET", packet)
                    switch packet.type {
                        
                    case .message:
                        let dmPacket = try BSONDecoder().decode(DirectMessagePacket.self, from: packet.body)
                        print("DMPACKET", dmPacket)
                        // We get the Message from IRC and Pass it off to CypherTextKit where it will queue it in a job and save
                        // it to the DB where we can get the message from
                        try await self.transportDelegate?.receiveServerEvent(
                            .messageSent(
                                dmPacket.message,
                                id: dmPacket.messageId,
                                byUser: dmPacket.sender.user,
                                deviceId: dmPacket.sender.device
                            )
                        )
                    case .multiRecipientMessage:
                        break
                    case .readReceipt:
                        let receipt = try BSONDecoder().decode(ReadReceiptPacket.self, from: packet.body)
                        switch receipt.state {
                        case .displayed:
                            break
                        case .received:
                            break
                        }
                    case .ack:
                        ()
                    }
                    
                } catch {
                    print(error)
                }
            }
//
//        case .otherCommand(let keyBundle, let data):
//            if keyBundle == "KEYBUNDLE" {
//                //DO stuff with data
//            }
        default:
            break
        }
        }
    

    
    public func client(_ client: IRCClient, messageOfTheDay message: String) async {
        await self.updateConnectedClientState(client)
//        self.messageOfTheDay = message
      }
    
    
    // MARK: - Channels

    public func client(_ client: IRCClient,
                       user: IRCUserID, joined channels: [ IRCChannelName ]
    ) async {
        await self.updateConnectedClientState(client)
//        channels.forEach { self.registerChannel($0.stringValue) }
      }
    
    public func client(_ client: IRCClient,
                       user: IRCUserID, left channels: [ IRCChannelName ],
                       with message: String?
    ) async {
        await self.updateConnectedClientState(client)
//        channels.forEach { self.unregisterChannel($0.stringValue) }
      }

    public func client(_ client: IRCClient,
                       changeTopic welcome: String, of channel: IRCChannelName
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
                      await client.sendMessage(.init(command: .JOIN(channels: channels, keys: nil)))
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
