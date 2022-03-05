    import XCTest
    import NIO
    @testable import AsyncIRC

    final class NeedleTailKitTests: XCTestCase {
        func testExample() {
            // This is an example of a functional test case.
            // Use XCTAssert and related functions to verify your tests produce the correct
            // results.
//            XCTAssertEqual(CartisimNIORTC.text, "Hello, World!")  
            
            let m = asyncParse(line: "SOME STRING")
            m.whenSuccess{ message in
            print(message, "MESSAGE")                
        }
        }
    }


 func asyncParse(line: String) -> EventLoopFuture<IRCMessage> {
     let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let promise = group.next().makePromise(of: IRCMessage.self)
        promise.completeWithTask {
            guard let message = try await queueMessage(line: line) else { throw ParserError.jobFailedToParse }
            return message
        }
        return promise.futureResult
    }

    func queueMessage(line: String) async throws -> IRCMessage? {
        let c = try? IRCCommand("COMMAND", "ARGUEMENTS")
        let message = IRCMessage(origin: "ORIGIN", target: "TARGET", command: c!, tags: nil)
        return message
    }



