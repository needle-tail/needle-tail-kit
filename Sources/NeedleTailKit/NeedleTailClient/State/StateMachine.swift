//
//  StateMachine.swift
//  
//
//  Created by Cole M on 11/27/21.
//

import Foundation
import NeedleTailHelpers

public protocol StateMachine: AnyObject, Sendable {
    associatedtype State
    var current: State { get set }
    func transition(to nextState: State) async
}
