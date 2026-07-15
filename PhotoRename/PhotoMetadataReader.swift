//
//  PhotoMetadataReader.swift
//  PhotoDateRenamer
//
//  Created by Hideko Ogawa on 2026/07/15.
//

import Foundation
import ImageIO

enum PhotoMetadataReader {
  struct Result: Sendable {
    let date: Date?
    let timeZone: TimeZone?
    let source: RenameItem.DateSource
  }

  nonisolated static func captureDate(
    for url: URL,
    useFileCreationDateAsFallback: Bool
  ) -> Result {
    if let exif = readExifDate(from: url) {
      return Result(
        date: exif.date,
        timeZone: exif.timeZone,
        source: .exif
      )
    }

    if useFileCreationDateAsFallback,
      let fileDate = readFileCreationDate(from: url)
    {
      return Result(
        date: fileDate,
        timeZone: nil,
        source: .fileCreationDate
      )
    }

    return Result(
      date: nil,
      timeZone: nil,
      source: .unavailable
    )
  }

  nonisolated private static func readExifDate(
    from url: URL
  ) -> (date: Date, timeZone: TimeZone?)? {
    guard
      let imageSource = CGImageSourceCreateWithURL(
        url as CFURL,
        nil
      )
    else {
      return nil
    }

    guard
      let properties = CGImageSourceCopyPropertiesAtIndex(
        imageSource,
        0,
        nil
      ) as? [CFString: Any]
    else {
      return nil
    }

    let exif =
      properties[
        kCGImagePropertyExifDictionary
      ] as? [CFString: Any]

    let tiff =
      properties[
        kCGImagePropertyTIFFDictionary
      ] as? [CFString: Any]

    /*
     優先順位：

     DateTimeOriginal + OffsetTimeOriginal
     DateTimeDigitized + OffsetTimeDigitized
     TIFF DateTime + OffsetTime
     */

    if let dateString =
      exif?[kCGImagePropertyExifDateTimeOriginal] as? String
    {

      let offsetString =
        exif?[kCGImagePropertyExifOffsetTimeOriginal] as? String

      if let result = parseExifDate(
        dateString,
        offsetString: offsetString
      ) {
        return result
      }
    }

    if let dateString = exif?[kCGImagePropertyExifDateTimeDigitized] as? String {
      let offsetString = exif?[kCGImagePropertyExifOffsetTimeDigitized] as? String

      if let result = parseExifDate(dateString, offsetString: offsetString ) {
        return result
      }
    }

    if let dateString = tiff?[kCGImagePropertyTIFFDateTime] as? String {
      let offsetString = exif?[kCGImagePropertyExifOffsetTime] as? String
      if let result = parseExifDate(dateString, offsetString: offsetString){
        return result
      }
    }

    return nil
  }

  nonisolated private static func readFileCreationDate(from url: URL) -> Date? {
    do {
      let values = try url.resourceValues(
        forKeys: [
          .creationDateKey,
          .contentModificationDateKey,
        ]
      )

      return values.creationDate ?? values.contentModificationDate
    } catch {
      return nil
    }
  }

  nonisolated private static func parseExifDate(_ dateString: String, offsetString: String?) -> (date: Date, timeZone: TimeZone?)? {
    let locale = Locale(identifier: "en_US_POSIX")

    if let offsetString, let timeZone = timeZone(from: offsetString) {
      let formatter = DateFormatter()
      formatter.locale = locale
      formatter.calendar = Calendar(identifier: .gregorian)
      formatter.timeZone = timeZone
      formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"

      guard let date = formatter.date(from: dateString) else { return nil }

      return (date, timeZone)
    }

    /*
     オフセットがない写真。

     ここではMacの現在のタイムゾーンとして解釈する。
     別の方針として「タイムゾーン不明」のまま扱うことも可能。
     */
    let fallbackTimeZone = TimeZone.current

    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = fallbackTimeZone
    formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"

    guard let date = formatter.date(from: dateString) else {
      return nil
    }

    return (date, nil)
  }

  nonisolated private static func timeZone(
    from offsetString: String
  ) -> TimeZone? {
    /*
     想定形式:
     +09:00
     -10:00
     +05:30
     */

    let pattern = #"^([+-])(\d{2}):(\d{2})$"#

    guard
      let regex = try? NSRegularExpression(
        pattern: pattern
      )
    else {
      return nil
    }

    let range = NSRange(
      offsetString.startIndex...,
      in: offsetString
    )

    guard
      let match = regex.firstMatch(
        in: offsetString,
        range: range
      ),
      let signRange = Range(match.range(at: 1), in: offsetString),
      let hourRange = Range(match.range(at: 2), in: offsetString),
      let minuteRange = Range(match.range(at: 3), in: offsetString),
      let hours = Int(offsetString[hourRange]),
      let minutes = Int(offsetString[minuteRange])
    else {
      return nil
    }

    let sign = offsetString[signRange] == "-" ? -1 : 1
    let seconds = sign * ((hours * 60 + minutes) * 60)

    return TimeZone(secondsFromGMT: seconds)
  }
}
