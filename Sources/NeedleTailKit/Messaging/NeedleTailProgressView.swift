//
//  NeedleTailProgressView.swift
//  NeedleTailClient3
//
//  Created by Cole M on 4/19/22.
//

import SwiftUI

public struct NeedleTailProgressView: View {
        let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
    @State private var statements = ["Keeping Confidence...", "Somethings are no ones business...", "🤫"]
    @State private var index = 0
    @State private var fade = false
    
    public init() {}
    
        public var body: some View {
            VStack {
                Spacer()
                ProgressView(value: 0) {
                    Text(statements[index])
                        .onReceive(timer) { input in
                            if index >= statements.count - 1 {
                                index = 0
                            } else {
                            index += 1
                            }
                        }
                }
                .progressViewStyle(.circular)
                Spacer()
            }
            .tint(.orange)
            .padding()
        }
    }


struct NeedleTailProgressView_Previews: PreviewProvider {
    static var previews: some View {
        NeedleTailProgressView()
    }
}
