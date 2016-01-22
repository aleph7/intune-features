//  Copyright © 2015 Venture Media. All rights reserved.

import Accelerate
import Upsurge

public struct FeatureBuilder {
    /// Input audio data sampling frequency
    public static let samplingFrequency = 44100.0

    /// Analysis window size in samples
    public static let windowSize = 8*1024

    /// Step size between analysis windows
    public static let stepSize = 1024

    /// The range of notes to consider for labeling
    public static let notes = 36...96

    /// The range of notes to include in the spectrums
    public static let bandNotes = 24...120

    /// The note resolution for the spectrums
    public static let bandSize = 1.0
    
    /// The peak height cutoff as a multiplier of the RMS
    public static let peakHeightCutoffMultiplier = 0.05

    /// The minimum distance between peaks in notes
    public static let peakMinimumNoteDistance = 0.5

    /// Calculate the number of windows that fit inside the given number of samples
    public static func windowCountInSamples(samples: Int) -> Int {
        if samples < windowSize {
            return 0
        }
        return 1 + (samples - windowSize) / stepSize
    }

    /// Calculate the number of samples in the given number of contiguous windows
    public static func sampleCountInWindows(windowCount: Int) -> Int {
        if windowCount < 1 {
            return 0
        }
        return (windowCount - 1) * stepSize + windowSize
    }

    // Helpers
    public var window: RealArray
    public let fft = FFT(inputLength: windowSize)
    public let peakExtractor = PeakExtractor(heightCutoffMultiplier: peakHeightCutoffMultiplier, minimumNoteDistance: peakMinimumNoteDistance)
    public let fb = Double(samplingFrequency) / Double(windowSize)
    
    // Generators
    public let peakLocations = PeakLocationsFeatureGenerator(notes: bandNotes, bandSize: bandSize)
    public let peakHeights: PeakHeightsFeatureGenerator = PeakHeightsFeatureGenerator(notes: bandNotes, bandSize: bandSize)
    public let spectrumFeature0: SpectrumFeatureGenerator = SpectrumFeatureGenerator(notes: bandNotes, bandSize: bandSize)
    public let spectrumFeature1: SpectrumFeatureGenerator = SpectrumFeatureGenerator(notes: bandNotes, bandSize: bandSize)
    public let spectrumFluxFeature: SpectrumFluxFeatureGenerator = SpectrumFluxFeatureGenerator(notes: bandNotes, bandSize: bandSize)

    public init() {
        window = RealArray(count: FeatureBuilder.windowSize)
        vDSP_hamm_windowD(window.mutablePointer, vDSP_Length(FeatureBuilder.windowSize), 0)
    }

    public func generateFeatures<C: LinearType where C.Element == Real>(data0: C, _ data1: C) -> Feature {
        let rms = rmsq(data1)
        
        // Previous spectrum
        let spectrum0 = spectrumValues(data0)
        
        // Extract peaks
        let spectrum1 = spectrumValues(data1)
        let points1 = spectrumPoints(spectrum1)
        let peaks1 = peakExtractor.process(points1, rms: rms).sort{ $0.y > $1.y }
        
        peakLocations.update(peaks1)
        peakHeights.update(peaks1, rms: rms)
        spectrumFeature0.update(spectrum: spectrum0, baseFrequency: fb)
        spectrumFeature1.update(spectrum: spectrum1, baseFrequency: fb)
        spectrumFluxFeature.update(spectrum0: spectrumFeature0.data, spectrum1: spectrumFeature1.data)
        
        return Feature(
            rms: rms,
            spectrum: spectrumFeature1.data.copy(),
            spectralFlux: spectrumFluxFeature.data.copy(),
            peakHeights: peakHeights.data.copy(),
            peakLocations: peakLocations.data.copy()
        )
    }
    
    /// Compute the power spectrum values
    public func spectrumValues<C: LinearType where C.Element == Real>(data: C) -> RealArray {
        return sqrt(fft.forwardMags(data * window))
    }

    /// Convert from spectrum values to frequency, value points
    public func spectrumPoints<C: LinearType where C.Element == Real>(spectrum: C) -> [Point] {
        var points = [Point]()
        points.reserveCapacity(spectrum.count)
        for i in 0..<spectrum.count {
            let v = spectrum[i]
            points.append(Point(x: fb * Real(i), y: v))
        }
        return points
    }
}