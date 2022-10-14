
import NIO
import Foundation
import Logging
import NeedleTailHelpers

@ParsingActor
public final class MessageParser {
    
    enum IRCCommandKey {
        case int   (Int)
        case string(String)
    }
    var logger: Logger
    
    init() {
        self.logger = Logger(label: "MessageParser")
    }
    
    
    internal func parseMessage(_ message: String) async throws -> IRCMessage {
        var ircMessage: IRCMessage
        var origin: String?
        var seperatedTags: [String] = []
        var stripedMessage: String = ""
        var commandKey: IRCCommandKey = .string("")
        self.logger.trace("Parsing Message....")
        
        /// IRCMessage sytax
        /// ::= ['@' <tags> SPACE] [':' <source> SPACE] <command> <parameters> <crlf>
        
        ///We are seperating our tags from our message string before we process the rest of our message
        if message.contains("@") && message.contains("; ") {
            seperatedTags.append(contentsOf: message.components(separatedBy: "; "))
            stripedMessage = seperatedTags[1]
        } else {
            stripedMessage = message
        }
        
        guard let firstSpaceIndex = stripedMessage.firstIndex(of: " ") else {
            throw MessageParserError.messageWithWhiteSpaceNil
        }
        var command = ""
        var parameter = ""
        ///This strippedMessage represents our irc message portion without tags. If we have the source then we will get the source here
        
        /// Always our origin
        if stripedMessage.hasPrefix(":") {
            let source = stripedMessage[..<firstSpaceIndex]
            origin = String(source)
        }
        let spreadStriped = stripedMessage.components(separatedBy: " ")
        
        ///If we get an origin back from the server it will be preceeded with a :. So we are using it to determine the command type.
        if stripedMessage.hasPrefix(":") {
            command = spreadStriped[1]
            parameter = spreadStriped[2]
        } else {
            command = spreadStriped[0]
            parameter = spreadStriped[1]
        }
        
        guard let command = try parseCommand(
            command: command,
            commandKey: commandKey
        ) else { throw MessageParserError.commandIsNil}
        
        commandKey = command
        
        
        let rest = stripedMessage[firstSpaceIndex...].trimmingCharacters(in: .whitespacesAndNewlines)
        let commandIndex = rest.startIndex
        let commandMessage = rest[commandIndex...]
        
        guard let arguments = try parseArgument(
            commandKey: commandKey,
            message: message,
            commandMessage: String(commandMessage),
            stripedMessage: stripedMessage,
            parameter: parameter
        ) else { throw MessageParserError.argumentsAreNil }
        
        var tags: [IRCTags]?
        if seperatedTags != [] {
            tags = try parseTags(
                tags: seperatedTags[0]
            )
        }
        
        
        switch commandKey {
        case .string(let commandKey):
            /// Potential origins
            /// :needletail!needletail@localhost JOIN #NIO
            /// :someBase64EncodedString JOIN #NIO
            if let unwrappedOrigin = origin {
                if unwrappedOrigin.hasPrefix(":"),
                   unwrappedOrigin.contains("@") && unwrappedOrigin.contains("!") {
                    let seperatedJoin = unwrappedOrigin.components(separatedBy: "!")
                    origin = seperatedJoin[0].replacingOccurrences(of: ":", with: "")
                } else if unwrappedOrigin.hasPrefix(":") {
                    origin = unwrappedOrigin.replacingOccurrences(of: ":", with: "")
                }
            }
            
            ircMessage = IRCMessage(origin: origin,
                                    command: try IRCCommand(commandKey, arguments: arguments), tags: tags)
        case .int(let commandKey):
            if origin?.hasPrefix(":") != nil {
                origin = origin?.replacingOccurrences(of: ":", with: "")
            }
            ircMessage = IRCMessage(origin: origin,
                                    command: try IRCCommand(commandKey, arguments: arguments), tags: tags)
            
        }
        self.logger.trace("Parsed Message")
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
        self.logger.trace("Parsing CommandKey")
        return commandKey
    }
    
