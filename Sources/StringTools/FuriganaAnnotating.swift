//
//  File.swift
//  
//
//  Created by Morten Bertz on 2021/04/15.
//

import Foundation

public protocol FuriganaAnnotating {
    var base:String {get}
    var reading:String {get}
    var range:Range<String.Index> {get}
    
    func furiganaAnnotation(for text:String, kanjiOnly:Bool) -> [FuriganaAnnotation]?
}

extension FuriganaAnnotating {
    public func scanAnnotation() -> [FuriganaAnnotation] {
        
        guard self.base.containsKanjiCharacters else{
            return []
        }

        var reading = reading
        var tempBase = base

        let hiraganaNSRanges = base.hiraganaRanges.map({ NSRange($0, in: base) })

        guard !hiraganaNSRanges.isEmpty else {
            return [.init(reading: reading, range: range)]
        }

        var result = [FuriganaAnnotation]()

        var removedBase = ""
        var removedReading = ""

        for (index, char) in base.enumerated() {
            guard String(char).containsKanjiCharacters, tempBase.contains(char) else {
                if !reading.isEmpty, let first = reading.first {
                    removedReading += String(first)
                    reading.removeFirst(1)
                }
                if !tempBase.isEmpty, let first = tempBase.first {
                    removedBase += String(first)
                    tempBase.removeFirst(1)
                }
                continue
            }
            var lastRange: NSRange?
            for (rangeIndex, range) in hiraganaNSRanges.enumerated() {

                // find next hiragana range
                guard range.location > index else {
                    lastRange = range
                    continue
                }
                
                guard let kanaRange = Range(range, in: base) else { continue }
                let nextKana = base.substring(with: kanaRange)
                guard let rangeInReading = reading.range(of: nextKana) else { continue }
                var nsRangeInReading = NSRange(rangeInReading, in: reading)
                nsRangeInReading = NSRange(
                    location: nsRangeInReading.location + removedReading.count,
                    length: nsRangeInReading.length
                )
                
                // current kana range
                let end = nsRangeInReading.location
                let start = removedReading.count
                let kanaLength = end - start
                let readingRange = NSRange(location: start, length: kanaLength)
                
                // current kanji range
                let kanjiStart = (lastRange?.location ?? 0) + (lastRange?.length ?? 0)
                var kanjiEnd = index + 1
                for object in tempBase.enumerated() {
                    if String(object.element).containsKanjiCharacters {
                        if object.offset == tempBase.count - 1 {
                            kanjiEnd = base.count - 1
                        }
                    } else {
                        kanjiEnd = object.offset + removedBase.count
                        break
                    }
                }
                let kanjiLength = kanjiEnd - kanjiStart
                let kanjiRange = NSRange(location: kanjiStart, length: kanjiLength)
                
                if let kanaRange = Range(readingRange, in: self.reading),
                   let kanjiRange = Range(kanjiRange, in: self.base),
                   self.reading.count >= kanaLength
                {
                    result.append(.init(reading: self.reading.substring(with: kanaRange), range: kanjiRange))
                    if reading.count >= kanaLength {
                        removedReading += reading[
                            reading.startIndex..<reading.index(reading.startIndex, offsetBy: kanaLength)
                        ]
                        reading.removeFirst(kanaLength)
                    }
                    if tempBase.count >= kanjiLength {
                        removedBase += tempBase[
                            tempBase.startIndex..<tempBase.index(tempBase.startIndex, offsetBy: kanjiLength)
                        ]
                        tempBase.removeFirst(kanjiLength)
                    }
                    break
                }
            }
        }
        if !tempBase.isEmpty && !reading.isEmpty {
            let kanjiRange = NSRange(location: removedBase.count, length: tempBase.count)
            if let range = Range(kanjiRange, in: self.base) {
                result.append(.init(reading: reading, range: range))
            }
        }
        return result
    }

    public func furiganaAnnotation(for text:String, kanjiOnly:Bool) -> [FuriganaAnnotation]?{
        
        guard kanjiOnly == true else{
            return [FuriganaAnnotation(reading: self.reading, range: self.range)]
        }
        
        var range = self.range
        var transliteration = self.reading
        
        let hiraganaRanges = self.base.hiraganaRanges

        var lastUpperBound: String.Index?
        var results: [FuriganaAnnotation] = []

        for hiraganaRange in hiraganaRanges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            switch hiraganaRange {
            case _ where hiraganaRange.upperBound == self.base.endIndex:
                let trailingDistance = self.base.distance(from: self.base.endIndex, to: hiraganaRange.lowerBound)
                let newEndIndex = text.index(range.upperBound, offsetBy: trailingDistance)
                range = range.lowerBound..<newEndIndex
                let transliterationEnd = transliteration.index(transliteration.endIndex, offsetBy: trailingDistance)
                let newTransliterationRange = transliteration.startIndex..<transliterationEnd
                let t2 = transliteration[newTransliterationRange]
                transliteration = String(t2)
            case _ where hiraganaRange.lowerBound == self.base.startIndex:
                let leadingDistance = self.base.distance(from: self.base.startIndex, to: hiraganaRange.upperBound)
                let newStartIndex = text.index(range.lowerBound, offsetBy: leadingDistance) // wrong?
                range = newStartIndex..<range.upperBound
                let transliterationStart = transliteration.index(transliteration.startIndex, offsetBy: leadingDistance)
                let newTransliterationRange = transliterationStart..<transliteration.endIndex
                let t2 = transliteration[newTransliterationRange]
                transliteration = String(t2)
            default:
                let detectedCenterHiragana = self.base[hiraganaRange]
                let parts = transliteration.components(separatedBy: detectedCenterHiragana)
                
                let distance1 = self.base.distance(from: self.base.startIndex, to: hiraganaRange.lowerBound)
                let range1End = text.index(range.lowerBound, offsetBy: distance1)
                let range1 = range.lowerBound..<range1End
                
                let distance2 = self.base.distance(from: hiraganaRange.upperBound, to: self.base.endIndex)
                let range2Start = text.index(range.lowerBound, offsetBy: distance2)
                let range2 = range2Start..<range.upperBound
                
                results.append(FuriganaAnnotation(reading: parts.first ?? "", range: range1))
                results.append(FuriganaAnnotation(reading: parts.last ?? "", range: range2))
                return results
            }
        }
        
        guard transliteration.isEmpty == false else {return nil}
        return [FuriganaAnnotation(reading: transliteration, range: range)]
    }
}
