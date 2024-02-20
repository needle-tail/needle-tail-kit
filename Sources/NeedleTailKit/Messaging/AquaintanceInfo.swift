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
    
    @MainActor
    private func updateNicksOnline(_ nicks: [NeedleTailNick]) {
        emitter.nicksOnline = emitter.nicksOnline.filter({ nicks.contains($0.nick) })
    }
    
    @MainActor
    private func updateNickOnline(_ nick: NickOnline) async {
        guard let index = emitter.nicksOnline.firstIndex(where: {$0.nick == nick.nick}) else { return }
        emitter.nicksOnline[index] = nick
    }
    
    func recievedIsOnline(_ nicks: [NeedleTailNick]) async {
        await updateNicksOnline(nicks)
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
        await updateNickOnline(emitterNick)

    }
    
}

public enum TypingStatus: Sendable, Codable {
    case isTyping, isNotTyping
    
}
