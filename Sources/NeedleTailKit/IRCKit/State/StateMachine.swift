//
//  File.swift
//  
//
//  Created by Cole M on 11/27/21.
//

import Foundation
import AsyncIRC

protocol StateMachine {
    associatedtype State: Hashable
    var state: State { get }
    /// States transitions definition.
    /// Must contain set of allowed next states for each state.
    static var stateTransitions: [State: Set<State>] { get }
    func canTransition(to nextState: State) -> Bool
    mutating func transition(to nextState: State)
}

extension StateMachine {
    static func isStateTransitionAllowed(from state: State, to nextState: State) -> Bool {
        guard let validNextStates = self.stateTransitions[state] else {
            fatalError("No transitions for \(state) defined in stateTransitions")
        }
        return validNextStates.contains(nextState)
    }
    func canTransition(to nextState: State) -> Bool {
        return type(of: self).isStateTransitionAllowed(from: self.state, to: nextState)
    }
}