    func parseArgument(
        commandKey: IRCCommandKey,
        message: String,
        commandMessage: String,
        stripedMessage: String,
        parameter: String
    ) throws -> [String]? {
        
        var args = [String]()
        switch commandKey {
        case .int(let int):
            //            :localhost 332 Guest31 #NIO :Welcome to #nio!
            var spread = message.components(separatedBy: " ")
            guard spread.count >= 4 else { return nil }
            let right = spread[4...]
            let left = spread[0...3]
            spread = Array(left)
            let rightArray = Array(right)
            let joinedString = rightArray.joined(separator: " ")
            let newArray = spread + [joinedString]
            
            //If we replyKeyBundle or replyInfo we need to do a bit more parsing
            if int == 270 || int == 371 {
                let chunk = newArray[3].dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
                let components = chunk.components(separatedBy: "\r\n")
                args.append(components[0])
            } else {
                args.append(contentsOf: newArray)
            }
        case .string(let commandKey):
            if commandKey.hasPrefix("NICK") || commandKey.hasPrefix("JOIN") || commandKey.hasPrefix("PART") {
                args.append(parameter)
            } else if commandKey.hasPrefix("USER") {
                let initialBreak = commandMessage.components(separatedBy: " :")
                var spreadArgs = initialBreak[0].components(separatedBy: " ")
                spreadArgs.append(initialBreak[1])
                args = spreadArgs
            } else if commandKey.hasPrefix("PRIVMSG") {
                let initialBreak = stripedMessage.components(separatedBy: " ")
                var newArgArray: [String] = []
                newArgArray.append(initialBreak[initialBreak.count <= 3 ? 1 : 2])
                newArgArray.append(String("\(initialBreak[initialBreak.count <= 3 ? 2 : 3])".dropFirst()))
                args = newArgArray
            } else if commandKey.hasPrefix("MODE") {
                let seperated = commandMessage.components(separatedBy: " ")
                args.append(seperated[1])
            } else if commandKey.hasPrefix("REGISTRYREQUEST") ||
                        commandKey.hasPrefix("REGISTRYRESPONSE") ||
                        commandKey.hasPrefix("NEWDEVICE") ||
                        commandKey.hasPrefix("READKEYBNDL") ||
                        commandKey.hasPrefix("PASS") ||
                        commandKey.hasPrefix("BLOBS") ||
                        commandKey.hasPrefix("QUIT") {
                var stripedMessage = stripedMessage
                if stripedMessage.first == ":" {
                    stripedMessage = String(stripedMessage.dropFirst())
                }
                let seperated = stripedMessage.components(separatedBy: ":")
                args.append(seperated[1])
            }
        }
        return args
    }

    // https://ircv3.net/specs/extensions/message-tags.html#format
    func parseTags(
        tags: String = ""
    ) throws -> [IRCTags]? {
        if tags.hasPrefix("@") {
            var tagArray: [IRCTags] = []
            let seperatedTags = tags.components(separatedBy: ";@")
            for tag in seperatedTags {
                var tag = tag
                tag.removeAll(where: { $0 == "@" })
                let kvpArray = tag.split(separator: "=", maxSplits: 1)
                tagArray.append(
                    IRCTags(key: String(kvpArray[0]), value: String(kvpArray[1]))
                )
            }
            self.logger.trace("Parsing Tags")
            return tagArray
        }
        return nil
    }
}


public enum MessageParserError: Error, Sendable {
    case rangeNotFound
    case firstCharacterIsNil
    case argumentsAreNil
    case commandIsNil
    case originIsNil
    case firstIndexChoiceNil
    case messageWithTagsNil
    case messageWithWhiteSpaceNil
    case invalidPrefix(Data)
    case invalidCommand(Data)
    case tooManyArguments(Data)
    case invalidArgument(Data)
    case invalidArgumentCount(command: String, count: Int, expected: Int)
    case invalidMask(command: String, mask: String)
    case invalidChannelName(String)
    case invalidNickName(String)
    case invalidMessageTarget(String)
    case invalidCAPCommand(String)
    case transportError(Error)
    case syntaxError
    case notImplemented
    case jobFailedToParse
}
