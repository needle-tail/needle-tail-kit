import NIOCore
    
public final class NeedleTailEncoder {
    
//    [':' SOURCE]? ' ' COMMAND [' ' ARGS]? [' :' LAST-ARG]?
    public class func encode(
        value: IRCMessage
    ) async -> ByteBuffer {
        var newTag = ""
        var newOrigin = ""
        var newTarget = ""
        var newString = ""
        let command = value.command.commandAsString
        
        if value.tags != [], value.tags != nil {
            for tag in value.tags ?? [] {
                newTag += Constants.atString + tag.key + Constants.equalsString + tag.value + Constants.semiColon
            }
            newTag = newTag + Constants.space
        }
        
        if let origin = value.origin, !origin.isEmpty {
            newOrigin = Constants.colon + origin + Constants.space
        }
        
        if let target = value.target {
            newTarget = Constants.space + target
        }
        
        let base = newTag + newOrigin + command + newTarget

        switch value.command {
            
        case .NICK(let v), .MODEGET(let v):
            newString = base + Constants.space + v.stringValue
            
        case .USER(let userInfo):
            let userBase = base + Constants.space + userInfo.username
            if let mask = userInfo.usermask {
                newString = userBase + Constants.space + String(mask.maskValue) + Constants.space + Constants.star
            } else {
                newString = userBase + Constants.space + (userInfo.hostname ?? Constants.star) + Constants.space + (userInfo.servername ?? Constants.star)
            }
            newString += Constants.space + Constants.colon + userInfo.realname
            
        case .ISON(let nicks):
            newString += base + Constants.space + arguments(nicks.lazy.map({ $0.stringValue }))
            
        case .QUIT(.none):
            break
        case .QUIT(.some(let value)):
            newString = base + Constants.space + Constants.colon + value
            
        case .PING(server: let server, server2: let server2),
                .PONG(server: let server, server2: let server2):
            if let server2 = server2 {
                //TODO: This is probably wrong
                newString = base + argumentsWithLast([server]) + Constants.space + Constants.colon + argumentsWithLast([server2])
            } else {
                newString = base + argumentsWithLast([server])
            }
            
        case .JOIN(channels: let channels, keys: let keys):
            newString = base + Constants.space
            newString += commaSeperatedValues(channels.lazy.map({ $0.stringValue }))
            if let keys = keys {
                newString += commaSeperatedValues(keys)
            }
            
        case .JOIN0:
            newString = base + Constants.space + Constants.star
            
        case .PART(channels: let channels):
            newString = base + commaSeperatedValues(channels.lazy.map({ $0.stringValue }))
            
        case .LIST(channels: let channels, target: let target):
            if let channels = channels {
                newString = base + commaSeperatedValues(channels.lazy.map({ $0.stringValue }))
            } else {
                newString = base + Constants.space + Constants.star
            }
            if let target = target {
                newString += Constants.space + Constants.colon + target
            }
            
        case .PRIVMSG(let recipients, let message),
                .NOTICE(let recipients, let message):
            newString = base + commaSeperatedValues(recipients.lazy.map({ $0.stringValue }))
            newString += Constants.space + Constants.colon + message
        case .MODE(let nick, add: let add, remove: let remove):
            newString = base + Constants.space + nick.stringValue
            let adds = add.stringValue.map({ "\(Constants.plus)\($0)" })
            let removes = remove.stringValue.map({ "\(Constants.minus)\($0)" })
            
            if add.isEmpty && remove.isEmpty {
                newString += Constants.space + Constants.colon
            } else {
                newString += arguments(adds) + arguments(removes) + argumentsWithLast()
            }
            
        case .CHANNELMODE(let channel, add: let add, remove: let remove):
            let adds = add.stringValue.map({ "\(Constants.plus)\($0)" })
            let removes = remove.stringValue.map({ "\(Constants.minus)\($0)" })
            
            newString = base + Constants.space + channel.stringValue
            newString += arguments(adds) + arguments(removes) + argumentsWithLast()
            
        case .CHANNELMODE_GET(let value):
            newString = base + Constants.space + value.stringValue
            
        case .CHANNELMODE_GET_BANMASK(let value):
            newString = base + Constants.space + Constants.bString + Constants.space + value.stringValue
        case .WHOIS(server: let server, usermasks: let usermasks):
            newString = base
            if let target = server {
                newString += Constants.space + target
            }
            newString += Constants.space + usermasks.joined(separator: Constants.comma)
            
        case .WHO(usermask: let usermask, onlyOperators: let onlyOperators):
            newString += base
            if let mask = usermask {
                newString += Constants.space + mask
                if onlyOperators {
                    newString += Constants.space + Constants.oString
                }
            }
        case .KICK(let channels, let users, let comments):
            newString = base + Constants.space
            newString += commaSeperatedValues(channels.lazy.map({ $0.stringValue }))
            newString += commaSeperatedValues(users.lazy.map({ $0.stringValue }))
            newString += commaSeperatedValues(comments.lazy.map({ $0 }))
        case .KILL(let nick, let comment):
            newString = base + Constants.space + nick.stringValue + comment
        case .numeric(_, let args),
                .otherCommand(_, let args),
                .otherNumeric(_, let args):
                newString = base + argumentsWithLast(args)
        case .CAP(let subCommand, let capabilityIds):
            newString = base + Constants.space + subCommand.commandAsString + Constants.space + Constants.colon
            newString += capabilityIds.joined(separator: Constants.space)
        }
        newString += Constants.cCR + Constants.cLF
        return ByteBuffer(string: newString)
    }
    
    private class func arguments(_ args: [String] = [""]) -> String {
        var newString = ""
        for arg in args {
            newString += Constants.space + arg
        }
        return newString
    }
    
    //This method is used to recreate the last arguement in order for it to start with a colon. This is according to IRC syntax design.
    private class func argumentsWithLast(_ args: [String] = [""]) -> String {
        guard !args.isEmpty else { return "" }
        var newString = ""
            for arg in args.dropLast() {
                newString += Constants.space + arg
            }
        let lastIdx = args.index(args.startIndex, offsetBy: args.count - 1)
        return newString + Constants.space + Constants.colon + args[lastIdx]
    }
    
    private class func commaSeperatedValues(_ args: [String] = [""]) -> String {
        var newString = Constants.space
        var isFirst = true
        for arg in args {
            if isFirst {
                isFirst = false
            } else {
                newString += Constants.comma
            }
            newString += arg
        }
        return newString
    }
}
