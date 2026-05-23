//
//  FileProviderEnumerator.swift
//  Bucketeer File Provider
//
//  Created by Marcel R. G. Berger on 23.05.26.
//

import Foundation
import FileProvider

/// Walks one prefix worth of objects for the system enumerator. In v1
/// this is a stub that returns an empty page so mounted buckets show
/// up in Finder without populating files; v1.1 wires the actual S3 /
/// Azure listing once the Core framework is extracted.
final class FileProviderEnumerator: NSObject, NSFileProviderEnumerator {
    let domain: NSFileProviderDomain
    let container: NSFileProviderItemIdentifier

    init(domain: NSFileProviderDomain, container: NSFileProviderItemIdentifier) {
        self.domain = domain
        self.container = container
        super.init()
    }

    func invalidate() {}

    func enumerateItems(
        for observer: NSFileProviderEnumerationObserver,
        startingAt page: NSFileProviderPage
    ) {
        observer.finishEnumerating(upTo: nil)
    }

    func enumerateChanges(
        for observer: NSFileProviderChangeObserver,
        from syncAnchor: NSFileProviderSyncAnchor
    ) {
        observer.finishEnumeratingChanges(upTo: syncAnchor, moreComing: false)
    }

    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        completionHandler(NSFileProviderSyncAnchor(Data("v1".utf8)))
    }
}
