//
//  BSON+Extension.swift
//
//
//  Created by Cole M on 1/15/24.
//

import BSON
import NIOCore
import Foundation

extension BSONDecoder {
    public func decodeString<T: Codable>(_ type: T.Type, from string: String) throws -> T {
        guard let data = Data(base64Encoded: string) else { throw NeedleTailError.nilData }
        let buffer = ByteBuffer(data: data)
        return try decode(type, from: Document(buffer: buffer))
    }

    public func decodeData<T: Codable>(_ type: T.Type, from data: Data) throws -> T {
        let buffer = ByteBuffer(data: data)
        return try decode(type, from: Document(buffer: buffer))
    }
    
    public func decodeBuffer<T: Codable>(_ type: T.Type, from buffer: ByteBuffer) throws -> T {
        return try decode(type, from: Document(buffer: buffer))
    }
}

extension BSONEncoder {
    public func encodeString<T: Codable>(_ encodable: T) throws -> String {
        try encode(encodable).makeData().base64EncodedString()
    }

    public func encodeData<T: Codable>(_ encodable: T) throws -> Data {
        try encode(encodable).makeData()
    }
}
