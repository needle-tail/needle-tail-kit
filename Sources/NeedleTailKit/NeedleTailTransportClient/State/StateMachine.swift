//
//  StateMachine.swift
//  
//
//  Created by Cole M on 11/27/21.
//

import Foundation
import NeedleTailHelpers

@NeedleTailClientActor
public protocol StateMachine {
    associatedtype State
    var current: State { get }
    func transition(to nextState: State) async
}
