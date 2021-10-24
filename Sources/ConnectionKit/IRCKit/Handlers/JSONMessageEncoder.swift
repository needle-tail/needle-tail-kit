import Foundation
import NIO

public final class JSONMessageEncoder<Message: Encodable>: MessageToByteEncoder {
    public typealias OutboundIn = Message
    public let jsonEncoder: JSONEncoder
    
    public init(jsonEncoder: JSONEncoder = JSONEncoder()) {
        self.jsonEncoder = jsonEncoder
    }
    
    public func encode(data: Message, out: inout ByteBuffer) throws {
        try self.jsonEncoder.encode(data, into: &out)
        assert(!out.readableBytesView.contains(UInt8(ascii: "\n")),
               "Foundation.JSONEncoder encoded a newline into the output for \(data), this will fail decoding. Please configure JSONEncoder differently")
        out.writeStaticString("\n")
    }
}
