//
//  MessageParserTests.swift
//
//
//  Created by Cole M on 2/9/24.
//

import XCTest
import NeedleTailKit
import NeedleTailHelpers
import CypherMessaging
@testable import NeedleTailProtocol

final class MessageParserTests: XCTestCase {
    
    var parser = MessageParser()
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
    
    func testParseISON() throws {
        let isonMessage = ":abcdefghi123456789= ISON user1_123456 user2_78910"
       
        XCTAssertNoThrow(try parser.parseMessage(isonMessage))
    }
    
    func testUserMessageParser() {
        let (arguments, _) = parser.parseArgument(
            commandKey: .string(Constants.user.rawValue),
            message: ":origin USER username_deviceId hostname servername :Real name is secret",
            commandMessage: "USER username_deviceId hostname servername :Real name is secret",
            stripedMessage: ":origin USER username_deviceId hostname servername :Real name is secret",
            parameter: "username:deviceId",
            origin: ":origin"
        )
        XCTAssertEqual(arguments.count, 4)
        
    }
    
    func testlistBucketParser() {
        let (arguments, _) = parser.parseArgument(
            commandKey: .string(Constants.user.rawValue),
            message: ":origin USER username_deviceId hostname servername :Real name is secret",
            commandMessage: "USER username_deviceId hostname servername :Real name is secret",
            stripedMessage: ":origin USER username_deviceId hostname servername :Real name is secret",
            parameter: "username_deviceId",
            origin: ":origin"
        )
        XCTAssertEqual(arguments.count, 4)
    }
    
    func testParseIntCommandArgumentTargetArray() throws {
        let messages = ":origin1 303 target1 :userOne_123456789 userTwo_987654321".components(separatedBy: Constants.cLF.rawValue)
            .map { $0.replacingOccurrences(of: Constants.cCR.rawValue, with: Constants.space.rawValue) }
            .filter { !$0.isEmpty }
        for message in messages {
            let result = try parser.parseMessage(message)
            XCTAssertEqual(result.arguments?.count, 2)
        }
    }
    
    func testParseIntCommandArgumentArray() throws {
        let messages = ":origin1 303 :userOne_123456789 userTwo_987654321".components(separatedBy: Constants.cLF.rawValue)
            .map { $0.replacingOccurrences(of: Constants.cCR.rawValue, with: Constants.space.rawValue) }
            .filter { !$0.isEmpty }
        for message in messages {
            let result = try parser.parseMessage(message)
            XCTAssertEqual(result.arguments?.count, 2)
        }
    }
    
    func testParseIntCommandEmptyArgumentArray() throws {
        let messages = ":origin1 303".components(separatedBy: Constants.cLF.rawValue)
            .map { $0.replacingOccurrences(of: Constants.cCR.rawValue, with: Constants.space.rawValue) }
            .filter { !$0.isEmpty }
        for message in messages {
            let result = try parser.parseMessage(message)
            XCTAssertEqual(result.arguments?.count, 0)
        }
    }
    
    func testParseIntCommandTargetEmptyArgumentArray() throws {
        let messages = ":origin1 303 target1".components(separatedBy: Constants.cLF.rawValue)
            .map { $0.replacingOccurrences(of: Constants.cCR.rawValue, with: Constants.space.rawValue) }
            .filter { !$0.isEmpty }
        for message in messages {
            let result = try parser.parseMessage(message)
            XCTAssertEqual(result.arguments?.count, 0)
        }
    }
    
    
    func testParsePrivMsgCommand() throws {
        let messages = ":origin1 PRIVMSG user1_1233456789 :send message".components(separatedBy: Constants.cLF.rawValue)
            .map { $0.replacingOccurrences(of: Constants.cCR.rawValue, with: Constants.space.rawValue) }
            .filter { !$0.isEmpty }
        for message in messages {
            let result = try parser.parseMessage(message)
            XCTAssertEqual(result.arguments?.count, 2)
        }
    }
    
    func testParseNickCommand() throws {
        let messages = ":origin1 PRIVMSG user1_1233456789 :send message".components(separatedBy: Constants.cLF.rawValue)
            .map { $0.replacingOccurrences(of: Constants.cCR.rawValue, with: Constants.space.rawValue) }
            .filter { !$0.isEmpty }
        for message in messages {
            let result = try parser.parseMessage(message)
            XCTAssertEqual(result.arguments?.count, 2)
        }
    }
    
    func testParseIRCMessage() async throws {
        for message in buildIRCMessage() {
            var encoded = await NeedleTailEncoder.encode(value: message)
            
            guard let message = encoded.readString(length: encoded.readableBytes) else { return }
            guard !message.isEmpty else { return }
            let messages = message.components(separatedBy: Constants.cLF.rawValue)
                .map { $0.replacingOccurrences(of: Constants.cCR.rawValue, with: Constants.space.rawValue) }
                .filter { !$0.isEmpty }
            for message in messages {
                runCommandTests(message: try parser.parseMessage(message))
            }
        }
    }
}

