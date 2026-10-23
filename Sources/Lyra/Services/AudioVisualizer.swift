import Foundation
import AVFoundation
import MediaToolbox
import Accelerate

/// Real-time spectrum analyzer. It taps the audio coming out of an AVPlayerItem
/// (via MTAudioProcessingTap), runs an FFT (Accelerate/vDSP) on the samples and
/// exposes a small set of frequency-band levels (0...1) for the visualizer UI.
///
/// The tap callbacks run on a real-time audio thread, so all shared state is
/// guarded by a lock. `currentLevels()` is safe to call from the main actor.
final class AudioVisualizer: @unchecked Sendable {

    static let bandCount = 48

    private let fftSize = 1024
    private let log2n: vDSP_Length = 10        // log2(1024)
    private let hop = 512

    private let lock = NSLock()
    private var bands = [Float](repeating: 0, count: AudioVisualizer.bandCount)

    // FFT scratch (only touched on the audio thread)
    private let fftSetup: FFTSetup
    private var window: [Float]
    private var ring: [Float]
    private var ringFilled = 0
    private var realp: [Float]
    private var imagp: [Float]
    private var magnitudes: [Float]
    private var mono: [Float] = []

    private var sampleRate: Double = 44_100
    private var bandBins: [(lo: Int, hi: Int)] = []
    private var prepared = false

    init() {
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        window = [Float](repeating: 0, count: fftSize)
        ring = [Float](repeating: 0, count: fftSize)
        realp = [Float](repeating: 0, count: fftSize / 2)
        imagp = [Float](repeating: 0, count: fftSize / 2)
        magnitudes = [Float](repeating: 0, count: fftSize / 2)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        computeBandBins()
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    // MARK: - Public

    /// Latest band levels (0...1), thread-safe copy.
    func currentLevels() -> [Float] {
        lock.lock(); defer { lock.unlock() }
        return bands
    }

    /// Builds an AVAudioMix that routes the item's audio through the analyzer.
    @MainActor
    func makeAudioMix(for item: AVPlayerItem) async -> AVAudioMix? {
        guard let track = try? await item.asset.loadTracks(withMediaType: .audio).first else {
            return nil
        }

        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: UnsafeMutableRawPointer(Unmanaged.passRetained(self).toOpaque()),
            init: tapInit,
            finalize: tapFinalize,
            prepare: tapPrepare,
            unprepare: tapUnprepare,
            process: tapProcess
        )

        var tap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(
            kCFAllocatorDefault, &callbacks,
            kMTAudioProcessingTapCreationFlag_PostEffects, &tap
        )
        guard status == noErr, let tap else {
            // creation failed → balance the retain we did for clientInfo
            Unmanaged.passUnretained(self).release()
            return nil
        }

        let params = AVMutableAudioMixInputParameters(track: track)
        params.audioTapProcessor = tap
        let mix = AVMutableAudioMix()
        mix.inputParameters = [params]
        return mix
    }

    // MARK: - Called from the audio thread

    fileprivate func prepare(sampleRate: Double) {
        lock.lock()
        self.sampleRate = sampleRate
        computeBandBins()
        ringFilled = 0
        prepared = true
        lock.unlock()
    }

    fileprivate func processAudio(_ bufferList: UnsafeMutablePointer<AudioBufferList>, frames: Int) {
        guard prepared, frames > 0 else { return }
        let abl = UnsafeMutableAudioBufferListPointer(bufferList)

        if mono.count < frames { mono = [Float](repeating: 0, count: frames) }
        for i in 0..<frames { mono[i] = 0 }

        var channels = 0
        for buffer in abl {
            guard let raw = buffer.mData else { continue }
            let ptr = raw.assumingMemoryBound(to: Float.self)
            let ch = Int(buffer.mNumberChannels)
            if ch <= 1 {
                for i in 0..<frames { mono[i] += ptr[i] }
            } else {
                for i in 0..<frames {
                    var s: Float = 0
                    for c in 0..<ch { s += ptr[i * ch + c] }
                    mono[i] += s / Float(ch)
                }
            }
            channels += 1
        }
        if channels > 1 {
            for i in 0..<frames { mono[i] /= Float(channels) }
        }

        // Feed samples into the analysis window, emitting an FFT every `hop` samples.
        var offset = 0
        while offset < frames {
            let copy = min(fftSize - ringFilled, frames - offset)
            for i in 0..<copy { ring[ringFilled + i] = mono[offset + i] }
            ringFilled += copy
            offset += copy

            if ringFilled == fftSize {
                computeSpectrum()
                // slide window by hop, keep the overlap
                let keep = fftSize - hop
                for i in 0..<keep { ring[i] = ring[i + hop] }
                ringFilled = keep
            }
        }
    }

