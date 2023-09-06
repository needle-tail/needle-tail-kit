//
//  NeedleTailTransportClient+IRCDispatcher.swift
//
//
//  Created by Cole M on 3/4/22.
//

import NeedleTailHelpers
import Logging
import CypherMessaging
#if canImport(Combine)
import Combine
#endif
@_spi(AsyncChannel) import NIOCore
@_spi(AsyncChannel) import NeedleTailProtocol

protocol MessengerTransportBridge: AnyObject, Sendable {
    @NeedleTailTransportActor
    var ctcDelegate: CypherTransportClientDelegate? { get set }
    @NeedleTailTransportActor
    var ctDelegate: ClientTransportDelegate? { get set }
    @NeedleTailTransportActor
    var plugin: NeedleTailPlugin? { get set }
}

protocol ClientTransportDelegate: AnyObject {
    func shutdown() async
}


@NeedleTailTransportActor
public final class NeedleTailTransport: NeedleTailClientDelegate, MessengerTransportBridge {
    
    @_spi(AsyncChannel)
    public var asyncChannel: NIOAsyncChannel<ByteBuffer, ByteBuffer>
    var userMode = IRCUserMode()
    @NeedleTailClientActor
    let logger = Logger(label: "Transport")
    //    var usermask: String? {
    //        guard case .registered(_, let nick, let info) = transportState.current else { return nil }
    //        let host = info.servername ?? clientInfo.hostname
    //        return "\(nick.stringValue)!~\(info.username)@\(host)"
    //    }
    var nick: NeedleTailNick? {
        return clientContext.nickname
    }
    var origin: String? {
        return try? BSONEncoder().encode(clientContext.nickname).makeData().base64EncodedString()
    }
    var tags: [IRCTags]?
    var ntkBundle: NTKClientBundle
    var subscribedChannels = Set<IRCChannelName>()
    var proceedNewDeivce = false
    var alertType: AlertType = .registryRequestRejected
    var userInfo: IRCUserInfo?
    var transportState: TransportState
    var registryRequestId = ""
    var receivedNewDeviceAdded: NewDeviceState = .waiting
    var channelBlob: String?
    let clientContext: ClientContext
    let serverInfo: ClientContext.ServerClientInfo
    let store: TransportStore
    weak var delegate: IRCDispatcher?
    weak var ctcDelegate: CypherMessaging.CypherTransportClientDelegate?
    weak var ctDelegate: ClientTransportDelegate?
    var plugin: NeedleTailPlugin?
    let messenger: NeedleTailMessenger
    var quiting = false
#if canImport(Combine)
    private var statusCancellable: Cancellable?
#endif
    let motdBuilder = MOTDBuilder()
    var hasStarted = false
    var multipartData = Data()
    let needleTailCrypto = NeedleTailCrypto()
    
    init(
        ntkBundle: NTKClientBundle,
        asyncChannel: NIOAsyncChannel<ByteBuffer, ByteBuffer>,
        transportState: TransportState,
        clientContext: ClientContext,
        store: TransportStore,
        messenger: NeedleTailMessenger
    ) {
        self.ntkBundle = ntkBundle
        self.store = store
        self.asyncChannel = asyncChannel
        self.transportState = transportState
        self.clientContext = clientContext
        self.serverInfo = clientContext.serverInfo
        self.messenger = messenger
        self.delegate = self
#if canImport(Combine)
        statusCancellable = self.messenger.emitter.publisher(for: \.clientIsRegistered) as? Cancellable
#endif
    }
    
    deinit{
#if canImport(Combine)
        statusCancellable?.cancel()
        statusCancellable = nil
#endif
        //           print("RECLAIMING MEMORY IN TRANSPORT")
    }
    
    func getSender(_ origin: String) async throws -> IRCUserID {
        guard let data = Data(base64Encoded: origin) else { throw NeedleTailError.nilData }
        let buffer = ByteBuffer(data: data)
        let userId = try BSONDecoder().decode(IRCUserID.self, from: Document(buffer: buffer))
        return userId
    }
    
