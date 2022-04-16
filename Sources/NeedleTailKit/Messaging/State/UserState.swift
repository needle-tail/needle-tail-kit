//
//  UserState.swift
//  
//
//  Created by Cole M on 11/28/21.
//

import Foundation

public struct UserState: StateMachine {

    let identifier: String
    init(identifier: String) {
        self.identifier = identifier
    }
    // MARK: StateMachine
    enum State: CaseIterable {
        case suspended
        case offline
        case connecting
        case online
        
    }

    private(set) var state: State = .offline
    static let stateTransitions: [State: Set<State>] = [
        .suspended: [.offline],
        .offline: [.connecting],
        .connecting: [.suspended, .offline, .online],
        .online: [.connecting, .offline, .suspended],
    ]
    
    
    mutating func transition(to nextState: State) {
        precondition(self.canTransition(to: nextState), "Invalid state transition (\(self.state) -> \(nextState))!")
        self.state = nextState
    }
}
