//
//  NeedleTailProgressView.swift
//  NeedleTailClient3
//
//  Created by Cole M on 4/19/22.
//

#if canImport(SwiftUI) && canImport(Combine) && (os(macOS) || os(iOS))
import SwiftUI

public struct NeedleTailProgressView: View {
        let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
    @State private var statements = ["Keeping Confidence...", "Somethings are no ones business...", "🤫"]
    @State private var index = 0
    @State private var fade = false
    public var shouldDisplayProgress: Bool
    
    public init(shouldDisplayProgress: Bool = true) {
        self.shouldDisplayProgress = shouldDisplayProgress
    }
    
        public var body: some View {
            VStack {
                if shouldDisplayProgress == true {
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
            }
                .tint(.orange)
                .padding()
        }
    }
#endif
