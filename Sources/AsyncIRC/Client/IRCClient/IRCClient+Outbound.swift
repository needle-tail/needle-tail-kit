//
//  IRCClient+Outbound.swift
//  
//
//  Created by Cole M on 4/29/22.
//

import Foundation
import NeedleTailHelpers
import CypherMessaging

extension IRCClient {
    
    /// This method is how all client messages get sent through the client to the server. This is the where they leave the Client.
    /// - Parameters:
    ///   - message: Our IRCMessage
    ///   - chatDoc: Not needed/used for clients and shouldn't be.
    public func sendAndFlushMessage(_ message: IRCMessage, chatDoc: ChatDocument?) async {
        do {
            try await channel?.writeAndFlush(message)
        } catch {
            logger.error("\(error)")
        }
    }
    
    /// This is where we register the transport session
    /// - Parameter regPacket: Our Registration Packet
    @NeedleTailActor
    public func registerNeedletailSession(_ regPacket: String?) async {
        guard case .registering(_, let nick, let user) = transportState.current else {
            assertionFailure("called \(#function) but we are not connecting?")
            return
        }
        
            await createNeedleTailMessage(.otherCommand("PASS", [ clientInfo.password ]))
        
        if let regPacket = regPacket {
            print("Registering", nick)
            let tag = IRCTags(key: "registrationPacket", value: regPacket)
            await createNeedleTailMessage(.NICK(nick), tags: [tag])
        } else {
            await createNeedleTailMessage(.NICK(nick))
        }
        
        await createNeedleTailMessage(.USER(user))
    }

    // 1. We want to tell the master device that we want to register
    @NeedleTailActor
    public func sendDeviceRegistryRequest(_ masternNick: NeedleTailNick, childNick: NeedleTailNick) async throws {
        let recipient = IRCMessageRecipient.nickname(masternNick)
        let child = try BSONEncoder().encode(childNick).makeData().base64EncodedString()
        let packet = MessagePacket(
            id: UUID().uuidString,
            pushType: .none,
            type: .requestRegistry(child),
            createdAt: Date(),
            sender: nil,
            recipient: nil,
            message: nil,
            readReceipt: .none
        )
        let message = try BSONEncoder().encode(packet).makeData().base64EncodedString()
        await sendIRCMessage(message, to: recipient, tags: nil)
    }
    
    // 4.
    @NeedleTailActor
    public func sendFinishRegistryMessage(toMaster
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
        @KeyBundleActor
        public func readKeyBundle(_ packet: String) async -> UserConfig? {
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
    @NeedleTailActor
    public func changeNick(_ nick: NeedleTailNick) async {
        await createNeedleTailMessage(.NICK(nick))
    }
    
    @NeedleTailActor
    func _resubscribe() {
        if !subscribedChannels.isEmpty {
            // TODO: issues JOIN commands
        }
    }
    @NeedleTailActor
    public func sendPrivateMessage(_ message: Data, to recipient: IRCMessageRecipient, tags: [IRCTags]? = nil) async {
        await sendIRCMessage(message.base64EncodedString(), to: recipient, tags: tags)
    }
}
