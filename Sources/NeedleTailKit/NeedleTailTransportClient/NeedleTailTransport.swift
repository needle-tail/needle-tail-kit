//
//  NeedleTailTransportClient+IRCDispatcher.swift
//  
//
//  Created by Cole M on 3/4/22.
//

import NIOCore
import BSON
import NeedleTailHelpers
import AsyncIRC
import Foundation
import Logging
import CypherMessaging

@NeedleTailTransportActor
final class NeedleTailTransport: AsyncIRCDelegate, IRCDispatcher {
    
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
    var cypher: CypherMessenger?
    var messenger: NeedleTailMessenger
    var userConfig: UserConfig?
    var acknowledgment: Acknowledgment.AckType = .none
    var tags: [IRCTags]?
    var channel: Channel?
    var messageOfTheDay = ""
    var subscribedChannels = Set<IRCChannelName>()
    var proceedNewDeivce = false
    var userMode: IRCUserMode
    var alertType: AlertType = .registryRequestRejected
    var userInfo: IRCUserInfo?
    var transportState: TransportState
    var registrationPacket = ""
    let signer: TransportCreationRequest
    var authenticated: AuthenticationState
    var channelBlob: String?
    let clientContext: ClientContext
    let clientInfo: ClientContext.ServerClientInfo
    var transportDelegate: CypherTransportClientDelegate?
    weak var delegate: IRCDispatcher?
    
    
    init(
        cypher: CypherMessenger? = nil,
        messenger: NeedleTailMessenger,
        channel: Channel? = nil,
        messageOfTheDay: String = "",
        userMode: IRCUserMode,
        transportState: TransportState,
        signer: TransportCreationRequest,
        authenticated: AuthenticationState,
        clientContext: ClientContext,
        clientInfo: ClientContext.ServerClientInfo,
        transportDelegate: CypherTransportClientDelegate?
    ) {
        self.cypher = cypher
        self.messenger = messenger
        self.channel = channel
        self.messageOfTheDay = messageOfTheDay
        self.userMode = userMode
        self.transportState = transportState
        self.signer = signer
        self.authenticated = authenticated
        self.clientContext = clientContext
        self.clientInfo = clientInfo
        self.transportDelegate = transportDelegate
        self.delegate = self
    }
    
    /// This is the client side message command processor. We decide what to do with each IRCMessage here
    /// - Parameter message: Our IRCMessage
    func processReceivedMessages(_ message: IRCMessage) async throws {
        let tags = message.tags
        switch message.command {
        case .PING(let server, let server2):
            try await delegate?.doPing(server, server2: server2)
        case .PRIVMSG(let recipients, let payload):
            guard let data = Data(base64Encoded: message.origin ?? "") else { throw NeedleTailError.nilData }
            let buffer = ByteBuffer(data: data)
            let senderNick = try BSONDecoder().decode(NeedleTailNick.self, from: Document(buffer: buffer))
            guard let sender = IRCUserID(
                senderNick.name,
                deviceId: senderNick.deviceId
            ) else { throw NeedleTailError.invalidUserId }
            
            try await delegate?.doMessage(sender: sender,
                                recipients: recipients,
                                message: payload,
                                tags: tags,
                                onlineStatus: .isOnline)
        case .NOTICE(let recipients, let message):
            try await delegate?.doNotice(recipients: recipients, message: message)
        case .NICK(let nickName):
            try await delegate?.doNick(nickName, tags: message.tags)
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
                return print("ERROR: JOIN is missing a proper origin:", message)
            }
            try await delegate?.doPart(channels, tags: tags)
        case .LIST(let channels, let target):
            try await doList(channels, target)
        case .otherCommand("READKEYBNDL", let keyBundle):
            try await delegate?.doReadKeyBundle(keyBundle)
        case .otherCommand("BLOBS", let blob):
            try await delegate?.doBlobs(blob)
        case .numeric(.replyMotDStart, let args):
            messageOfTheDay = (args.last ?? "") + "\n"
        case .numeric(.replyMotD, let args):
            messageOfTheDay += (args.last ?? "") + "\n"
        case .numeric(.replyEndOfMotD, _):
            if !messageOfTheDay.isEmpty {
//                await clientDelegate?.client(self, messageOfTheDay: messageOfTheDay)
            }
            messageOfTheDay = ""
        case .numeric(.replyNameReply, _ /*let args*/):
            break
        case .numeric(.replyEndOfNames, _):
            break
        case .numeric(.replyInfo, let info):
            handleInfo(info)
//            try await clientDelegate?.client(self, info: info)
        case .numeric(.replyTopic, let args):
            // :localhost 332 Guest31 #NIO :Welcome to #nio!
            guard args.count > 2, let channel = IRCChannelName(args[3]) else {
                return print("ERROR: topic args incomplete:", message)
            }
            handleTopic(args[2], on: channel)
//            await clientDelegate?.client(self, changeTopic: args[2], of: channel)
        case .otherNumeric(let code, let args):
            logger.trace("otherNumeric Code: - \(code)")
            logger.trace("otherNumeric Args: - \(args)")
            break
//            await clientDelegate?.client(self, received: message)
        default:
            break
//            await clientDelegate?.client(self, received: message)
        }
    }
}
