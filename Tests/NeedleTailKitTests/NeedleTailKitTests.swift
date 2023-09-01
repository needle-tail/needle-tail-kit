import XCTest
import NIO
@testable import NeedleTailProtocol

final class NeedleTailKitTests: XCTestCase {
    
    
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
    
}