func runCommandTests(message: IRCMessage) {
    switch message.command {
    case .NICK(let needleTailNick):
        XCTAssertNotNil(needleTailNick)
    case .USER(let iRCUserInfo):
        XCTAssertNotNil(iRCUserInfo)
    case .ISON(let array):
        XCTAssertNotNil(array)
    case .QUIT(let string):
        XCTAssertNotNil(string)
    case .PING(let server, let server2):
        XCTAssertNotNil(server)
    case .PONG(let server, let server2):
        XCTAssertNotNil(server)
    case .JOIN(let channels, let keys):
        XCTAssertNotNil(channels)
        XCTAssertNotNil(keys)
    case .JOIN0:
        ()
    case .PART(let channels):
        XCTAssertNotNil(channels)
    case .LIST(let channels, let target):
        XCTAssertNotNil(channels)
        XCTAssertNotNil(target)
    case .PRIVMSG(let array, let string):
        XCTAssertNotNil(array)
        XCTAssertNotNil(string)
    case .NOTICE(let array, let string):
        XCTAssertNotNil(array)
        XCTAssertNotNil(string)
    case .MODE(let needleTailNick, let add, let remove):
        XCTAssertNotNil(needleTailNick)
        XCTAssertNotNil(add)
        XCTAssertNotNil(remove)
    case .MODEGET(let needleTailNick):
        XCTAssertNotNil(needleTailNick)
    case .CHANNELMODE(let iRCChannelName, let add, let remove):
        XCTAssertNotNil(iRCChannelName)
        XCTAssertNotNil(add)
        XCTAssertNotNil(remove)
    case .CHANNELMODE_GET(let iRCChannelName):
        XCTAssertNotNil(iRCChannelName)
    case .CHANNELMODE_GET_BANMASK(let iRCChannelName):
        XCTAssertNotNil(iRCChannelName)
    case .WHOIS(let server, let usermasks):
        XCTAssertNotNil(server)
        XCTAssertNotNil(usermasks)
    case .WHO(let usermask, let onlyOperators):
        XCTAssertNotNil(usermask)
        XCTAssertNotNil(onlyOperators)
    case .KICK(let array, let array2, let array3):
        XCTAssertNotNil(array)
        XCTAssertNotNil(array2)
        XCTAssertNotNil(array3)
    case .KILL(let needleTailNick, let string):
        XCTAssertNotNil(needleTailNick)
        XCTAssertNotNil(string)
    case .numeric(let iRCCommandCode, let array):
        XCTAssertNotNil(iRCCommandCode)
        XCTAssertNotNil(array)
    case .otherCommand(let string, let array):
        XCTAssertNotNil(string)
        XCTAssertNotNil(array)
    case .otherNumeric(let int, let array):
        XCTAssertNotNil(int)
        XCTAssertNotNil(array)
    case .CAP(let cAPSubCommand, let array):
        XCTAssertNotNil(cAPSubCommand)
        XCTAssertNotNil(array)
    }
}

func buildIRCMessage() -> [IRCMessage] {
    var messages = [IRCMessage]()
    for command in buildCommandList() {
        switch command {
        case .NICK(_):
            let tag = IRCTags(key: "registrationPacket", value: "encodedDataString")
            messages.append(IRCMessage(
                origin: "origin1",
                command: command,
                tags: [tag]
            )
            )
        case .USER(_):
            messages.append(IRCMessage(
                origin: "origin1",
                command: command
            )
            )
        case .ISON(_):
            messages.append(IRCMessage(
                origin: "origin1",
                command: command
            )
            )
        case .QUIT(_):
            messages.append(IRCMessage(
                origin: "origin1",
                command: command
            )
            )
        case .PING(_, _):
            messages.append(IRCMessage(
                origin: "origin1",
                command: command
            )
            )
        case .PONG(_, _):
            messages.append(IRCMessage(
                origin: "origin1",
                command: command
            )
            )
        case .JOIN(_, _):
            let tag = IRCTags(key: "channelPacket", value: "encodedDataString")
            messages.append(IRCMessage(
                origin: "origin1",
                command: command,
                tags: [tag]
            )
            )
        case .JOIN0:
            messages.append(IRCMessage(
                origin: "origin1",
                command: command
            )
            )
        case .PART(_):
            let tag = IRCTags(key: "channelPacket", value: "encodedDataString")
            messages.append(IRCMessage(
                origin: "origin1",
                command: command,
                tags: [tag]
            )
            )
        case .LIST(_, _):
            messages.append(IRCMessage(
                origin: "origin1",
                command: command
            )
            )
        case .PRIVMSG(_, _):
            messages.append(IRCMessage(
                origin: "origin1",
                command: command
            )
            )
        case .NOTICE(_, _):
            messages.append(IRCMessage(
                origin: "origin1",
                command: command
            )
            )
        case .MODE(_, _, _):
            messages.append(IRCMessage(
                origin: "origin1",
                command: command
            )
            )
        case .MODEGET(let target):
            messages.append(IRCMessage(
                origin: "origin1",
                command: command
            )
            )
        case .CHANNELMODE(_, _, _):
            messages.append(IRCMessage(
                origin: "origin1",
                command: command
            )
            )
        case .CHANNELMODE_GET(_):
            messages.append(IRCMessage(
                origin: "origin1",
                command: command
            )
            )
        case .CHANNELMODE_GET_BANMASK(_):
            messages.append(IRCMessage(
                origin: "origin1",
                command: command
            )
            )
        case .WHOIS(_, _):
            messages.append(IRCMessage(
                origin: "origin1",
                command: command
            )
            )
        case .WHO(_, _):
            messages.append(IRCMessage(
                origin: "origin1",
                command: command
            )
            )
        case .KICK(_, _, _):
            messages.append(IRCMessage(
                origin: "origin1",
                command: command
            )
            )
        case .KILL(_, _):
            messages.append(IRCMessage(
                origin: "origin1",
                command: command
            )
            )
        case .numeric(let iRCCommandCode, _):
            if iRCCommandCode == .replyMotD {
                messages.append(IRCMessage(
                    origin: "origin1",
                    command: command
                )
                )
            } else {
                messages.append(IRCMessage(
                    origin: "origin1",
                    target: "target1",
                    command: command
                )
                )
            }
        case .otherCommand(_, _):
            messages.append(IRCMessage(
                origin: "origin1",
                command: command
            )
            )
        case .otherNumeric(_, _):
            messages.append(IRCMessage(
                origin: "origin1",
                command: command
            )
            )
        case .CAP(_, _):
            messages.append(IRCMessage(
                origin: "origin1",
                command: command
            )
            )
        }
    }
    return messages
}

