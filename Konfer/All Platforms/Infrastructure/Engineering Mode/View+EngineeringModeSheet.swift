//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

extension View {
    func engineeringModeSheet() -> some View {
        self.modifier(EngineeringModeSheetViewModifier())
    }
}

struct EngineeringModeSheetViewModifier: ViewModifier {
    
    @State private var isPresented: Bool = false
    
    @Environment(EngineeringMode.self) private var engineeringMode

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) {
                NavigationStack {
                    EngineeringModeForm()
                        .navigationTitle("Engineering Mode")
                        #if os(iOS)
                        .navigationBarTitleDisplayMode(.inline)
                        #endif
                        .toolbar {
                            #if os(macOS)
                            ToolbarItem(placement: .cancellationAction) {
                                Button {
                                    isPresented = false
                                } label: {
                                    Image(systemName: "xmark")
                                }
                            }
                            #else
                            ToolbarItem(placement: .topBarTrailing) {
                                Button {
                                    isPresented = false
                                } label: {
                                    Image(systemName: "xmark")
                                }
                            }
                            #endif
                        }
                }
                .environment(engineeringMode)
            }
            #if os(iOS)
            .onShake {
                if engineeringMode.isEnabled, !isPresented {
                    isPresented = true
                }
            }
            #endif
    }
}
