import AVFoundation

/// Converts audio of one sample rate to 16 kHz mono, keeping its state between chunks.
final class Resampler {
    private let converter: AVAudioConverter
    private let input: AVAudioFormat
    private let output: AVAudioFormat
    private let ratio: Double

    init?(from sampleRate: Double) {
        guard sampleRate > 0,
              let input = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
              let output = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: AudioFormat.sampleRate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: input, to: output)
        else { return nil }
        // Priming would add a few milliseconds of nothing to the front of every take.
        converter.primeMethod = .none
        converter.sampleRateConverterQuality = .max
        self.converter = converter
        self.input = input
        self.output = output
        ratio = AudioFormat.sampleRate / sampleRate
    }

    func convert(_ samples: UnsafeBufferPointer<Float>) -> [Float] {
        guard samples.count > 0, let baseAddress = samples.baseAddress,
              let buffer = AVAudioPCMBuffer(pcmFormat: input, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0]
        else { return [] }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        channel.update(from: baseAddress, count: samples.count)

        let capacity = AVAudioFrameCount(Double(samples.count) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: capacity) else { return [] }
        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed {
                status.pointee = .noDataNow
                return nil
            }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, out.frameLength > 0, let data = out.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: data, count: Int(out.frameLength)))
    }
}
