//  Copyright © 2016 Venture Media. All rights reserved.

import FeatureExtraction
import Upsurge

public class Tracker {
    let onsetThreshold = Float(0.5)
    let lookahead = 4
    let weights: [Double] = [1.5, 1.1, 1.6, 1.7, 1.8]

    let configuration: Configuration
    let decayModel: DecayModel
    
    /// List of reference onsets
    let onsets: [Onset]

    /// Current event index
    public private(set) var index = 0

    /// Current tempo in beats per second
    public var tempo = 1.0

    public var lastOnsetValue: Float = 0.0

    public var didMoveCursorAction: (Int -> Void)?

    public init(onsets: [Onset], configuration: Configuration) {
        self.configuration = configuration
        self.decayModel = DecayModel(representableNoteRange: configuration.representableNoteRange)
        self.onsets = onsets
    }

    /// Start tracking
    ///
    /// - parameter position: The current cursor position as an index of the event list
    /// - parameter tempo: The song's current tempo in beats per second
    func start(position: Int, tempo: Double) {
        self.index = position
        self.tempo = tempo
    }

    /// Update with the output of the neural net
    public func update(onset: Float, notes: ValueArray<Float>) {
        defer {
            lastOnsetValue = onset
        }
        if lastOnsetValue < 0.5 || onset > 0.5 {
            return
        }

        var distances = [(Double, Int)]()

        for i in 0...lookahead {
            guard index + i < onsets.count  else {
                break
            }

            let onset = onsets[index + i]
            let label = labelForOnset(onset)
            let d = distance(label, notes) * weights[i]
            distances.append((d, i))
        }

        var minDistance: Double? = nil
        var offset = 0
        for (d, o) in distances {
            if minDistance == nil || d < minDistance! {
                minDistance = d
                offset = o
            }
        }

        if offset != 0 {
            index += offset
            didMoveCursorAction?(index)
        }
    }

    func closeToOnset(beat: Double) -> Bool {
        var closestOnsetIndex = 0
        var closestDistance: Double?
        for (i, event) in onsets.enumerate() {
            let d = abs(Double(event.start) - beat)
            if closestDistance == nil || d < closestDistance! {
                closestDistance = d
                closestOnsetIndex = i
            }
        }

        if closestDistance == nil {
            return false
        }

        let closestOnset = onsets[closestOnsetIndex]
        let otherIndex = closestOnsetIndex == onsets.count - 1 ? 0 : closestOnsetIndex + 1
        let beatsPerSecond = Double(closestOnset.start - onsets[otherIndex].start) / (closestOnset.wallTime - onsets[otherIndex].wallTime)
        let timeDistance = abs(closestOnset.wallTime - beat / beatsPerSecond)
        return timeDistance <= Double(configuration.windowSize / 2) / configuration.samplingFrequency
    }

    func labelForOnset(event: Onset) -> ValueArray<Float> {
        let label = ValueArray<Float>(count: configuration.representableNoteRange.count, repeatedValue: 0.0)
        for note in event.notes {
            label[note.midiNoteNumber - configuration.representableNoteRange.startIndex] = 1.0
        }
        return label
    }

    func distance(labels: ValueArray<Float>, _ notes: ValueArray<Float>) -> Double {
        var sum = 0.0
        for (label, note) in zip(labels, notes) {
            let d = Double(label - note)
            sum += d * d
        }
        return sqrt(sum)
    }
}
