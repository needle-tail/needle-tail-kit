//
//  StateMachine.swift
//  
//
//  Created by Cole M on 11/27/21.
//

import Foundation

public protocol StateMachine {
    associatedtype State
    var current: State { get }
    mutating func transition(to nextState: State) async
}
