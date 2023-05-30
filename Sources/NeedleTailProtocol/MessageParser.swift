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
    
    public init() {
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
        if message.contains(Constants.atString) && message.contains(Constants.semiColonSpace) {
            seperatedTags.append(contentsOf: message.components(separatedBy: Constants.semiColonSpace))
            stripedMessage = seperatedTags[1]
        } else {
            stripedMessage = message
        }
        
        guard let firstSpaceIndex = stripedMessage.firstIndex(of: Character(Constants.space)) else {
            throw MessageParserError.messageWithWhiteSpaceNil
        }
        var command = ""
        var parameter = ""
        ///This strippedMessage represents our irc message portion without tags. If we have the source then we will get the source here
        
        /// Always our origin
        if stripedMessage.hasPrefix(Constants.colon) {
            let source = stripedMessage[..<firstSpaceIndex]
            origin = String(source)
        }
        let spreadStriped = stripedMessage.components(separatedBy: Constants.space)
        
        ///If we get an origin back from the server it will be preceeded with a :. So we are using it to determine the command type.
        if stripedMessage.hasPrefix(Constants.colon) {
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
        
        let arguments = parseArgument(
            commandKey: commandKey,
            message: message,
            commandMessage: String(commandMessage),
            stripedMessage: stripedMessage,
            parameter: parameter,
            origin: origin
        )
        
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
                if unwrappedOrigin.hasPrefix(Constants.colon),
                   unwrappedOrigin.contains(Constants.atString) && unwrappedOrigin.contains(Constants.exclamation) {
                    let seperatedJoin = unwrappedOrigin.components(separatedBy: Constants.exclamation)
                    origin = seperatedJoin[0].replacingOccurrences(of: Constants.colon, with: Constants.none)
                } else if unwrappedOrigin.hasPrefix(Constants.colon) {
                    origin = unwrappedOrigin.replacingOccurrences(of: Constants.colon, with: Constants.none)
                }
            }
            let command = try IRCCommand(commandKey, arguments: arguments)
            ircMessage = IRCMessage(origin: origin,
                                    command: command,
                                    arguments: arguments,
                                    tags: tags
            )
            
        case .int(let commandKey):
            if origin?.hasPrefix(Constants.colon) != nil {
                origin = origin?.replacingOccurrences(of: Constants.colon, with: Constants.none)
            }
            let command = try IRCCommand(commandKey, arguments: arguments)
            ircMessage = IRCMessage(origin: origin,
                                    command: command,
                                    arguments: arguments,
                                    tags: tags
            )
            
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
        parameter: String,
        origin: String?
    ) -> [String] {
        
        var args = [String]()
        switch commandKey {
        case .int(let int):
            //            :localhost 332 Guest31 #NIO :Welcome to #nio!
            var spread = message.components(separatedBy: Constants.space)
            guard spread.count >= 4 else { return [] }
            let right = spread[4...]
            let left = spread[0...3]
            spread = Array(left)
            let rightArray = Array(right)
            let joinedString = rightArray.joined(separator: Constants.space)
            let newArray = spread + [joinedString]
            
            args.append(
                createArgFromIntCommand(newArray, command: int)
            )
            
        case .string(let commandKey):
            if commandKey.hasPrefix(Constants.nick) ||
                commandKey.hasPrefix(Constants.join) ||
                commandKey.hasPrefix(Constants.part) {
                args.append(parameter)
            }  else if commandKey.hasPrefix(Constants.ping) ||
                        commandKey.hasPrefix(Constants.pong) {
                if parameter.hasPrefix(Constants.colon) {
                    args.append(String(parameter.dropFirst()))
                } else {
                    args.append(parameter)
                }
            } else if commandKey.hasPrefix(Constants.user) {
                let initialBreak = commandMessage.components(separatedBy: Constants.space + Constants.colon)
                var spreadArgs = initialBreak[0].components(separatedBy: Constants.space)
                spreadArgs.append(initialBreak[1])
                args = spreadArgs
            } else if commandKey.hasPrefix(Constants.privMsg) {
                let initialBreak = stripedMessage.components(separatedBy: Constants.space)
                var newArgArray: [String] = []
                newArgArray.append(initialBreak[initialBreak.count <= 3 ? 1 : 2])
                newArgArray.append(String("\(initialBreak[initialBreak.count <= 3 ? 2 : 3])".dropFirst()))
                args = newArgArray
            } else if commandKey.hasPrefix(Constants.mode) {
                let seperated = commandMessage.components(separatedBy: Constants.space)
                args.append(seperated[1])
            } else if commandKey.hasPrefix(Constants.kill) {
                let seperatedCommand = stripedMessage.components(separatedBy: commandKey)
                let spread = seperatedCommand[1].components(separatedBy: Constants.space).filter({ !$0.isEmpty })
                args.append(contentsOf: [spread[0], spread.dropFirst().joined(separator: " ")])
            } else if commandKey.hasPrefix(Constants.kick) {
                //TODO: 
                //               print(stripedMessage)
                break
            } else if commandKey.hasPrefix(Constants.registryRequest) ||
                        commandKey.hasPrefix(Constants.registryResponse) ||
                        commandKey.hasPrefix(Constants.newDevice) ||
                        commandKey.hasPrefix(Constants.readKeyBundle) ||
                        commandKey.hasPrefix(Constants.pass) ||
                        commandKey.hasPrefix(Constants.blobs) ||
                        commandKey.hasPrefix(Constants.offlineMessages) ||
                        commandKey.hasPrefix(Constants.deleteOfflineMessage) ||
                        commandKey.hasPrefix(Constants.quit) ||
                        commandKey.hasPrefix(Constants.badgeUpdate) ||
                        commandKey.hasPrefix(Constants.multipartMedia) {
                var stripedMessage = stripedMessage
                
                if stripedMessage.contains(commandKey) {
                    let seperatedCommand = stripedMessage.components(separatedBy: commandKey)
                    let joined = seperatedCommand.joined(separator: " ")
                    stripedMessage = joined
                }
                
                if stripedMessage.first == Character(Constants.space) {
                    stripedMessage = String(stripedMessage.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines))
                }
                
                if stripedMessage.first == Character(Constants.colon) {
                    stripedMessage = String(stripedMessage.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines))
                }
                
                let seperatedArguments = stripedMessage.components(separatedBy: Constants.colon)
                
                let origin = origin ?? ""
                if seperatedArguments.first?.trimmingCharacters(in: .whitespacesAndNewlines) == String(origin.dropFirst()) {
                    for argument in seperatedArguments.dropFirst() {
                        guard !argument.isEmpty else { break }
                        args.append(argument.trimmingCharacters(in: .whitespaces))
                    }
                } else {
                    for argument in seperatedArguments {
                        guard !argument.isEmpty else { break }
                        args.append(argument.trimmingCharacters(in: .whitespaces))
                    }
                }
            }
        }
        return args
    }
    
    private func createArgFromIntCommand(_ newArray: [String], command: Int) -> String {
        //If we replyKeyBundle or replyInfo we need to do a bit more parsing
        if command == 270 || command == 371 {
            let chunk = newArray[3].dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
            let components = chunk.components(separatedBy: Constants.cCR + Constants.cLF)
            return components[0]
        } else {
            return dropColon(from: newArray, command: command)
        }
    }
    
    private func dropColon(from newArray: [String], command: Int) -> String {
        if newArray[3].isInt, newArray[4].first == Character(Constants.colon) {
            return newArray[3] + Constants.space + String(newArray[4].dropFirst())
        } else if newArray[3].first == Character(Constants.colon) {
            return String(newArray[3].dropFirst()) + Constants.space + String(newArray[4])
        } else {
            if newArray[4].contains(Constants.colon) {
                let split = newArray[4].components(separatedBy: Constants.colon)
                return newArray[3] + Constants.space + String(split.joined())
            } else {
                return newArray[3] + Constants.space + String(newArray[4])
            }
        }
    }
    
    // https://ircv3.net/specs/extensions/message-tags.html#format
    func parseTags(
        tags: String = ""
    ) throws -> [IRCTags]? {
        if tags.hasPrefix(Constants.atString) {
            var tagArray: [IRCTags] = []
            let seperatedTags = tags.components(separatedBy: Constants.semiColon + Constants.atString)
            for tag in seperatedTags {
                var tag = tag
                tag.removeAll(where: { $0 == Character(Constants.atString) })
                let kvpArray = tag.split(separator: Character(Constants.equalsString), maxSplits: 1)
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

extension String {
    var isInt: Bool {
        return Int(self) != nil
    }
}
