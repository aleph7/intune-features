//  Copyright © 2016 Venture Media. All rights reserved.

import Peak
import AudioToolbox


class MIDIMixer {
    let minChunkSize = 3
    let maxChunkSize = 20
    let maxDelay = 0.07

    let duplicationProbability = 0.2



    var inputFile: MIDIFile

    init(inputFile: MIDIFile) {
        self.inputFile = inputFile
    }

    func mix() -> MusicSequence {
        var inputEvents = inputFile.noteEvents
        var chunks = splitChunks(&inputEvents)
        duplicateChunks(&chunks)
        addDelays(&chunks)

        var sequence = sequenceFromChunk(chunks.flatMap({ $0 }))
        setTempo(&sequence)
        return sequence
    }

    func splitChunks(inout inputEvents: [MIDINoteEvent]) -> [Chunk] {
        var chunkedEvents = chunkFromEvents(inputEvents)
        var splitChunks = [Chunk]()

        var chunkSize = min(random(min: minChunkSize, max: maxChunkSize), inputEvents.count)
        var chunk = Chunk()
        var chordCount = 0
        var noteCount = 0
        applyToChords(&chunkedEvents) { chord in
            if chordCount < chunkSize {
                chunk.append(chord)
                chordCount += 1
                noteCount += chord.count
            } else {
                splitChunks.append(chunk)
                chunkSize = min(random(min: self.minChunkSize, max: self.maxChunkSize), inputEvents.count - noteCount)
                chunk = Chunk([chord])
                chordCount = 0
                noteCount = 0
            }
        }
        if chordCount > 0 {
            splitChunks.append(chunk)
        }
        return splitChunks
    }

    func duplicateChunks(inout chunks: [Chunk]) {
        let iterableChunks = chunks
        var offset = 0
        for (i, chunk) in iterableChunks.enumerate() {
            if random(probability: duplicationProbability) {
                chunks.insert(chunks[i+offset], atIndex: i+offset)
                offset += 1
                shiftChunks(&chunks[i+offset..<chunks.count], offset: duration(chunk))
            }
        }
    }

    func addDelays(inout chunks: [Chunk]) {
        var offset = 0.0
        applyToChords(&chunks){ chord in
            let delay = random(min: -self.maxDelay, max: self.maxDelay+1)
            for i in 0..<chord.count {
                chord[i].timeStamp = max(chord[i].timeStamp + offset + delay, 0)
            }
            offset += delay
        }
    }

    func sequenceFromChunk(chunk: Chunk) -> MusicSequence {
        var sequence: MusicSequence = nil
        guard NewMusicSequence(&sequence) == noErr else {
            fatalError("Failed to create MusicSequence")
        }
        trackFromChunk(&sequence, chunk: chunk)
        return sequence
    }

    func trackFromChunk(inout sequence: MusicSequence, chunk: Chunk) {
        var track: MusicTrack = nil

        guard MusicSequenceNewTrack(sequence, &track) == noErr else {
            fatalError("Failed to add track to sequence.")
        }

        for chord in chunk {
            for event in chord {
                var message = MIDINoteMessage(channel: event.channel, note: event.note, velocity: event.velocity, releaseVelocity: 0, duration: event.duration)
                MusicTrackNewMIDINoteEvent(track, event.timeStamp, &message)
            }
        }

    }

    func setTempo(inout sequence: MusicSequence) {
        var tempoTrack: MusicTrack = nil
        guard MusicSequenceGetTempoTrack(sequence, &tempoTrack) == noErr else {
            fatalError("Could not read tempo track")
        }

        var trackLength = MusicTimeStamp()
        guard MusicTrackGetProperty(tempoTrack, kSequenceTrackProperty_TrackLength, &trackLength, nil) == noErr else {
            fatalError("Could not read track length")
        }

        if trackLength != 0 {
            guard MusicTrackClear(tempoTrack, 0, trackLength) == noErr else {
                fatalError("Could not clear tempo track")
            }
        }

        for event in inputFile.tempoEvents {
            guard MusicTrackNewExtendedTempoEvent(tempoTrack, event.timeStamp, event.bpm) == noErr else {
                fatalError("Could not create tempo event")
            }
        }
    }
}