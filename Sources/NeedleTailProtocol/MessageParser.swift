import Foundation
import Logging
import NeedleTailHelpers
import NIOConcurrencyHelpers

public struct MessageParser: Sendable {
    
    let logger = Logger(label: "MessageParser")
    
    enum IRCCommandKey {
        case int(Int)
        case string(String)
    }
    
    public init() {}
    
    internal func parseMessage(_ message: String) throws -> IRCMessage {
        var ircMessage: IRCMessage
        var origin: String?
        var seperatedTags: [String] = []
        var stripedMessage: String = ""
        var commandKey: IRCCommandKey = .string("")
        
        self.logger.trace("Parsing Message....")
        
        /// IRCMessage sytax
        /// ::= ['@' <tags> SPACE] [':' <source> SPACE] <command> <parameters> <crlf>
        ///We are seperating our tags from our message string before we process the rest of our message
        if message.contains(Constants.atString.rawValue) && message.contains(Constants.semiColonSpace.rawValue) {
            seperatedTags.append(contentsOf: message.components(separatedBy: Constants.semiColonSpace.rawValue))
            stripedMessage = seperatedTags[1]
        } else {
            stripedMessage = message
        }
        guard let firstSpaceIndex = stripedMessage.firstIndex(of: Character(Constants.space.rawValue)) else {
            throw MessageParserError.messageWithWhiteSpaceNil
        }
        
        var command = ""
        var parameter = ""
        ///This strippedMessage represents our irc message portion without tags. If we have the source then we will get the source here
        
        /// Always our origin
        if stripedMessage.hasPrefix(Constants.colon.rawValue) {
            let source = stripedMessage[..<firstSpaceIndex]
            origin = String(source)
        }
        let spreadStriped = stripedMessage.components(separatedBy: Constants.space.rawValue)
        
        ///If we get an origin back from the server it will be preceeded with a :. So we are using it to determine the command type.
        if stripedMessage.hasPrefix(Constants.colon.rawValue) {
            precondition(spreadStriped.count >= 2)
            command = spreadStriped[1]
            if spreadStriped.count >= 3 {
                parameter = spreadStriped[2]
            }
        } else {
            precondition(spreadStriped.count == 2)
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
        
        let (arguments, target) = parseArgument(
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
            ///
            if let unwrappedOrigin = origin {
                if unwrappedOrigin.hasPrefix(Constants.colon.rawValue),
                   unwrappedOrigin.contains(Constants.atString.rawValue) && unwrappedOrigin.contains(Constants.exclamation.rawValue) {
                    let seperatedJoin = unwrappedOrigin.components(separatedBy: Constants.exclamation.rawValue)
                    origin = seperatedJoin.first?.replacingOccurrences(of: Constants.colon.rawValue, with: Constants.none.rawValue)
                } else if unwrappedOrigin.hasPrefix(Constants.colon.rawValue) {
                    origin = unwrappedOrigin.replacingOccurrences(of: Constants.colon.rawValue, with: Constants.none.rawValue)
                }
            }
            let command = try IRCCommand(commandKey, arguments: arguments)
            ircMessage = IRCMessage(origin: origin,
                                    target: target,
                                    command: command,
                                    arguments: arguments,
                                    tags: tags
            )
            
        case .int(let commandKey):
            if origin?.hasPrefix(Constants.colon.rawValue) != nil {
                origin = origin?.replacingOccurrences(of: Constants.colon.rawValue, with: Constants.none.rawValue)
            }
            let command = try IRCCommand(commandKey, arguments: arguments)
            ircMessage = IRCMessage(origin: origin,
                                    target: target,
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
    
    //Private Message Example -    :Angel!wings@irc.org PRIVMSG Wiz :Are you receiving this message ?
    func parseArgument(
        commandKey: IRCCommandKey,
        message: String,
        commandMessage: String,
        stripedMessage: String,
        parameter: String,
        origin: String?
    ) -> ([String], String?) {
        
        var seperatedArgumentesByComponent = [String]()
        var target: String?
        
        switch commandKey {
        case .int(let commandInt):
            //            ":origin1 303 target1 :userOne_123456789 userTwo_987654321"
            //            ":origin1 303 :userOne_123456789 userTwo_987654321"
            var commandString = String(commandInt)
            if commandString.count == 1 {
                commandString = "00" + commandString
            }
            
            let seperatedArguments = parse(stripedMessage: stripedMessage, from: commandString)
            //Last Argument
            if let messageIndex = seperatedArguments.firstIndex(where: { $0.hasPrefix(Constants.colon.rawValue) }) {
                let initialIndex = seperatedArguments[..<messageIndex].joined(separator: Constants.space.rawValue)
                let initialArgument = initialIndex.components(separatedBy: Constants.space.rawValue).joined(separator: Constants.space.rawValue)
                
                let message = seperatedArguments[messageIndex...].joined(separator: Constants.space.rawValue)
                let seperatedMessage = message.components(separatedBy: Constants.space.rawValue).joined(separator: Constants.space.rawValue).dropFirst()
                if commandInt == 303 {
                    seperatedArgumentesByComponent.append(contentsOf: seperatedMessage.components(separatedBy: Constants.comma.rawValue))
                } else {
                    seperatedArgumentesByComponent.append(contentsOf: [String(seperatedMessage)])
                }
            }
        case .string(let commandString):
            var arguments = [String]()
            let seperatedArguments = parse(stripedMessage: stripedMessage, from: commandString)
            //Last Argument
            if let messageIndex = seperatedArguments.firstIndex(where: { $0.hasPrefix(Constants.colon.rawValue) }) {
                let initialComponents = seperatedArguments[..<messageIndex].joined(separator: Constants.space.rawValue)
                let commaSeparatedArgs = initialComponents.components(separatedBy: Constants.space.rawValue)
                
                if commaSeparatedArgs.first?.isChannel == true {
                    let channels = commaSeparatedArgs.filter({ $0.isChannel })
                    if !channels.isEmpty {
                        arguments.append(channels.joined(separator: Constants.space.rawValue))
                    }
                    
                    let targets = commaSeparatedArgs.filter({ !channels.contains($0) })
                    arguments.append(contentsOf: targets)
                    
                    let lastArgument = Array(seperatedArguments[messageIndex...]).joined(separator: Constants.space.rawValue)
                    if commandString == Constants.kick.rawValue {
                        let channels = channels.joined(separator: Constants.space.rawValue)
                        let targets = targets.joined(separator: Constants.space.rawValue)
                        seperatedArgumentesByComponent.append(contentsOf: [channels, targets, String(lastArgument.dropFirst())])
                    } else {
                        let argumentString = arguments.joined(separator: Constants.space.rawValue)
                        seperatedArgumentesByComponent.append(contentsOf: [argumentString, String(lastArgument.dropFirst())])
                    }
                } else {
                    if commandString.isOtherCommand && commandString != Constants.multipartMediaUpload.rawValue {
                        let initialArguements = seperatedArguments[..<messageIndex]
                        let lastArgument = seperatedArguments[messageIndex...]
                            .joined(separator: Constants.space.rawValue)
                            .dropFirst()
                            .components(separatedBy: Constants.comma.rawValue)
                            .filter({ !$0.isEmpty })
                            .map({ $0.replacing(Constants.space.rawValue, with: Constants.none.rawValue) })
                        seperatedArgumentesByComponent.append(contentsOf: initialArguements + lastArgument)
                        
                        //If we are multipart this is probably a huge message that we want to parse further away from the inbound stream....
                    } else if commandString.isOtherCommand, commandString == Constants.multipartMediaUpload.rawValue || commandString == Constants.multipartMediaDownload.rawValue {
                            let initialArguements = seperatedArguments[..<messageIndex]
                            let lastArgument = seperatedArguments[messageIndex...]
                            seperatedArgumentesByComponent = seperatedArguments
                    } else {
                        let initialArguements = seperatedArguments[..<messageIndex]
                        let lastArgument = seperatedArguments[messageIndex...].joined(separator: Constants.space.rawValue)
                        seperatedArgumentesByComponent.append(contentsOf: initialArguements + [String(lastArgument.dropFirst())])
                    }
                }
            } else {
                //No comments so no colon is expected in the irc message... parse origin, targets
                if let targetIndex = seperatedArguments.firstIndex(where: { !$0.hasPrefix(Constants.hashTag.rawValue) }), targetIndex > 1 {
                    let originArgument = seperatedArguments[..<targetIndex].joined(separator: Constants.space.rawValue)
                    let targetArgument = seperatedArguments[targetIndex...].joined(separator: Constants.space.rawValue)
                    seperatedArgumentesByComponent.append(contentsOf: [originArgument, targetArgument])
                } else {
                    if commandString == Constants.mode.rawValue {
                        guard let channel = seperatedArguments.first else { return ([], nil) }
                        let modeSetting = seperatedArguments.dropFirst()
                        if !modeSetting.isEmpty {
                            seperatedArgumentesByComponent.append(contentsOf: [channel, modeSetting.joined()])
                        } else {
                            seperatedArgumentesByComponent.append(contentsOf: [channel])
                        }
                    } else {
                        seperatedArgumentesByComponent.append(seperatedArguments.joined(separator: Constants.space.rawValue))
                    }
                }
            }
        }
        return (seperatedArgumentesByComponent, nil)
    }
    
    /// Seperates the arguments from the Command in an IRCMessage String
    /// - Parameters:
    ///   - stripedMessage: Striped Message
    ///   - commandKey: CommandKey
    /// - Returns: Arguements
    private func parse(stripedMessage: String, from commandKey: String) -> [String] {
        let seperatedMessage = stripedMessage.components(separatedBy: Constants.space.rawValue).filter({ !$0.isEmpty})
        guard let commandIndex = seperatedMessage.firstIndex(of: commandKey) else { return [] }
        return Array(seperatedMessage[commandIndex.advanced(by: 1)...])
    }
    
    // https://ircv3.net/specs/extensions/message-tags.html#format
    func parseTags(
        tags: String = ""
    ) throws -> [IRCTags]? {
        if tags.hasPrefix(Constants.atString.rawValue) {
            var tagArray: [IRCTags] = []
            let seperatedTags = tags.components(separatedBy: Constants.semiColon.rawValue + Constants.atString.rawValue)
            for tag in seperatedTags {
                var tag = tag
                tag.removeAll(where: { $0 == Character(Constants.atString.rawValue) })
                let kvpArray = tag.split(separator: Character(Constants.equalsString.rawValue), maxSplits: 1)
                guard let key = kvpArray.first else { return nil }
                guard let value = kvpArray.last else { return nil }
                tagArray.append(
                    IRCTags(key: String(key), value: String(value))
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
    case firstArgumentIsMissing
    case lastArgumentIsMissing
}

extension String: Sendable {
    var isInt: Bool {
        return Int(self) != nil
    }
}

extension Int {
    var argumentIsArray: Bool {
        self == 303 ? true : false
    }
}


extension String {
    var isChannel: Bool {
        hasPrefix(Constants.ampersand.rawValue) || hasPrefix(Constants.hashTag.rawValue) || hasPrefix(Constants.plus.rawValue) || hasPrefix(Constants.exclamation.rawValue)
    }
    
    var isOtherCommand: Bool {
        self == Constants.badgeUpdate.rawValue || self == Constants.multipartMediaDownload.rawValue || self == Constants.multipartMediaUpload.rawValue || self == Constants.listBucket.rawValue || self == Constants.blobs.rawValue || self == Constants.readKeyBundle.rawValue || self == Constants.pass.rawValue || self == Constants.deleteOfflineMessage.rawValue || self == Constants.offlineMessages.rawValue || self == Constants.requestMediaDeletion.rawValue
    }
    
    var isNumeric: Bool {
        self.isInt
    }
}
