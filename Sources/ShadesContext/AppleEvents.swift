import CoreServices
import Foundation

/// Scripting through raw Apple Events. Going through osascript takes about 150 ms a call against
/// about 8 ms here, can't be aimed at one process, and has to be killed to time out.
enum AppleEvents {
    enum Failure: Error, Equatable, Sendable {
        case notAllowed, notAsked, timedOut, noWindow, appGone, javaScriptOff
        case other(Int)

        /// Chromium answers 12 whatever language it's in. Safari's wording is the only sign it gives.
        init(code: Int, message: String?) {
            let text = message ?? ""
            switch code {
            case -1743: self = .notAllowed
            case -1744: self = .notAsked
            case -1712: self = .timedOut
            case -1719, -1728: self = .noWindow
            case -600, -609: self = .appGone
            case 12: self = .javaScriptOff
            default:
                self = text.contains("Allow JavaScript from Apple Events") ? .javaScriptOff : .other(code)
            }
        }
    }

    /// Whether events may be sent, without ever asking. Nothing is sent unless this says yes,
    /// which is what keeps a normal capture free of permission prompts.
    static func permissionFailure(pid: pid_t) -> Failure? {
        status(of: NSAppleEventDescriptor(processIdentifier: pid), askUser: false)
    }

    static func status(of target: NSAppleEventDescriptor, askUser: Bool) -> Failure? {
        guard let address = target.aeDesc else { return .appGone }
        let result = AEDeterminePermissionToAutomateTarget(address, typeWildCard, typeWildCard, askUser)
        return result == noErr ? nil : Failure(code: Int(result), message: nil)
    }

    /// `get <property>`, answering with its text.
    static func get(_ specifier: NSAppleEventDescriptor, pid: pid_t, timeout: TimeInterval) -> Result<String?, Failure> {
        let event = make("core", "getd", pid: pid)
        event.setParam(specifier, forKeyword: code("----"))
        return send(event, timeout: timeout)
    }

    static func send(_ event: NSAppleEventDescriptor, timeout: TimeInterval) -> Result<String?, Failure> {
        do {
            let reply = try event.sendEvent(options: [.waitForReply, .neverInteract], timeout: timeout)
            if let number = reply.paramDescriptor(forKeyword: code("errn"))?.int32Value, number != 0 {
                let message = reply.paramDescriptor(forKeyword: code("errs"))?.stringValue
                return .failure(Failure(code: Int(number), message: message))
            }
            return .success(reply.paramDescriptor(forKeyword: code("----"))?.stringValue)
        } catch {
            return .failure(Failure(code: (error as NSError).code, message: nil))
        }
    }

    static func make(_ eventClass: String, _ eventID: String, pid: pid_t) -> NSAppleEventDescriptor {
        NSAppleEventDescriptor(
            eventClass: code(eventClass),
            eventID: code(eventID),
            targetDescriptor: NSAppleEventDescriptor(processIdentifier: pid),
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
    }

    /// `window 1` of the application, in whichever class code the app's dictionary uses.
    static func frontWindow(classCode: String) -> NSAppleEventDescriptor {
        specifier(want: classCode, form: "indx", selector: NSAppleEventDescriptor(int32: 1), from: .null())
    }

    static func property(_ propertyCode: String, of container: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        specifier(want: "prop", form: "prop", selector: NSAppleEventDescriptor(typeCode: code(propertyCode)), from: container)
    }

    private static func specifier(
        want: String,
        form: String,
        selector: NSAppleEventDescriptor,
        from container: NSAppleEventDescriptor
    ) -> NSAppleEventDescriptor {
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(NSAppleEventDescriptor(typeCode: code(want)), forKeyword: code("want"))
        record.setDescriptor(NSAppleEventDescriptor(enumCode: code(form)), forKeyword: code("form"))
        record.setDescriptor(selector, forKeyword: code("seld"))
        record.setDescriptor(container, forKeyword: code("from"))
        return record.coerce(toDescriptorType: code("obj ")) ?? record
    }

    static func code(_ text: String) -> FourCharCode {
        text.utf8.reduce(0) { ($0 << 8) | FourCharCode($1) }
    }
}
