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
            try await channel?.writeAndFlush(message)
        } catch {
            logger.error("\(error)")
        }
    }
    
    /// This is where we register the transport session
    /// - Parameter regPacket: Our Registration Packet
    func registerNeedletailSession(_ regPacket: String?) async {
        transportState.transition(to: .registering(
                     channel: channel!,
                     nick: clientContext.nickname,
                     userInfo: clientContext.userInfo))
        
        guard case .registering(_, let nick, let user) = transportState.current else {
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
        
        await createNeedleTailMessage(.USER(user))
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
             print("Client READ BUNDLE")
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
             print("Received Response From Server for Read Key Bundle: \(userConfig)")
            return userConfig
        }
    
    /// Sends a ``NeedleTailNick`` to the server in order to update a users nick name
    /// - Parameter nick: A Nick
     func changeNick(_ nick: NeedleTailNick) async {
        await createNeedleTailMessage(.NICK(nick))
    }
    
//    @NeedleTailActor
//    func _resubscribe() {
//        if !subscribedChannels.isEmpty {
//            // TODO: issues JOIN commands
//        }
//    }

     func sendPrivateMessage(_ message: Data, to recipient: IRCMessageRecipient, tags: [IRCTags]? = nil) async {
        await sendIRCMessage(message.base64EncodedString(), to: recipient, tags: tags)
    }
}