    // MARK: - FFT

    private func computeSpectrum() {
        // Apply Hann window in place into a scratch buffer
        var windowed = [Float](repeating: 0, count: fftSize)
        vDSP_vmul(ring, 1, window, 1, &windowed, 1, vDSP_Length(fftSize))

        let half = fftSize / 2
        realp.withUnsafeMutableBufferPointer { rp in
            imagp.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                windowed.withUnsafeBufferPointer { wp in
                    wp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) { cp in
                        vDSP_ctoz(cp, 2, &split, 1, vDSP_Length(half))
                    }
                }
                vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(half))
            }
        }

        // Map magnitudes to log-spaced bands with perceptual scaling.
        var newBands = [Float](repeating: 0, count: Self.bandCount)
        let scale = 2.0 / Float(fftSize)
        for b in 0..<Self.bandCount {
            let range = bandBins[b]
            guard range.hi >= range.lo else { continue }
            var sum: Float = 0
            for bin in range.lo...range.hi { sum += magnitudes[bin] }
            let avg = sum / Float(range.hi - range.lo + 1)
            // magnitude (sqrt of power), normalized, then a gentle curve + gain
            var level = sqrtf(avg) * scale
            level = sqrtf(level) * 1.7        // perceptual lift
            newBands[b] = min(level, 1)
        }

        lock.lock()
        bands = newBands
        lock.unlock()
    }

    private func computeBandBins() {
        let half = fftSize / 2
        let minFreq: Double = 30
        let maxFreq = min(16_000, sampleRate / 2)
        var bins: [(Int, Int)] = []
        var previousHi = 0
        for b in 0..<Self.bandCount {
            let f0 = minFreq * pow(maxFreq / minFreq, Double(b) / Double(Self.bandCount))
            let f1 = minFreq * pow(maxFreq / minFreq, Double(b + 1) / Double(Self.bandCount))
            var lo = Int(f0 * Double(fftSize) / sampleRate)
            var hi = Int(f1 * Double(fftSize) / sampleRate)
            lo = max(1, min(lo, half - 1))
            hi = max(lo, min(hi, half - 1))
            if hi <= previousHi { hi = min(previousHi + 1, half - 1); lo = min(lo, hi) }
            previousHi = hi
            bins.append((lo, hi))
        }
        bandBins = bins
    }
}

// MARK: - C tap callbacks (run on the real-time audio thread)

private let tapInit: MTAudioProcessingTapInitCallback = { _, clientInfo, tapStorageOut in
    tapStorageOut.pointee = clientInfo
}

private let tapFinalize: MTAudioProcessingTapFinalizeCallback = { tap in
    Unmanaged<AudioVisualizer>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
}

private let tapPrepare: MTAudioProcessingTapPrepareCallback = { tap, _, format in
    let analyzer = Unmanaged<AudioVisualizer>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
    analyzer.prepare(sampleRate: format.pointee.mSampleRate)
}

private let tapUnprepare: MTAudioProcessingTapUnprepareCallback = { _ in }

private let tapProcess: MTAudioProcessingTapProcessCallback = { tap, numberFrames, _, bufferListInOut, numberFramesOut, flagsOut in
    let status = MTAudioProcessingTapGetSourceAudio(tap, numberFrames, bufferListInOut, flagsOut, nil, numberFramesOut)
    guard status == noErr else { return }
    let analyzer = Unmanaged<AudioVisualizer>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
    analyzer.processAudio(bufferListInOut, frames: Int(numberFramesOut.pointee))
}
