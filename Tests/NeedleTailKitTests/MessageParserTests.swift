//
//  MessageParserTests.swift
//  
//
//  Created by Cole M on 2/9/24.
//

import XCTest
@testable import NeedleTailProtocol

final class MessageParserTests: XCTestCase {
    
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
    
    func testParseISON() throws {
        let isonMessage = ":TQAAAAJuYW1lAAsAAABuZWVkbGV0YWlsAAJkZXZpY2VJZAAlAAAANjk3Njg4YjQtNDc0Zi00YWViLWIwYjMtZWQzYjAwNGUyY2YyAAA= ISON snackerhacker:ad86f9ed-7191-490a-90a2-9b1628711f28 cartisim:175dbc25-811a-4f05-ba10-4e6d3e966aba"
        let parser = MessageParser()
        XCTAssertNoThrow(try parser.parseMessage(isonMessage))
    }
    
    func testUserMessageParser() {
        let result = MessageParser().parseArgument(
            commandKey: .string(Constants.user.rawValue),
            message: ":origin USER username:deviceId hostname servername :Real name is secret",
            commandMessage: "USER username:deviceId hostname servername :Real name is secret",
            stripedMessage: ":origin USER username:deviceId hostname servername :Real name is secret",
            parameter: "username:deviceId",
            origin: ":origin"
        )
        XCTAssertEqual(result.count, 4)
        
    }
    
    func testlistBucketParser() {
        let result = MessageParser().parseArgument(
            commandKey: .string(Constants.user.rawValue),
            message: ":origin USER username:deviceId hostname servername :Real name is secret",
            commandMessage: "USER username:deviceId hostname servername :Real name is secret",
            stripedMessage: ":origin USER username:deviceId hostname servername :Real name is secret",
            parameter: "username:deviceId",
            origin: ":origin"
        )
        XCTAssertEqual(result.count, 4)
        
    }
}