    /// This is the client side message command processor. We decide what to do with each IRCMessage here
    /// - Parameter message: Our IRCMessage
    public func processReceivedMessages(_ message: IRCMessage) async {
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                try Task.checkCancellation()
                let tags = message.tags
                switch message.command {
                case .PING(let origin, let origin2):
                    group.addTask(priority: .utility) { [weak self] in
                        guard let self else { return }
                        try await self.delegate?.doPing(origin, origin2: origin2)
                    }
                case .PONG(_, _):
                    break
                case .PRIVMSG(let recipients, let payload):
                    group.addTask { [weak self] in
                        guard let self else { return }
                        guard let origin = message.origin else { return }
                        let sender = try await self.getSender(origin)
                        try await self.delegate?.doMessage(sender: sender,
                                                           recipients: recipients,
                                                           message: payload,
                                                           tags: tags)
                    }
                case .NOTICE(let recipients, let message):
                    group.addTask { [weak self] in
                        guard let self else { return }
                        try await self.delegate?.doNotice(recipients: recipients, message: message)
                    }
                case .NICK(let nickName):
                    group.addTask { [weak self] in
                        guard let self else { return }
                        guard let origin = message.origin else { return }
                        let sender = try await self.getSender(origin)
                        try await self.delegate?.doNick(sender, nick: nickName, tags: message.tags)
                    }
                case .USER(let info):
                    group.addTask { [weak self] in
                        guard let self else { return }
                        try await self.delegate?.doUserInfo(info, tags: message.tags)
                    }
                case .ISON(let nicks):
                    group.addTask { [weak self] in
                        guard let self else { return }
                        try await self.delegate?.doIsOnline(nicks)
                    }
                case .MODEGET(let nickName):
                    group.addTask { [weak self] in
                        guard let self else { return }
                        try await self.delegate?.doModeGet(nick: nickName)
                    }
                case .CAP(let subcmd, let capIDs):
                    group.addTask { [weak self] in
                        guard let self else { return }
                        try await self.delegate?.doCAP(subcmd, capIDs)
                    }
                case .QUIT(let message):
                    group.addTask { [weak self] in
                        guard let self else { return }
                        try await self.delegate?.doQuit(message)
                    }
                case .CHANNELMODE_GET(let channelName):
                    group.addTask { [weak self] in
                        guard let self else { return }
                        try await self.delegate?.doModeGet(channel: channelName)
                    }
                case .CHANNELMODE_GET_BANMASK(let channelName):
                    group.addTask { [weak self] in
                        guard let self else { return }
                        try await self.delegate?.doGetBanMask(channelName)
                    }
                case .MODE(let nickName, let add, let remove):
                    group.addTask { [weak self] in
                        guard let self else { return }
                        try await self.delegate?.doMode(nick: nickName, add: add, remove: remove)
                    }
                case .WHOIS(let server, let masks):
                    group.addTask { [weak self] in
                        guard let self else { return }
                        try await self.delegate?.doWhoIs(server: server, usermasks: masks)
                    }
                case .WHO(let mask, let opOnly):
                    group.addTask { [weak self] in
                        guard let self else { return }
                        try await self.delegate?.doWho(mask: mask, operatorsOnly: opOnly)
                    }
                case .JOIN(let channels, _):
                    group.addTask { [weak self] in
                        guard let self else { return }
                        try await self.delegate?.doJoin(channels, tags: tags)
                    }
                case .PART(let channels):
                    group.addTask { [weak self] in
                        guard let self else { return }
                        guard let origin = message.origin, let _ = IRCUserID(origin) else {
                            return self.logger.error("ERROR: JOIN is missing a proper origin: \(message)")
                        }
                        try await self.delegate?.doPart(channels, tags: tags)
                    }
                case .LIST(let channels, let target):
                    group.addTask { [weak self] in
                        guard let self else { return }
                        try await self.delegate?.doList(channels, target)
                    }
                case .KICK(let channels, let users, let comments):
                    group.addTask { [weak self] in
                        guard let self else { return }
                        self.logger.info("The following users \(users) were Kicked from the channels \(channels) for these reasons \(comments)")
                        //TODO: Handle
                    }
                case .KILL(let nick, let comment):
                    group.addTask { [weak self] in
                        guard let self else { return }
                        self.logger.info("The following nick \(nick.description) was Killed because it already exists. This is what the server has to say: \(comment)")
                    }
                    //TODO: Handle
                case .otherCommand(Constants.blobs.rawValue, let blob):
                    group.addTask { [weak self] in
                        guard let self else { return }
                        try await self.delegate?.doBlobs(blob)
                    }
                case.otherCommand(Constants.multipartMediaDownload.rawValue, let media):
                    group.addTask(priority: .background) { [weak self] in
                        guard let self else { return }
                        try await self.delegate?.doMultipartMessageDownload(media)
                    }
                case .numeric(.replyMotDStart, _):
                    group.addTask { [weak self] in
                        guard let self else { return }
                        guard let arguments = message.arguments else { return }
                        motdBuilder.createInitial(message: "\(arguments.last!)\n")
                    }
                case .numeric(.replyMotD, _):
                    group.addTask { [weak self] in
                        guard let self else { return }
                        guard let arguments = message.arguments else { return }
                        motdBuilder.createBody(message: "\(arguments.last!)\n")
                    }
                case .numeric(.replyEndOfMotD, _):
                    group.addTask { [weak self] in
                        guard let self else { return }
                            let messageOfTheDay = motdBuilder.createFinalMessage()
                            await self.handleServerMessages([messageOfTheDay], type: .replyEndOfMotD)
                            motdBuilder.clearMessage()
                    }
                case .numeric(.replyNameReply, let args):
                    group.addTask { [weak self] in
                        guard let self else { return }
                        await self.handleServerMessages(args, type: .replyNameReply)
                    }
                case .numeric(.replyEndOfNames, let args):
                    group.addTask { [weak self] in
                        guard let self else { return }
                        await self.handleServerMessages(args, type: .replyEndOfNames)
                    }
                case .numeric(.replyInfo, let info):
                    group.addTask { [weak self] in
                        guard let self else { return }
                        await self.handleInfo(info)
                    }
                case .numeric(.replyMyInfo, let info):
                    group.addTask { [weak self] in
                        guard let self else { return }
                        await self.handleServerMessages(info, type: .replyMyInfo)
                    }
                case .numeric(.replyWelcome, let args):
                    group.addTask { [weak self] in
                        guard let self else { return }
                        await self.handleServerMessages(args, type: .replyWelcome)
                    }
                case .numeric(.replyTopic, let args):
                    group.addTask { [weak self] in
                        guard let self else { return }
                        // :localhost 332 Guest31 #NIO :Welcome to #nio!
                        guard args.count > 2, let channel = IRCChannelName(args[3]) else {
                            return self.logger.error("ERROR: topic args incomplete: \(message)")
                        }
                        await self.handleTopic(args[2], on: channel)
                    }
                case .otherNumeric(let code, let args):
                    group.addTask { [weak self] in
                        guard let self else { return }
                        self.logger.trace("otherNumeric Code: - \(code)")
                        self.logger.trace("otherNumeric Args: - \(args)")
                        await self.handleServerMessages(args, type: IRCCommandCode(rawValue: code)!)
                    }
                default:
                    group.addTask { [weak self] in
                        guard let self else { return }
                        await self.handleInfo(message.command.arguments)
                    }
                }
                try await group.next()
                group.cancelAll()
            }
        } catch {
            logger.error("\(error)")
        }
    }
}
