import AudioToolbox

class SoundManager {
    static let shared = SoundManager()
    private init() {}

    func playShutter() {
        AudioServicesPlaySystemSound(1108)
    }
}
