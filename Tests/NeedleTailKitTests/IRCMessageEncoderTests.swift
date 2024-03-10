//
//  IRCMessageEncoderTests.swift
//  
//
//  Created by Cole M on 2/20/24.
//

import XCTest
import NeedleTailKit
import NeedleTailHelpers
import CypherMessaging

@testable import NeedleTailProtocol

final class IRCMessageEncoderTests: XCTestCase {

    func testEncodeNumericCommandStringArray() async {
        let message = IRCMessage(origin: "origin1",
                                 target: "target1",
                                 command: .numeric(.replyISON, ["userOne_123456789 userTwo_987654321", "someTHING ELSE", "XIXHI"]),
                                 tags: nil)
        let encoded = await NeedleTailEncoder.encode(value: message)
        XCTAssertNotNil(encoded)
    }
    
    func testEncodePRIVMSGCommandStringArray() async {
        let message = IRCMessage(origin: "origin1",
                                 command: .PRIVMSG([.nick(NeedleTailNick(name: "user1", deviceId: DeviceId("1233456789"))!)], "send message"),
                                 tags: nil)
        let encoded = await NeedleTailEncoder.encode(value: message)
        XCTAssertNotNil(encoded)
    }
    
    func testArgumentsWithLastAppendColon() async {
        let result = NeedleTailEncoder.create(
            arguments: ["userOne_123456789", "userTwo_987654321"],
            buildWithColon: true
        )
        XCTAssertEqual(result, " :userOne_123456789 userTwo_987654321")
    }

}