func buildCommandList() -> [IRCCommand] {
    var commands = [IRCCommand]()
    commands.append(.NICK(NeedleTailNick(name: "user1", deviceId: DeviceId("123456789"))!))
    commands.append(.USER(.init(username: "user1", hostname: "hostname1", servername: "servername1", realname: "realname1")))
    commands.append(.ISON([NeedleTailNick(name: "user1", deviceId: DeviceId("123456789"))!, NeedleTailNick(name: "user2", deviceId: DeviceId("987654321"))!]))
    commands.append(.QUIT("user1 is quiting"))
    commands.append(.PING(server: "ServerOne", server2: "Server2"))
    commands.append(.PONG(server: "ServerOne", server2: "Server2"))
    commands.append(.JOIN(channels: [.init("#Channel1")!, .init("#Channel2")!], keys: ["Key1", "Key2"]))
    commands.append(.JOIN0)
    commands.append(.PART(channels: [.init("#Channel1")!, .init("#Channel2")!]))
    commands.append(.LIST(channels: [.init("#Channel1")!, .init("#Channel2")!], target: "target1"))
    commands.append(.PRIVMSG([.channel(.init("#Channel1")!), .everything, .nick(NeedleTailNick(name: "user1", deviceId: DeviceId("123456789"))!)], "Send Message"))
    commands.append(.NOTICE([.channel(.init("#Channel1")!), .everything, .nick(NeedleTailNick(name: "user1", deviceId: DeviceId("123456789"))!)], "Send Notice"))
    commands.append(.MODE(NeedleTailNick(name: "user1", deviceId: DeviceId("123456789"))!, add: .operator, remove: .away))
    commands.append(.MODEGET(NeedleTailNick(name: "user1", deviceId: DeviceId("123456789"))!))
    commands.append(.CHANNELMODE(.init("#Channel1")!, add: .inviteOnly, remove: .channelOperator))
    commands.append(.CHANNELMODE_GET(.init("#Channel1")!))
    commands.append(.CHANNELMODE_GET_BANMASK(.init("#Channel1")!))
    commands.append(.WHOIS(server: "SERVER1", usermasks: ["MASK1", "MASK2"]))
    commands.append(.WHO(usermask: "MASK1", onlyOperators: false))
    commands.append(.WHO(usermask: "OPMASK1", onlyOperators: true))
    commands.append(.KICK([.init("#Channel1")!, .init("#Channel2")!], [NeedleTailNick(name: "user1", deviceId: DeviceId("123456789"))!, NeedleTailNick(name: "user2", deviceId: DeviceId("987654321"))!], ["GO AWAY", "NOT AUTHORISED"]))
    commands.append(.KILL(NeedleTailNick(name: "user1", deviceId: DeviceId("123456789"))!, "KILL IT"))
    commands.append(.numeric(.replyISON, ["userOne_123456789 userTwo_987654321", "someTHING ELSE", "XIXHI"]))
    commands.append(.numeric(.replyKeyBundle, ["userOne_123456789 userTwo_987654321", "someTHING ELSE", "XIXHI"]))
    commands.append(.numeric(.replyInfo, ["userOne_123456789 userTwo_987654321", "someTHING ELSE", "XIXHI"]))
    commands.append(.otherCommand(Constants.badgeUpdate.rawValue, ["\(10)"]))
    commands.append(.otherCommand(Constants.multipartMediaDownload.rawValue, ["1", "2", "3", "4"]))
    commands.append(.otherNumeric(999, ["something"]))
    return commands
}
