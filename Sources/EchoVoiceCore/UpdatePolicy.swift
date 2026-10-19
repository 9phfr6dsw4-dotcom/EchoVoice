import Foundation

/// When EchoVoice may quit to install an update that has already downloaded.
public enum UpdateInstallPolicy {
    /// How often the waiting installer asks again while EchoVoice is busy.
    public static let retryInterval: TimeInterval = 15

    /// A voice is being generated, a model is being downloaded or removed, or a clip is being
    /// recorded, prepared or transcribed. Stopping any of them would lose work, so the update waits.
    /// Quitting EchoVoice still installs the update straight away.
    public static func canInstallNow(isBusy: Bool) -> Bool {
        !isBusy
    }
}
