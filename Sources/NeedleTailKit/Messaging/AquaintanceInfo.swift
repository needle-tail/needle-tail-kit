import CypherMessaging
import NeedleTailHelpers

public struct NickOnline: Codable, Hashable {
    public var nick: NeedleTailNick
    public var isTyping: TypingStatus
}

struct AquaintanceInfo {
    
    init(emitter: NeedleTailEmitter) {
        self.emitter = emitter
    }
    
    let emitter: NeedleTailEmitter
    
    func recievedIsOnline(_ nicks: [NeedleTailNick]) async {
        for nick in nicks {
            if var emitterNick = await emitter.nicksOnline.first(where: { $0.nick == nick }) {
                emitterNick.nick = nick
            } else {
                await setNickOnline(
                    NickOnline(nick: nick, isTyping: .isNotTyping)
                )
            }
        }
    }
    
    @MainActor
    private func setNickOnline(_ nickOnline: NickOnline) {
        emitter.nicksOnline.append(nickOnline)
    }
    
    func receivedIsTyping(_ nickOnline: NickOnline) async {
        guard var emitterNick = await emitter.nicksOnline.first(where: {$0.nick == nickOnline.nick}) else { return }
        emitterNick.isTyping = nickOnline.isTyping
    }
    
}

public enum TypingStatus: Sendable, Codable {
    case isTyping, isNotTyping
    
}
