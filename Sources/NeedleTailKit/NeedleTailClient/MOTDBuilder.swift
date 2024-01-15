//
//  MOTDBuilder.swift
//  
//
//  Created by Cole M on 6/9/23.
//

actor MOTDBuilder {
    
    private var intitialMessage = ""
    private var bodyMessage = ""
    private var endMessage = ""
    private var finalMessage = ""
    
    public func createInitial(message: String) {
        intitialMessage = message
    }
    
    public func createBody(message: String) {
        bodyMessage = message
    }
    
    public func createFinalMessage() -> String {
        intitialMessage + bodyMessage
    }
    
    public func clearMessage() {
        intitialMessage = ""
        bodyMessage = ""
    }
}
