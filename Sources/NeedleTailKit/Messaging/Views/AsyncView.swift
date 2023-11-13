//
//  AsyncView.swift
//  
//
//  Created by Cole M on 9/2/23.
//

#if canImport(SwiftUI) && (os(macOS) || os(iOS))
import SwiftUI

public struct AsyncView<T, V: View>: View {
    @State var result: Result<T, Error>?
    let run: () async throws -> T
    let build: (T) -> V
    
    public init(run: @escaping () async throws -> T, @ViewBuilder build: @escaping (T) -> V) {
        self.run = run
        self.build = build
    }
    
    public var body: some View {
        ZStack {
            switch result {
            case .some(.success(let value)):
                build(value)
            case .some(.failure(let error)):
                ErrorView(error: error)
            case .none:
                NeedleTailProgressView()
                    .task {
                        do {
                            self.result = .success(try await run())
                        } catch {
                            self.result = .failure(error)
                        }
                    }
            }
        }
        .id(result.debugDescription)
    }
}
#endif
