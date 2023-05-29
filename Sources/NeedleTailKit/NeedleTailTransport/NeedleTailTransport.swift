//
//  NeedleTailTransportClient+IRCDispatcher.swift
//
//
//  Created by Cole M on 3/4/22.
//

import NeedleTailHelpers
import NeedleTailProtocol
import Logging
import CypherMessaging
@_spi(AsyncChannel) import NIOCore

protocol MessengerTransportBridge: AnyObject {
    @NeedleTailTransportActor
    var ctcDelegate: CypherTransportClientDelegate? { get set }
    @NeedleTailTransportActor
    var ctDelegate: ClientTransportDelegate? { get set }
    @NeedleTailTransportActor
    var plugin: NeedleTailPlugin? { get set }
    @MainActor
    var emitter: NeedleTailEmitter? { get set }
}

protocol ClientTransportDelegate: AnyObject {
    func shutdown() async
}


@NeedleTailTransportActor
final class NeedleTailTransport: NeedleTailTransportDelegate, IRCDispatcher, MessengerTransportBridge {
    
    var userMode = IRCUserMode()
    @NeedleTailClientActor
    var channel: Channel
    let logger = Logger(label: "Transport")
    //    var usermask: String? {
    //        guard case .registered(_, let nick, let info) = transportState.current else { return nil }
    //        let host = info.servername ?? clientInfo.hostname
    //        return "\(nick.stringValue)!~\(info.username)@\(host)"
    //    }
    var nick: NeedleTailNick? {
        return clientContext.nickname
    }
    @NeedleTailTransportActor
    var origin: String? {
        return try? BSONEncoder().encode(clientContext.nickname).makeData().base64EncodedString()
    }
    @NeedleTailTransportActor
    var tags: [IRCTags]?
    var ntkBundle: NTKClientBundle
    var messageOfTheDay = ""
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
    @MainActor
    var emitter: NeedleTailEmitter?
    var quiting = false
    
    init(
        ntkBundle: NTKClientBundle,
        asyncChannel: NIOAsyncChannel<ByteBuffer, ByteBuffer>,
        messageOfTheDay: String = "",
        transportState: TransportState,
        clientContext: ClientContext,
        store: TransportStore
    ) {
        self.ntkBundle = ntkBundle
        self.store = store
        self.channel = asyncChannel.channel
        self.messageOfTheDay = messageOfTheDay
        self.transportState = transportState
        self.clientContext = clientContext
        self.serverInfo = clientContext.serverInfo
        self.delegate = self
    }
    
    deinit{
        //           print("RECLAIMING MEMORY IN TRANSPORT")
    }
    
    /// This is the client side message command processor. We decide what to do with each IRCMessage here
    /// - Parameter message: Our IRCMessage
    nonisolated func processReceivedMessages(_ message: IRCMessage) async throws {
        let tags = message.tags
        var sender: IRCUserID?
        
        if let origin = message.origin {
            guard let data = Data(base64Encoded: origin) else { throw NeedleTailError.nilData }
            let buffer = ByteBuffer(data: data)
            let userId = try BSONDecoder().decode(IRCUserID.self, from: Document(buffer: buffer))
            sender = userId
        }
        
        switch message.command {
        case .PING(let origin, let origin2):
            Task.detached { [weak self] in
                guard let self else { return }
                try await self.delegate?.doPing(origin, origin2: origin2)
            }
        case .PONG(_, _):
            break
        case .PRIVMSG(let recipients, let payload):
            try await delegate?.doMessage(sender: sender,
                                          recipients: recipients,
                                          message: payload,
                                          tags: tags)
        case .NOTICE(let recipients, let message):
            try await delegate?.doNotice(recipients: recipients, message: message)
        case .NICK(let nickName):
            try await delegate?.doNick(sender, nick: nickName, tags: message.tags)
        case .USER(let info):
            try await delegate?.doUserInfo(info, tags: message.tags)
        case .ISON(let nicks):
            try await delegate?.doIsOnline(nicks)
        case .MODEGET(let nickName):
            try await delegate?.doModeGet(nick: nickName)
        case .CAP(let subcmd, let capIDs):
            try await delegate?.doCAP(subcmd, capIDs)
        case .QUIT(let message):
            try await delegate?.doQuit(message)
        case .CHANNELMODE_GET(let channelName):
            try await delegate?.doModeGet(channel: channelName)
        case .CHANNELMODE_GET_BANMASK(let channelName):
            try await delegate?.doGetBanMask(channelName)
        case .MODE(let nickName, let add, let remove):
            try await delegate?.doMode(nick: nickName, add: add, remove: remove)
        case .WHOIS(let server, let masks):
            try await delegate?.doWhoIs(server: server, usermasks: masks)
        case .WHO(let mask, let opOnly):
            try await delegate?.doWho(mask: mask, operatorsOnly: opOnly)
        case .JOIN(let channels, _):
            try await delegate?.doJoin(channels, tags: tags)
        case .PART(let channels):
            guard let origin = message.origin, let _ = IRCUserID(origin) else {
                return logger.error("ERROR: JOIN is missing a proper origin: \(message)")
            }
            try await delegate?.doPart(channels, tags: tags)
        case .LIST(let channels, let target):
            try await doList(channels, target)
        case .otherCommand(Constants.blobs, let blob):
            try await delegate?.doBlobs(blob)
        case.otherCommand(Constants.multipartMedia, let media):
            guard let media = media.first else { return }
            try await doMultipartMedia(
                media,
                sender: sender
            )
        case .numeric(.replyMotDStart, let args):
            Task { @NeedleTailTransportActor [weak self] in
                guard let self else { return }
                self.messageOfTheDay = (args.last ?? "") + "\n"
            }
        case .numeric(.replyMotD, let args):
            Task { @NeedleTailTransportActor [weak self] in
                guard let self else { return }
                self.messageOfTheDay += (args.last ?? "") + "\n"
            }
        case .numeric(.replyEndOfMotD, _):
            Task { @NeedleTailTransportActor [weak self] in
                guard let self else { return }
                if !self.messageOfTheDay.isEmpty {
                    await self.handleServerMessages([messageOfTheDay], type: .replyEndOfMotD)
                }
                self.messageOfTheDay = ""
            }
        case .numeric(.replyNameReply, let args):
            await handleServerMessages(args, type: .replyNameReply)
        case .numeric(.replyEndOfNames, let args):
            await handleServerMessages(args, type: .replyEndOfNames)
        case .numeric(.replyInfo, let info):
            await handleInfo(info)
        case .numeric(.replyMyInfo, let info):
            await handleServerMessages(info, type: .replyMyInfo)
        case .numeric(.replyWelcome, let args):
            await handleServerMessages(args, type: .replyWelcome)
        case .numeric(.replyTopic, let args):
            // :localhost 332 Guest31 #NIO :Welcome to #nio!
            guard args.count > 2, let channel = IRCChannelName(args[3]) else {
                return logger.error("ERROR: topic args incomplete: \(message)")
            }
            await handleTopic(args[2], on: channel)
        case .otherNumeric(let code, let args):
            logger.trace("otherNumeric Code: - \(code)")
            logger.trace("otherNumeric Args: - \(args)")
            await handleServerMessages(args, type: IRCCommandCode(rawValue: code)!)
        default:
            await handleInfo(message.command.arguments)
        }
    }
}
