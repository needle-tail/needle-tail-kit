import XCTest
import NIO
import NeedleTailHelpers
@testable import NeedleTailKit

protocol ReceiveMessageProtocol: AnyObject {
    func receivePing() async throws
    func receiveMessage() async throws
}

final class NeedleTailKitTests: XCTestCase, ReceiveMessageProtocol {

    let consumer = NeedleTailAsyncConsumer<Int>()
    let writerConsumer = NeedleTailAsyncConsumer<Int>()
    weak var delegate: ReceiveMessageProtocol?
    
    
    func testLongRuningTaskAndPingPong() async throws {
        await consumer.feedConsumer(1)
        delegate = self
        try await withThrowingTaskGroup(of: Void.self) { group in
            try Task.checkCancellation()
            group.addTask { [weak self] in
                guard let self else { return }
                try await simulateConnection()
            }
            
            group.addTask { [weak self] in
                guard let self else { return }
               try await sendPong()
            }
            
            group.addTask { [weak self] in
                guard let self else { return }
                try await sendMessage()
            }
        }
    }
    
    func sendMessage() async throws {
        Task {
            try! await Task.sleep(until: .now + .seconds(3), tolerance: .zero, clock: .suspending)
            print("SEND MESSAGE CALLED")
            await writerConsumer.feedConsumer(1, priority: .standard)
            try await delegate?.receiveMessage()
            print("SEND MESSAGE SENT")
        }
    }
    
    func sendPong() async throws {
        Task {
            try! await Task.sleep(until: .now + .seconds(5), tolerance: .seconds(2), clock: .suspending)
            print("SEND PONG CALLED")
            await writerConsumer.feedConsumer(1, priority: .pingPong)
            try await delegate?.receivePing()
            print("SEND PONG SENT")
        }
    }
    
    func receivePing() async throws {
       print("RECEIVED PING")
        for try await result in NeedleTailAsyncSequence(consumer: writerConsumer) {
            switch result {
            case .success(let result):
                try await sendPong()
                print("FLUSHED PONG")
            case .consumed:
                break
            }
        }
    }
    
    func receiveMessage() async throws {
        print("RECEIVED MESSAGE", await writerConsumer.deque.count)
        for try await result in NeedleTailAsyncSequence(consumer: writerConsumer) {
            switch result {
            case .success(let result):
                try await sendMessage()
                print("FLUSHED MESSAGE")
            case .consumed:
                break
            }
        }
    }
    
    
    func simulateConnection() async throws {
        for try await result in NeedleTailAsyncSequence(consumer: consumer) {
            switch result {
            case .success(let result):
                try! await Task.sleep(until: .now + .seconds(5), tolerance: .seconds(2), clock: .suspending)
                await consumer.feedConsumer(result)
            case .consumed:
                return
            }
        }
    }
    
}
