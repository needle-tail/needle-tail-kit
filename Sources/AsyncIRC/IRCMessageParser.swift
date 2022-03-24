//===----------------------------------------------------------------------===//
//
// This source file is part of the swift-nio-irc open source project
//
// Copyright (c) 2018-2021 ZeeZide GmbH. and the swift-nio-irc project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIOIRC project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIO
import Foundation
import AsyncCollections
import Logging
 
// Compat, remove me.
public typealias IRCParserError = IRCMessageParser.Error


enum ParserError: Swift.Error {
    case jobFailedToParse
}

public final class IRCMessageParser {

    public enum Error : Swift.Error {
        case invalidPrefix       (Data)
        case invalidCommand      (Data)
        case tooManyArguments    (Data)
        case invalidArgument     (Data)
        
        case invalidArgumentCount(command: String, count: Int, expected: Int)
        case invalidMask         (command: String, mask: String)
        case invalidChannelName  (String)
        case invalidNickName     (String)
        case invalidMessageTarget(String)
        case invalidCAPCommand   (String)
        
        case transportError(Swift.Error)
        case syntaxError
        case notImplemented
    }
    
    enum MessageParserError: Swift.Error {
        case rangeNotFound
        case firstCharacterIsNil
        case argumentsAreNil
        case commandIsNil
        case firstIndexChoiceNil
        case messageWithTagsNil
        case messageWithWhiteSpaceNil
    }
    
    enum IRCCommandKey {
        case int   (Int)
        case string(String)
    }
    var logger: Logger
    
    init(logger: Logger) {
        self.logger = logger
    }
    
    internal func parseMessage(_ message: String) async throws -> IRCMessage {
        var ircMessage: IRCMessage
        var origin: String?
        var seperatedTags: [String] = []
        var stripedMessage: String = ""
        var commandKey: IRCCommandKey = .string("")
        self.logger.info("Parsing Message.... \(message)")
        
        /// IRCMessage sytax
        /// ::= ['@' <tags> SPACE] [':' <source> SPACE] <command> <parameters> <crlf>
        
        ///We are seperating our tags from our message string before we process the rest of our message
        if message.contains("@") && message.contains("; ") {
            seperatedTags.append(contentsOf: message.components(separatedBy: "; "))
            stripedMessage = seperatedTags[1]
        } else {
            stripedMessage = message
        }

        guard let firstSpaceIndex = stripedMessage.firstIndex(of: " ") else { throw MessageParserError.messageWithWhiteSpaceNil }
        var command = ""
        ///This stripedMessage represents our irc message portion without tags. If we have the source then we will get the source here
        
        /// Always our origin
        if stripedMessage.hasPrefix(":") {
        let source = stripedMessage[..<firstSpaceIndex]
        origin = String(source)
        }
        let spreadStriped = stripedMessage.components(separatedBy: " ")
        
        //This is probably really bad, if we get a origin back from the server it will be preceeded with a :. So we are using it to determine the command type.
        if stripedMessage.hasPrefix(":") {
            command = spreadStriped[1]
        } else {
            command = spreadStriped[0]
        }
        
        guard let command = try parseCommand(
            command: command,
            commandKey: commandKey
        ) else { throw MessageParserError.commandIsNil}

        commandKey = command
        
        
        let rest = stripedMessage[firstSpaceIndex...].trimmingCharacters(in: .whitespacesAndNewlines)
        let commandIndex = rest.startIndex
        let commandMessage = rest[commandIndex...]
        let commandSubstring = stripedMessage[commandIndex..<firstSpaceIndex]

        guard let arguments = try parseArguments(
            commandMessage: String(commandMessage),
            commandSubstring: String(commandSubstring),
            stripedMessage: String(stripedMessage)
        ) else { throw MessageParserError.argumentsAreNil }

        
        var tags: [IRCTags]?
        if seperatedTags != [] {
            tags = try await parseTags(
            tags: seperatedTags[0]
        )
        }


        switch commandKey {
        case .string(let s):
            ircMessage = IRCMessage(origin: origin,
                                    command: try IRCCommand(s, arguments: arguments), tags: tags)
        case .int(let i):
            ircMessage = IRCMessage(origin: origin,
                                    command: try IRCCommand(i, arguments: arguments), tags: tags)

        }
        self.logger.info("Parsed Message \(ircMessage)")
        return ircMessage
    }
    

    
    func parseCommand(
        command: String,
        commandKey: IRCCommandKey
    ) throws -> IRCCommandKey? {
        var commandKey = commandKey
        if !command.isEmpty {
            guard let firstCharacter = command.first else { throw MessageParserError.firstCharacterIsNil }
            if firstCharacter.isLetter {
                commandKey = .string(String(command))
            } else {
                let command = command.components(separatedBy: .decimalDigits.inverted)
                for c in command {
                    if !c.isEmpty{
                        commandKey = .int(Int(c) ?? 0)
                    }
                }
            }
        }
        self.logger.info("Parsing CommandKey - \(commandKey)")
        return commandKey
    }
    
