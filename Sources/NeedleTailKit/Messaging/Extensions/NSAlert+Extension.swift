//
//  NSAlert+Extension.swift
//  NeedleTailClient1
//
//  Created by Cole M on 4/14/22.
//

#if os(macOS)
import Cocoa


extension NSAlert {
    public func configuredAlert(title: String, text: String, singleButton: Bool = false, switchRun: Bool = false)  {
        self.messageText = title
        self.informativeText = text
        self.alertStyle = NSAlert.Style.warning
        self.addButton(withTitle: "OK")
        if !singleButton {
        self.addButton(withTitle: "Cancel")
        }
        if !switchRun {
        self.runModal()
        }
    }
    
   public func configuredCustomButtonAlert(title: String, text: String, firstButtonTitle: String, singleButton: Bool = false, secondButtonTitle: String, thirdButtonTitle: String, switchRun: Bool = false)  {
        self.messageText = title
        self.informativeText = text
        self.alertStyle = NSAlert.Style.warning
        self.addButton(withTitle: firstButtonTitle)
        if !singleButton {
        self.addButton(withTitle: secondButtonTitle)
        self.addButton(withTitle: thirdButtonTitle)
        }
        if !switchRun {
        self.runModal()
        }
    }
}
#endif
