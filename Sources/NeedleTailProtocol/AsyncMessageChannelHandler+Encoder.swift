import NIOCore

extension AsyncMessageChannelHandler {
    
    func encode(
        value: IRCMessage
    ) async -> ByteBuffer {
        var newTag = ""
        var newOrigin = ""
        var newTarget = ""
        var newString = ""
        let cCR = "\r"
        let cLF = "\n"
        let star = "*"
        let colon = ":"
        let comma = ","
        let space = " "
        let bString = "b"
        let oString = "o"
        let plus = "+"
        let minus = "-"
        let atString = "@"
        let equalsString = "="
        let semiColon = ";"
        let command = value.command.commandAsString
        
        
        if value.tags != [], value.tags != nil {
            for tag in value.tags ?? [] {
                newTag += atString + tag.key + equalsString + tag.value + semiColon
            }
            newTag = newTag + space
        }
        
        if let origin = value.origin, !origin.isEmpty {
            newOrigin = colon + origin + space
        }
        
        if let target = value.target {
            newTarget = space + target
        }
        
        let base = newTag + newOrigin + command + newTarget

        switch value.command {
            
        case .NICK(let v), .MODEGET(let v):
            newString = base + space + v.stringValue
            
        case .USER(let userInfo):
            let userBase = base + space + userInfo.username
            if let mask = userInfo.usermask {
                newString = userBase + space + String(mask.maskValue) + space + star
            } else {
                newString = userBase + space + (userInfo.hostname ?? star) + space + (userInfo.servername ?? star)
            }
            newString += space + colon + userInfo.realname
            
        case .ISON(let nicks):
            newString += base + space + arguments(nicks.lazy.map({ $0.stringValue }))
            
        case .QUIT(.none):
            break
        case .QUIT(.some(let value)):
            newString = space + colon + value
            
        case .PING(server: let server, server2: let server2),
                .PONG(server: let server, server2: let server2):
            if let server2 = server2 {
                newString = base + space + server + space + colon + server2
            } else {
                newString = "\(base)\(space)\(colon)\(server)"
            }
            
        case .JOIN(channels: let channels, keys: let keys):
            newString = base + space
            newString += commaSeperatedValues(channels.lazy.map({ $0.stringValue }))
            if let keys = keys {
                newString +=  commaSeperatedValues(keys)
            }
            
        case .JOIN0:
            newString = base + space + star
            
        case .PART(channels: let channels):
            newString = base + commaSeperatedValues(channels.lazy.map({ $0.stringValue }))
            
        case .LIST(channels: let channels, target: let target):
            if let channels = channels {
                newString = base + commaSeperatedValues(channels.lazy.map({ $0.stringValue }))
            } else {
                newString = base + space + star
            }
            if let target = target {
                newString += space + colon + target
            }
            
        case .PRIVMSG(let recipients, let message),
                .NOTICE(let recipients, let message):
            newString = base + commaSeperatedValues(recipients.lazy.map({ $0.stringValue }))
            newString += space + colon + message
            
        case .MODE(let nick, add: let add, remove: let remove):
            newString = base + space + nick.stringValue
            let adds = add.stringValue.map({ "\(plus)\($0)" })
            let removes = remove.stringValue.map({ "\(minus)\($0)" })
            
            if add.isEmpty && remove.isEmpty {
                newString += space + colon
            } else {
                newString += arguments(adds) + arguments(removes) + argumentsWithLast()
            }
            
        case .CHANNELMODE(let channel, add: let add, remove: let remove):
            let adds = add.stringValue.map({ "\(plus)\($0)" })
            let removes = remove.stringValue.map({ "\(minus)\($0)" })
            
            newString = base + space + channel.stringValue
            newString += arguments(adds) + arguments(removes) + argumentsWithLast()
            
        case .CHANNELMODE_GET(let value):
            newString = space + value.stringValue
            
        case .CHANNELMODE_GET_BANMASK(let value):
            newString = base + space + bString + space + value.stringValue
        case .WHOIS(server: let server, usermasks: let usermasks):
            newString = base
            if let target = server {
                newString += space + target
            }
            newString += space + usermasks.joined(separator: comma)
            
        case .WHO(usermask: let usermask, onlyOperators: let onlyOperators):
            newString += base
            if let mask = usermask {
            newString += space + mask
                if onlyOperators {
                    newString += space + oString
                }
            }
        case .numeric(_, let args),
                .otherCommand(_, let args),
                .otherNumeric(_, let args):
            newString = argumentsWithLast(args)
        case .CAP(let subCommand, let capabilityIds):
            newString = space + subCommand.commandAsString + space + colon
            newString += capabilityIds.joined(separator: space)
        }
        newString += cCR + cLF
        return ByteBuffer(string: newString)
    }
    
    private func arguments(_ args: [String] = [""]) -> String {
        var newString = ""
        for arg in args {
            newString += " \(arg)"
        }
        return newString
    }
    
    private func argumentsWithLast(_ args: [String] = [""]) -> String {
        guard !args.isEmpty else { return "" }
        var newString = ""
        for arg in args.dropLast() {
            newString += " \(arg)"
        }
        
        let lastIdx = args.index(args.startIndex, offsetBy: args.count - 1)
        newString += " :\(args[lastIdx])"
        return newString
    }
    
    private func commaSeperatedValues(_ args: [String] = [""]) -> String {
        var newString = " "
        var isFirst = true
        for arg in args {
            if isFirst {
                isFirst = false
            } else {
                newString += ","
            }
            newString += arg
        }
        return newString
    }
}