    func parseArguments(
        commandMessage: String,
        commandSubstring: String,
        stripedMessage: String
    ) throws -> [String]? {
        var args = [String]()
        guard let firstCharacter = commandSubstring.first else { throw MessageParserError.firstCharacterIsNil }
        if commandSubstring.hasPrefix("NICK") || commandSubstring.hasPrefix("JOIN") {
            args.append(commandMessage)
        } else if commandSubstring.hasPrefix("USER") {
            let initialBreak = commandMessage.components(separatedBy: " :")
            var spreadArgs = initialBreak[0].components(separatedBy: " ")
            spreadArgs.append(initialBreak[1])
            args = spreadArgs
        } else if commandSubstring.hasPrefix("PRIVMSG") {
            let initialBreak = stripedMessage.components(separatedBy: " ")
            var newArgArray: [String] = []
            newArgArray.append(initialBreak[1])
            newArgArray.append(initialBreak[2])
            args = newArgArray
        } else if commandSubstring.hasPrefix("READKEYBNDL") || commandSubstring.hasPrefix("PUBKEYBNDL") || commandSubstring.hasPrefix("REGAPN") {
            let seperated = stripedMessage.components(separatedBy: ":")
            args.append(seperated[1])
        } else if commandMessage.hasPrefix("MODE") {
            let seperated = commandMessage.components(separatedBy: " ")
            args.append(seperated[1])
        } else if !firstCharacter.isLetter {
            let seperated = stripedMessage.components(separatedBy: ":")
            guard let argument = seperated.last?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
            args.append(argument)
        }
        self.logger.info("Parsing Arguments - \(args)")
        return args
    }
//    2022-03-24T08:23:43+0800 info IRCTask -  : Parsing Message.... REGAPN :twEAAAJqd3QADAEAAGV5SmhiR2NpT2lKbFpESTFOVEU1SWl3aWRIbHdJam9pU2xkVUluMC5leUpsZUhBaU9qRTJORGd3T0RVd01qTXVPRFUzTURBMU1Td2laR1YyYVdObElqcDdJblZ6WlhJaU9pSnVaV1ZrYkdWMFlXbHNJaXdpWkdWMmFXTmxJam9pTnpWaFl6UmhaVE10WmpreVpDMDBaVGxpTFRobU1qQXRNR000WlRJd1lURmlNV013SW4xOS5fQ2s2WHJlaVBFaTR1UGNyU1NTT2hzUVpkdUVTUGhLZExOQnhFYU00aWFwcld4WGZ3dU9yQWxUcGhaVm5QdXlQZ0ktcUw0c3luZ3NRb1pBdWNJYVdDdwACYXBwbGVUb2tlbgBBAAAAODYwMjZhZDQ5NzY2MjVkZTJjNWJjYjViMWMzOTQzZTdlMWZlMmNlNWY5NGJjYTRjYzM5NTQ2Mzk0MGI1N2Y5YQACdXNlcm5hbWUACwAAAG5lZWRsZXRhaWwAAmRldmljZUlkACUAAAA3NWFjNGFlMy1mOTJkLTRlOWItOGYyMC0wYzhlMjBhMWIxYzAAAA==
//    2022-03-24T08:23:43+0800 info IRCTask -  : Parsing CommandKey - string("REGAPN")
//    2022-03-24T08:23:43+0800 info IRCTask -  : Parsing Arguments - []
// https://ircv3.net/specs/extensions/message-tags.html#format
    func parseTags(
        tags: String = ""
    ) async throws -> [IRCTags]? {
        if tags.hasPrefix("@") {
            var tagArray: [IRCTags] = []
            let seperatedTags = tags.components(separatedBy: ";@")
            for tag in seperatedTags {
                var tag = tag
                tag.removeAll(where: { $0 == "@" })
                var ircTag: IRCTags
                let kvpArray = tag.components(separatedBy: "=")
                if  String(tag.characters.suffix(2)) == "==" {
                    ircTag = IRCTags(key: kvpArray[0], value: "\(kvpArray[1])==")
                } else {
                    ircTag = IRCTags(key: kvpArray[0], value: kvpArray[1])
                }
                tagArray.append(ircTag)
            }
            self.logger.info("Parsing Tags - \(tags)")
            return tagArray
        }
        return nil
    }
}

