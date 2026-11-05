import Foundation

/// A window for seeing what's being said. It only reads, and opening it captures nothing.
extension AppController {
    func channelsPressed() {
        stage.showChannels(channels.open(threads: latestThreads))
    }

    func channelsClosed() {
        channels.close()
    }
}
