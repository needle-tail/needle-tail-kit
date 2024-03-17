//
//  PacketTracer.swift
//
//
//  Created by Cole M on 3/15/24.
//

import Foundation
import Logging
import NeedleTailProtocol

public actor PacketTracer {
    var id: UUID?
    var packets = [Packet]()
    
    public init() {}
    
    struct Packet: Sendable {
        var id: String
        var partNumber: Int
        var totalParts: Int
        var chunk: Data
        var totalData = Data()
        var receivedPackets: [Int] = []
    }
    
    public func processPacket(_ 
                              packet: [String],
                              needsParsing: Bool = true,
                              logger: Logger
    ) throws -> Data? {
        var splitMessage = [String]()
            if needsParsing, let messageIndex = packet.firstIndex(where: { $0.hasPrefix(Constants.colon.rawValue) }) {
                let initialArguements = packet[..<messageIndex].dropFirst()
                let lastArgument = packet[messageIndex...]
                let joined = (initialArguements + lastArgument).joined().components(separatedBy: Constants.comma.rawValue)
                splitMessage.append(contentsOf: joined)
            } else {
                splitMessage = packet
            }
        
        precondition(splitMessage.count == 4)
        let firstItem = splitMessage[0]
        let secondItem = splitMessage[1]
        let thirdItem = splitMessage[2]
        let fourthItem = splitMessage[3]
        logger.info("\n Received multipart packet with id \(firstItem):\n Packet: \(secondItem) of \(thirdItem)\n Number of items in Multipart Packet: \(splitMessage.count)")
        logger.info("Creating packet")
        try createPacket([
            String(firstItem),
            secondItem,
            thirdItem,
            fourthItem
        ])
        logger.info("Created packet")
        
        guard let packets = findPackets(String(firstItem)) else { return nil }
        guard packets.count == Int(thirdItem) else { return nil }
        var totalData = Data()
        totalData.append(contentsOf: packets.compactMap({ $0.chunk }).joined())
        logger.info("Finished processing with a total bytes size of: \(totalData.count)")
        return totalData
    }
    
    private func findPacket(_ id: String) -> Packet? {
        packets.first(where: { $0.id == id })
    }
    
    private func findPackets(_ id: String) -> [Packet]? {
        packets.filter({ $0.id == id }).sorted(by: { $0.partNumber < $1.partNumber })
    }
    
    private func createPacket(_ packet: [String]) throws {
        guard let partNumber = Int(packet[1]) else { throw PacketTracerError.invalidPartNumber }
        guard let totalParts = Int(packet[2]) else { throw PacketTracerError.invalidTotalNumber }
        guard let chunk = Data(base64Encoded: packet[3]) else { throw PacketTracerError.invalidData }
        packets.append(
            Packet(
                id: packet[0],
                partNumber: partNumber,
                totalParts: totalParts,
                chunk: chunk
            )
        )
    }
    
    public func removePacket(_ id: String) {
        packets.removeAll(where: { $0.id == id })
    }
    
    enum PacketTracerError: Error {
        case invalidData, invalidPartNumber, invalidTotalNumber
    }
}
