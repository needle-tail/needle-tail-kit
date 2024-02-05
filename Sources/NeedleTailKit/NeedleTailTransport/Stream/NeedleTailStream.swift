//
//  IRCClient+Inbound.swift
//
//
//  Created by Cole M on 4/29/22.
//

@preconcurrency import CypherMessaging
import NeedleTailHelpers
import NeedleTailProtocol
import NeedletailMediaKit
import NeedleTailCrypto
import NIOCore
import Logging
import DequeModule
#if os(macOS)
import AppKit
#endif
#if os(iOS)
import UIKit
#endif
#if canImport(Crypto)
import Crypto
#endif
#if canImport(SwiftDTF)
import SwiftDTF
#endif

#if (os(macOS) || os(iOS))
extension NeedleTailStream {
    public func doNotice(recipients: [IRCMessageRecipient], message: String) async throws {
        await respondToTransportState()
    }
}
#endif

actor NeedleTailStream: IRCDispatcher {
    
    struct Configuration: Sendable, MessengerTransportBridge {
        let writer: NeedleTailWriter
        let ntkBundle: NTKClientBundle
        let clientContext: ClientContext
        let store: TransportStore
        let messenger: NeedleTailMessenger
        var transportState: TransportState
        
        weak var delegate: IRCDispatcher?
        weak var ctcDelegate: CypherMessaging.CypherTransportClientDelegate?
        weak var ctDelegate: ClientTransportDelegate?
        var plugin: NeedleTailPlugin?
    }
    
    var configuration: Configuration
    let logger = Logger(label: "NeedleTailStream")
    let motdBuilder = MOTDBuilder()
    var userMode = IRCUserMode()
    var downloadChunks = NeedleTailAsyncConsumer<MultipartChunk>()
    let multipartMessageConsumer = NeedleTailAsyncConsumer<FilePacket>()
    var registryRequestId = ""
    var channelBlob: String?
    var receivedNewDeviceAdded: NewDeviceState = .waiting
    var hasStarted = false
    var updateKeyBundle = false
    var clientsKnownAquaintances = ClientsKnownAquaintances()
    
    struct MultipartChunk: Sendable {
        var id: String
        var partNumber: String
        var totalParts: String
        var chunk: Data
    }
    
    init(configuration: Configuration) {
        self.configuration = configuration
    }
    
    func setDelegates(_
                      client: NeedleTailClient,
                      delegate: CypherTransportClientDelegate,
                      plugin: NeedleTailPlugin,
                      messenger: NeedleTailMessenger
    ) async {
        configuration.ctcDelegate = delegate
        configuration.ctDelegate = client
        configuration.plugin = plugin
        configuration.delegate = self
    }
    
    func getSender(_ origin: String) async throws -> IRCUserID {
        guard let data = Data(base64Encoded: origin) else { throw NeedleTailError.nilData }
        return try BSONDecoder().decodeData(IRCUserID.self, from: data)
    }
    
    /// This is the client side message command processor. We decide what to do with each IRCMessage here
    /// - Parameter message: Our IRCMessage
    public func processReceivedMessage(_ message: IRCMessage) async {
        do {
            let tags = message.tags
            switch message.command {
            case .PING(let origin, let origin2):
                try await configuration.delegate?.doPong(origin, origin2: origin2)
            case .PONG(_, _):
                break
            case .PRIVMSG(let recipients, let payload):
                guard let origin = message.origin else { return }
                let sender = try await self.getSender(origin)
                try await configuration.delegate?.doMessage(sender: sender,
                                                            recipients: recipients,
                                                            message: payload,
                                                            tags: tags)
            case .NOTICE(let recipients, let message):
                try await configuration.delegate?.doNotice(recipients: recipients, message: message)
            case .NICK(let nickName):
                guard let origin = message.origin else { return }
                let sender = try await self.getSender(origin)
                try await configuration.delegate?.doNick(sender, nick: nickName, tags: message.tags)
            case .USER(let info):
                try await configuration.delegate?.doUserInfo(info, tags: message.tags)
            case .ISON(let nicks):
                //Server-Side
                break
            case .MODEGET(let nickName):
                try await configuration.delegate?.doModeGet(nick: nickName)
            case .CAP(let subcmd, let capIDs):
                try await configuration.delegate?.doCAP(subcmd, capIDs)
            case .QUIT(let message):
                try await configuration.delegate?.doQuit(message)
            case .CHANNELMODE_GET(let channelName):
                try await configuration.delegate?.doModeGet(channel: channelName)
            case .CHANNELMODE_GET_BANMASK(let channelName):
                try await configuration.delegate?.doGetBanMask(channelName)
            case .MODE(let nickName, let add, let remove):
                try await configuration.delegate?.doMode(nick: nickName, add: add, remove: remove)
            case .WHOIS(let server, let masks):
                try await configuration.delegate?.doWhoIs(server: server, usermasks: masks)
            case .WHO(let mask, let opOnly):
                try await configuration.delegate?.doWho(mask: mask, operatorsOnly: opOnly)
            case .JOIN(let channels, _):
                try await configuration.delegate?.doJoin(channels, tags: tags)
            case .PART(let channels):
                guard let origin = message.origin, let _ = IRCUserID(origin) else {
                    return self.logger.error("ERROR: JOIN is missing a proper origin: \(message)")
                }
                try await configuration.delegate?.doPart(channels, tags: tags)
            case .LIST(let channels, let target):
                try await configuration.delegate?.doList(channels, target)
            case .KICK(let channels, let users, let comments):
                self.logger.info("The following users \(users) were Kicked from the channels \(channels) for these reasons \(comments)")
                //TODO: Handle
            case .KILL(let nick, let comment):
                self.logger.info("The following nick \(nick.description) was Killed because it already exists. This is what the server has to say: \(comment)")
                //TODO: Handle
            case .otherCommand(Constants.blobs.rawValue, let blob):
                try await configuration.delegate?.doBlobs(blob)
            case.otherCommand(Constants.multipartMediaDownload.rawValue, let media):
                try await configuration.delegate?.doMultipartMessageDownload(media)
            case .otherCommand(Constants.listBucket.rawValue, let packet):
                try await configuration.delegate?.doListBucket(packet)
            case .numeric(.replyMotDStart, _):
                guard let arguments = message.arguments else { return }
                await motdBuilder.createInitial(message: "\(String(describing: arguments.last))\n")
            case .numeric(.replyMotD, _):
                guard let arguments = message.arguments else { return }
                await motdBuilder.createBody(message: "\(String(describing: arguments.last))\n")
            case .numeric(.replyEndOfMotD, _):
                let messageOfTheDay = await motdBuilder.createFinalMessage()
                await self.handleServerMessages([messageOfTheDay], type: .replyEndOfMotD)
                await motdBuilder.clearMessage()
            case .numeric(.replyNameReply, let args):
                await self.handleServerMessages(args, type: .replyNameReply)
            case .numeric(.replyEndOfNames, let args):
                await self.handleServerMessages(args, type: .replyEndOfNames)
            case .numeric(.replyInfo, let info):
                await self.handleInfo(info)
            case .numeric(.replyMyInfo, let info):
                await self.handleServerMessages(info, type: .replyMyInfo)
            case .numeric(.replyWelcome, let args):
                await self.handleServerMessages(args, type: .replyWelcome)
            case .numeric(.replyTopic, let args):
                // :localhost 332 Guest31 #NIO :Welcome to #nio!
                guard args.count > 2, let channel = IRCChannelName(args[3]) else {
                    return self.logger.error("ERROR: topic args incomplete: \(message)")
                }
                self.handleTopic(args[2], on: channel)
            case .numeric(.replyISON, let nicksAsString):
                try await handleIsOnReply(nicks: nicksAsString)
            case .otherNumeric(let code, let args):
                self.logger.trace("otherNumeric Code: - \(code)")
                self.logger.trace("otherNumeric Args: - \(args)")
                await self.handleServerMessages(args, type: IRCCommandCode(rawValue: code)!)
            case .otherCommand(Constants.readKeyBundle.rawValue, let keyBundle):
                try await doReadKeyBundle(keyBundle)
            default:
                await self.handleInfo(message.command.arguments)
            }
        } catch {
            logger.error("\(error)")
        }
    }
    
    public func doMessage(
        sender: IRCUserID?,
        recipients: [ IRCMessageRecipient ],
        message: String,
        tags: [IRCTags]?
    ) async throws {
        guard let data = Data(base64Encoded: message) else { return }
        let packet = try BSONDecoder().decodeData(MessagePacket.self, from: data)
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
                    try await processMessage(
                        packet,
                        sender: sender,
                        recipient: recipient,
                        messageType: .message,
                        ackType: .messageSent
                    )
                case .multiRecipientMessage:
                    break
                case .readReceipt:
                    guard let receipt = packet.readReceipt else { throw NeedleTailError.nilReadReceipt }
                    switch packet.readReceipt?.state {
                    case .displayed:
                        try await configuration.ctcDelegate?.receiveServerEvent(
                            .messageDisplayed(
                                by: receipt.sender.username,
                                deviceId: receipt.sender.deviceId,
                                id: receipt.messageId,
                                receivedAt: receipt.receivedAt
                            )
                        )
                    case .received:
                        try await configuration.ctcDelegate?.receiveServerEvent(
                            .messageReceived(
                                by: receipt.sender.username,
                                deviceId: receipt.sender.deviceId,
                                id: receipt.messageId,
                                receivedAt: receipt.receivedAt
                            )
                        )
                    default:
                        break
                    }
                case .ack(let ack):
                    let packet = try BSONDecoder().decodeData(Acknowledgment.self, from: ack)
                    await configuration.store.setAck(packet.acknowledgment)
                    switch await configuration.store.acknowledgment {
                    case .registered(let bool):
                        guard bool == "true" else { return }
                        await configuration.transportState.transition(to: .transportRegistered(clientContext: configuration.clientContext))
                        let type = TransportMessageType.standard(.USER(configuration.clientContext.userInfo))
                        try await configuration.writer.transportMessage(type: type)
                        
                        
                        //Create request for online nicks for all of our friends
                        var nicks = [NeedleTailNick]()
                        guard let cypher = await configuration.messenger.cypher else { return }
                        let usernames = try await cypher.listContacts().async.compactMap({ await $0.username })
                        for await username in usernames {
                            print("REQUESTING BUNDLE FOR USERNAME \(username)___________")
                            guard let masterKeyBundle = try await configuration.messenger.cypherTransport?.readKeyBundle(forUsername: username) else { return }
                            print("GOT BUNDLE FOR - BUNDLE: \(masterKeyBundle)___________")
                            for devices in try masterKeyBundle.readAndValidateDevices() {
                                guard let nick = NeedleTailNick(
                                    name: username.raw,
                                    deviceId: devices.deviceId
                                ) else { continue }
                                nicks.append(nick)
                            }
                        }
                        
                        //Send Request
                        try await configuration.writer.requestOnlineNicks(nicks)
                    case .isOnline:
                        await configuration.transportState.transition(to: .transportOnline(clientContext: configuration.clientContext))
                    case .quited:
                        await configuration.writer.setQuiting(false)
                        await configuration.ctDelegate!.shutdown()
                        await configuration.transportState.transition(to: .transportOffline)
#if os(macOS)
                        await NSApplication.shared.reply(toApplicationShouldTerminate: true)
#endif
                    case .multipartUploadComplete(let packet):
#if (os(macOS) || os(iOS))
                        //Thumbnails will always be small so the following code will always run and automatically download thumnbails.
                        if packet.size <= 10777216 && packet.size != 0 {
                            let encodedString = try BSONEncoder().encodeString([packet.name, packet.mediaId])
                            let type = TransportMessageType.standard(.otherCommand(Constants.multipartMediaDownload.rawValue, [encodedString]))
                            try await configuration.writer.transportMessage(type: type)
                        }
                        
                        await setUploadSuccess()
                        hasStarted = false
#else
                        break
#endif
                    case .multipartDownloadFailed(let error, let mediaId):
#if (os(macOS) || os(iOS))
                    Task { @MainActor in
                        if error == "Could not find multipart message" {
                            //Find Message and resize the thumbnail because it does not exist on the server
                                try await configuration.messenger.recreateOrRemoveFile(from: mediaId)
                        } else {
                            await setError(error: error)
                        }
                        await stopAnimatingProgress()
                    }
#else
                        break
#endif
                    default:
                        break
                    }
                case .requestRegistry:
                    switch packet.addDeviceType {
                    case .master:
                        try await receivedRegistryRequest(packet.id)
                    case .child:
                        guard let childDeviceConfig = packet.childDeviceConfig else { return }
                        try await configuration.ctcDelegate?.receiveServerEvent(
                            .requestDeviceRegistery(childDeviceConfig)
                        )
                    default:
                        break
                    }
                case .newDevice(let state):
                    guard let contacts = packet.contacts else { return }
                    try await receivedNewDevice(state, contacts: contacts)
                case .notifyContactRemoval:
#if os(iOS) || os(macOS)
                    guard let contact = packet.contacts?.first else { return }
                    guard let foundContact = try await configuration.messenger.cypher?.getContact(byUsername: contact.username) else { return }
                    try await configuration.messenger.removeMessages(from: foundContact)
                    try await foundContact.remove()
#else
                    return
#endif
                default:
                    return
                }
            case .channel(_):
                switch packet.type {
                case .message:
                    // We get the Message from IRC and Pass it off to CypherTextKit where it will enqueue it in a job and save it to the DB where we can get the message from.
                    try await processMessage(
                        packet,
                        sender: sender,
                        recipient: recipient,
                        messageType: .message,
                        ackType: .messageSent
                    )
                default:
                    return
                }
            }
        }
    }
    
    @MainActor
    private func setError(error: String) async {
#if (os(macOS) || os(iOS))
        await configuration.messenger.emitter.errorReporter = ErrorReporter(status: true, error: error)
#endif
    }
    
    @MainActor
    private func setUploadSuccess() async {
#if (os(macOS) || os(iOS))
        await configuration.messenger.emitter.multipartUploadComplete = true
#endif
    }
    
    public func processMessage(_
                               packet: MessagePacket,
                               sender: IRCUserID?,
                               recipient: IRCMessageRecipient,
                               messageType: MessageType,
                               ackType: Acknowledgment.AckType,
                               messagePacket: MultipartMessagePacket? = nil
    ) async throws {
        guard let message = packet.message else {
            throw NeedleTailError.messageReceivedError
        }
        guard let deviceId = packet.sender else {
            throw NeedleTailError.senderNil
        }
        guard let sender = sender?.nick.name else {
            throw NeedleTailError.nilNickName
        }
        
        do {
            try await configuration.ctcDelegate?.receiveServerEvent(
                .messageSent(
                    message,
                    id: packet.id,
                    byUser: Username(sender),
                    deviceId: deviceId
                )
            )
        } catch {
            logger.error("\(error.localizedDescription)")
            return
        }
        let acknowledgement = try await self.createAcknowledgment(ackType, id: packet.id, messagePacket: messagePacket)
        let ackMessage = acknowledgement.base64EncodedString()
        let type = TransportMessageType.private(.PRIVMSG([recipient], ackMessage))
        try await configuration.writer.transportMessage(type: type)
    }
    
    private func createAcknowledgment(_
                                      ackType: Acknowledgment.AckType,
                                      id: String? = nil,
                                      messagePacket: MultipartMessagePacket? = nil
    ) async throws -> Data {
        //Send message ack
        let received = Acknowledgment(acknowledgment: ackType)
        let ack = try BSONEncoder().encodeData(received)
        let packet = MessagePacket(
            id: id ?? UUID().uuidString,
            pushType: .none,
            type: .ack(ack),
            createdAt: Date(),
            sender: nil,
            recipient: nil,
            message: nil,
            readReceipt: .none,
            multipartMessage: messagePacket
        )
        
        return try BSONEncoder().encodeData(packet)
    }
    
    
    public func doNick(_ newNick: NeedleTailNick) async throws {}
    
    
    public func doMode(nick: NeedleTailNick, add: IRCUserMode, remove: IRCUserMode) async throws {
        var newMode = userMode
        newMode.subtract(remove)
        newMode.formUnion(add)
        if newMode != userMode {
            userMode = newMode
            await respondToTransportState()
        }
    }
    
    
    public func doBlobs(_ blobs: [String]) async throws {
        guard let blob = blobs.first else { throw NeedleTailError.nilBlob }
        self.channelBlob = blob
    }
    
    
    public func doJoin(_ channels: [IRCChannelName], tags: [IRCTags]?) async throws {
        logger.info("Joining channels: \(channels)")
        await respondToTransportState()
        
        guard let tag = tags?.first?.value else { return }
        self.channelBlob = tag
        
        guard let data = Data(base64Encoded: tag) else  { return }
        let packet = try BSONDecoder().decodeData([NeedleTailNick].self, from: data)
        await configuration.plugin?.onMembersOnline(packet)
    }
    
    public func doPart(_ channels: [IRCChannelName], tags: [IRCTags]?) async throws {
        await respondToTransportState()
        
        guard let tag = tags?.first?.value else { return }
        guard let data = Data(base64Encoded: tag) else  { return }
        let packet = try BSONDecoder().decodeData(NeedleTailChannelPacket.self, from: data)
        await configuration.plugin?.onPartMessage(packet.partMessage ?? "No Message Specified")
    }
    
    public func doModeGet(nick: NeedleTailNick) async throws {
        await respondToTransportState()
    }
    
    
    //Send a PONG Reply to server When We receive a PING MESSAGE FROM SERVER
    public func doPong(_ origin: String, origin2: String? = nil) async throws {
        Task { [weak self] in
            guard let self else { return }
        try await withThrowingTaskGroup(of: Void.self) { group in
            try Task.checkCancellation()
            group.addTask {
                try await Task.sleep(until: .now + .seconds(5), tolerance: .seconds(2), clock: .suspending)
                let type = TransportMessageType.standard(.PONG(server: origin, server2: origin2))
                try await self.configuration.writer.transportMessage(type: type)
            }
        }
        }
    }
    
    public func respondToTransportState() async {
        switch await configuration.transportState.current {
        case .clientOffline:
            break
        case .clientConnecting:
            break
        case .clientConnected:
            break
        case .transportRegistering(clientContext: _):
            break
        case .transportOnline(clientContext: _):
            break
        case .transportDeregistering:
            break
        case .transportOffline:
            break
        case .clientDisconnected:
            break
        case .shouldCloseChannel:
            break
        case .transportRegistered:
            break
        }
    }
    
    
    func handleInfo(_ info: [String]) async {
        logger.info("Server information: \(info.joined())")
    }
    
    
    func handleTopic(_ topic: String, on channel: IRCChannelName) {
        logger.info("Topic: \(topic), on Channel: \(channel)")
    }
    
    func handleServerMessages(_ messages: [String], type: IRCCommandCode) async {
        logger.info("Server Message: \n\(messages.joined(separator: "\n"))- type: \(type)")
    }
    
    func handleIsOnReply(nicks: [String]) async throws {
        print("RECEIVED NICKS IS ON", nicks)
        for nick in nicks {
            let split = nick.components(separatedBy: Constants.colon.rawValue)
            guard let name = split.first else { continue }
            guard let deviceId = split.last else { continue }
            guard let nick = NeedleTailNick(name: name, deviceId: DeviceId(deviceId)) else { continue }
            clientsKnownAquaintances.contacts.append(nick)
        }
    }
    
    var multipartData = Data()
    public func doMultipartMessageDownload(_ packet: [String]) async throws {
        logger.info("Received multipart packet: \(packet[0]) of: \(packet[1])")
        precondition(packet.count == 4)
        let partNumber = packet[0]
        let totalParts = packet[1]
        let name = packet[2]
        let chunk = packet[3]
        
        guard let data = Data(base64Encoded: chunk) else { return }
        await downloadChunks.feedConsumer([
            MultipartChunk(
                id: name,
                partNumber: partNumber,
                totalParts: totalParts,
                chunk: data
            )
        ])
        
        let totalPartsInFile = await self.downloadChunks.deque.filter({ $0.id == name && $0.partNumber <= $0.totalParts })
        if totalPartsInFile.count == Int(totalPartsInFile.first?.totalParts ?? "") {
            self.logger.info("Finished receiving parts...")
            self.logger.info("Starting to process multipart packet...")
            for try await result in NeedleTailAsyncSequence(consumer: self.downloadChunks) {
                switch result {
                case .success(let chunk):
                    await self.addChunkData(data: chunk.chunk)
                    if chunk.partNumber == chunk.totalParts {
                        try await self.processMultipartMediaMessage(self.multipartData)
                        await self.removeMultipartData()
                        await self.stopAnimatingProgress()
                        return
                    }
                case .consumed:
                    return
                }
            }
        }
    }
    
    func addChunkData(data: Data) async {
        self.multipartData.append(data)
    }
    
    func removeMultipartData() async {
        self.multipartData.removeAll()
    }
    
    @MainActor
    func stopAnimatingProgress() async {
#if (os(macOS) || os(iOS))
        await configuration.messenger.emitter.stopAnimatingProgress = true
#endif
    }
    
    public func doListBucket(_ packet: [String]) async throws {
        guard let data = Data(base64Encoded: packet[0]) else { return }
        let packet = try BSONDecoder().decodeData([String].self, from: data)
        var filenames = [Filename]()
        for name in packet {
            filenames.append(Filename(name))
        }
        await setFileNames(filenames)
    }
    
    @MainActor
    private func setFileNames(_ filenames: [Filename]) async {
#if (os(macOS) || os(iOS))
        await configuration.messenger.emitter.listedFilenames = filenames
#endif
    }
    
    private func processMultipartMediaMessage(_ multipartData: Data) async throws {
        let packet = try BSONDecoder().decodeData(FilePacket.self, from: multipartData)
        guard let cypher = await configuration.messenger.cypher else { throw NeedleTailError.cypherMessengerNotSet }
        //1. Look up message by Id
        if let message = try await configuration.messenger.findMessage(from: packet.mediaId, cypher: cypher) {
            try await processDownload(message: message, decodedData: packet, cypher: cypher)
        } else {
            //QUEUE Until message creation occurs
            await multipartMessageConsumer.feedConsumer([packet])
            logger.info("Couldn't find message in order to process media")
        }
    }
    
    internal func processDownload(
        message: AnyChatMessage,
        decodedData: FilePacket,
        cypher: CypherMessenger
    ) async throws {
        let mediaId = await message.metadata["mediaId"] as? String
        if mediaId == decodedData.mediaId {
            guard let keyBinary = await message.metadata["symmetricKey"] as? Binary else { throw NeedleTailError.symmetricKeyDoesNotExist }
            let ntc = configuration.messenger.needletailCrypto
            try await message.setMetadata(
                cypher,
                emitter: configuration.messenger.emitter,
                sortChats: sortConversations,
                run: { props in
                    let document = props.message.metadata
                    var dtfp = try BSONDecoder().decode(DataToFilePacket.self, from: document)
                    let symmetricKey = try BSONDecoder().decodeData(SymmetricKey.self, from: keyBinary.data)
                    guard let fileData = try ntc.decrypt(data: decodedData.data, symmetricKey: symmetricKey) else { throw NeedleTailError.nilData }
                    guard let fileBoxData = try cypher.encryptLocalFile(fileData).combined else { throw NeedleTailError.nilData }
                    
                    switch decodedData.mediaType {
                    case .file:
                        let fileLocation = try DataToFile.shared.generateFile(
                            data: fileBoxData,
                            fileName: dtfp.fileName,
                            fileType: dtfp.fileType
                        )
                        dtfp.fileLocation = fileLocation
                        dtfp.fileSize = fileBoxData.count
                    case .thumbnail:
                        let thumbnailLocation = try DataToFile.shared.generateFile(
                            data: fileBoxData,
                            fileName: dtfp.thumbnailName,
                            fileType: dtfp.thumbnailType
                        )
                        dtfp.thumbnailLocation = thumbnailLocation
                        dtfp.thumbnailSize = fileBoxData.count
                    }
                    dtfp.fileBlob = nil
                    dtfp.thumbnailBlob = nil
                    return try BSONEncoder().encode(dtfp)
                })
            
            var fileName = ""
            var fileType = ""
            switch decodedData.mediaType {
            case .file:
                fileName = await message.metadata["fileName"] as? String ?? ""
                fileType = await message.metadata["fileType"] as? String ?? ""
            case .thumbnail:
                fileName = await message.metadata["thumbnailName"] as? String ?? ""
                fileType = await message.metadata["thumbnailType"] as? String ?? ""
            }
            
            guard let senderDeviceId = await configuration.messenger.cypher?.deviceId else { throw NeedleTailError.deviceIdNil }
            var packet = MessagePacket(
                id: UUID().uuidString,
                pushType: .none,
                type: .ack(Data()),
                createdAt: Date(),
                sender: senderDeviceId,
                recipient: nil,
                multipartMessage: MultipartMessagePacket(
                    id: "\(fileName)_\(senderDeviceId.raw).\(fileType)",
                    sender: configuration.clientContext.nickname
                )
            )
            
            let acknowledgement = try await self.createAcknowledgment(.multipartReceived, id: packet.id, messagePacket: packet.multipartMessage)
            packet.type = .ack(acknowledgement)
            let ackMessage = acknowledgement.base64EncodedString()
            let type = TransportMessageType.private(.PRIVMSG([IRCMessageRecipient.nick(configuration.clientContext.nickname)], ackMessage))
            try await configuration.writer.transportMessage(type: type)
        } else {
            throw NeedleTailError.mediaIdNil
        }
    }
}

struct FilePacket: Sendable, Codable {
    var mediaId: String
    var mediaType: MediaType
    var name: String
    var data: Data
}

enum MediaType: Sendable, Codable {
    case thumbnail, file
}