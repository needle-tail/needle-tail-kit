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
#if os(macOS)
import AppKit
#endif

#if canImport(SwiftUI) && canImport(Combine) && (os(macOS) || os(iOS))
@NeedleTailTransportActor
extension NeedleTailTransport {
    func doNotice(recipients: [IRCMessageRecipient], message: String) async throws {
        await respondToTransportState()
    }
}
#endif

@NeedleTailTransportActor
extension NeedleTailTransport {
    
    @KeyBundleActor
    func doReadKeyBundle(_ keyBundle: [String]) async throws {
        print("READ_KEY_BUNDLE_REQUEST_RECEIVED_WE_SHOULD_HAVE_A_KEY_HERE_AND_NEXT_WE_SHOULD_FINISH_WITH_THE_REQUEST_METHOD: - BUNDLE: \(keyBundle)")
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
    func receivedNewDevice(_ deviceState: NewDeviceState, contacts: [NTKContact]) async throws {
        self.receivedNewDeviceAdded = deviceState
        try await messenger.addMasterDevicesContacts(contacts)
#if (os(macOS) || os(iOS))
        let emitter = messenger.plugin.emitter
        await MainActor.run {
            emitter.qrCodeData = nil
        }
#endif
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
        let type = TransportMessageType.private(.PRIVMSG([.nick(nick)], encodedData.base64EncodedString()))
        try await transportMessage(type)
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
                    try await processMessage(packet, sender: sender, recipient: recipient, messageType: .message)
                case .multiRecipientMessage:
                    break
                case .readReceipt:
                    
                    guard let receipt = packet.readReceipt else { throw NeedleTailError.nilReadReceipt }
                    switch packet.readReceipt?.state {
                    case .displayed:
                        try await messenger.delegate?.receiveServerEvent(
                            .messageDisplayed(
                                by: receipt.sender,
                                deviceId: receipt.senderDevice.device,
                                id: receipt.messageId,
                                receivedAt: receipt.receivedAt
                            )
                        )
                    case .received:
                        try await messenger.delegate?.receiveServerEvent(
                            .messageReceived(
                                by: receipt.sender,
                                deviceId: receipt.senderDevice.device,
                                id: receipt.messageId,
                                receivedAt: receipt.receivedAt
                            )
                        )
                    default:
                        break
                    }
                case .ack(let ack):
                    guard let data = Data(base64Encoded: ack) else { return }
                    let buffer = ByteBuffer(data: data)
                    let ack = try BSONDecoder().decode(Acknowledgment.self, from: Document(buffer: buffer))
                    acknowledgment = ack.acknowledgment
                    logger.info("INFO RECEIVED - ACK: - \(acknowledgment)")
                    
                    if acknowledgment == .registered("true") {
                        switch transportState.current {
                        case .transportRegistering(channel: let channel, nick: let nick, userInfo: let user):
                            let type = TransportMessageType.standard(.USER(user))
                            try await transportMessage(type)
                            await transportState.transition(to: .transportOnline(channel: channel, nick: nick, userInfo: user))
                        default:
                            return
                        }
                    } else if acknowledgment == .quited {
                        await messenger.shutdownClient()
#if os(macOS)
                        await NSApplication.shared.reply(toApplicationShouldTerminate: true)
#endif
                    }
                case .requestRegistry:
                    switch packet.addDeviceType {
                    case .master:
                        try await receivedRegistryRequest(packet.id)
                    case .child:
                        guard let childDeviceConfig = packet.childDeviceConfig else { return }
                        try await messenger.delegate?.receiveServerEvent(
                            .requestDeviceRegistery(childDeviceConfig)
                        )
                    default:
                        break
                    }
                case .newDevice(let state):
                    guard let contacts = packet.contacts else { return }
                    try await receivedNewDevice(state, contacts: contacts)
                default:
                    return
                }
            case .channel(_):
                switch packet.type {
                case .message:
                    // We get the Message from IRC and Pass it off to CypherTextKit where it will enqueue it in a job and save it to the DB where we can get the message from.
                    try await processMessage(packet, sender: sender, recipient: recipient, messageType: .message)
                default:
                    return
                }
            }
        }
    }
    
    private func processMessage(_
                                packet: MessagePacket,
                                sender: IRCUserID?,
                                recipient: IRCMessageRecipient,
                                messageType: MessageType
    ) async throws {
        guard let message = packet.message else { throw NeedleTailError.messageReceivedError }
        guard let deviceId = packet.sender else { throw NeedleTailError.senderNil }
        guard let sender = sender?.nick.name else { throw NeedleTailError.nilNickName }
        
        do {
            try await messenger.delegate?.receiveServerEvent(
                .messageSent(
                    message,
                    id: packet.id,
                    byUser: Username(sender),
                    deviceId: deviceId
                )
            )
        } catch {
            //            if error == "CypherSDKError.cannotFindDeviceConfig" {
            print("CAUGHT_RECEIVE_SERVER_EVENT_ERROR \(error.localizedDescription)")
            return
            //            }
        }
        
        let acknowledgement = try await createAcknowledgment(.messageSent, id: packet.id)
        let ackMessage = acknowledgement.base64EncodedString()
        let type = TransportMessageType.private(.PRIVMSG([recipient], ackMessage))
        try await transportMessage(type)
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
//        switch transportState.current {
//        case .transportRegistering(let channel, let nick, let info):
//            guard nick != newNick else { return }
//            transportState.transition(to: .transportOnline(channel: channel, nick: newNick, userInfo: info))
//        default:
//            return
//        }
//        await respondToTransportState()
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
        await respondToTransportState()
        
        guard let tag = tags?.first?.value else { return }
        guard let data = Data(base64Encoded: tag) else  { return }
        let channelPacket = try BSONDecoder().decode(NeedleTailChannelPacket.self, from: Document(data: data))
        await messenger.plugin.onPartMessage(channelPacket.partMessage ?? "No Message Specified")
    }
    
    func doModeGet(nick: NeedleTailNick) async throws {
        await respondToTransportState()
    }
    
    
    func doPing(_ server: String, server2: String? = nil) async throws {
        let message = IRCMessage(origin: origin, command: .PONG(server: server, server2: server))
        try await sendAndFlushMessage(message)
    }
    
    
    private func respondToTransportState() async {
        switch transportState.current {
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
        var newArray = [String]()
        if info.first?.contains(Constants.colon) != nil {
            newArray.append(contentsOf: info.dropFirst())
        }
        let filtered = newArray
            .filter{ !$0.isEmpty}
            .joined(separator: Constants.space)
        let infoMessage = filtered.components(separatedBy: Constants.cLF)
            .map { $0.replacingOccurrences(of: Constants.cCR, with: Constants.space) }
            .filter{ !$0.isEmpty}
        logger.info("Server information: \(infoMessage.joined())")
    }
    
    
    func handleTopic(_ topic: String, on channel: IRCChannelName) {
        logger.info("Topic: \(topic), on Channel: \(channel)")
    }
    
    func handleServerMessages(_ messages: [String], type: IRCCommandCode) {
        var newArray = [String]()
        if messages.first?.contains(Constants.colon) != nil {
            newArray.append(contentsOf: messages.dropFirst())
        }
        let filtered = newArray
            .filter{ !$0.isEmpty}
            .joined(separator: Constants.space)
        let message = filtered.components(separatedBy: Constants.cLF)
            .map { $0.replacingOccurrences(of: Constants.cCR, with: Constants.space) }
            .filter{ !$0.isEmpty}
        logger.info("Server Message: \(message.joined()), type: \(type)")
    }
}
