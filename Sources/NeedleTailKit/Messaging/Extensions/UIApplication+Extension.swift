//
//  UIApplication+Extension.swift
//  
//
//  Created by Cole M on 4/27/22.
//

#if os(iOS)
import UIKit
extension UIApplication {
    public func endEditing() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
#endif
