//
//  ConflictCopyName.swift
//  BucketeerCore
//
//  Created by Marcel R. G. Berger on 02.11.26.
//

import Foundation

/// Names the copy Bucketeer uploads when a local edit collides with a
/// change on the server: `<name> (conflict <date>).<ext>` next to the
/// original. Shared by Open With and the File Provider extension so
/// both produce the same names.
public enum ConflictCopyName {
    public static func key(for key: String, date: Date, timeZone: TimeZone = .current) -> String {
        let slash = key.lastIndex(of: "/")
        let folder = slash.map { String(key[...$0]) } ?? ""
        let name = slash.map { String(key[key.index(after: $0)...]) } ?? key
        let marker = " (conflict \(timestamp(date, timeZone: timeZone)))"

        // A leading dot belongs to the name (".env"), not to an extension.
        if let dot = name.lastIndex(of: "."),
           dot != name.startIndex,
           name.index(after: dot) != name.endIndex {
            return folder + name[..<dot] + marker + name[dot...]
        }
        return folder + name + marker
    }

    /// Dots instead of colons: Finder shows a colon in a file name as "/".
    private static func timestamp(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter.string(from: date)
    }
}

/// ETags come quoted from some APIs and unquoted from others; compare
/// them without the quotes and add them back only on the wire.
public enum ETag {
    public static func normalized(_ etag: String) -> String {
        etag.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }

    public static func quoted(_ etag: String) -> String {
        "\"\(normalized(etag))\""
    }
}
