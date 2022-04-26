//
//  ErrorView.swift
//  
//
//  Created by Cole M on 4/22/22.
//

import SwiftUI

public struct ErrorView: View {
    @State var error: Error
    
    public var body: some View {
        ZStack {
            Text("You need to finish registering Error: \(error.localizedDescription)")
        }
    }
}
