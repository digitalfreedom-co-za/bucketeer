//
//  ArrayChunked.swift
//  BucketeerCore
//
//  Created by Marcel R. G. Berger on 24.05.26.
//

import Foundation

extension Array {
    /// Split the array into fixed-size chunks. The last chunk may be
    /// shorter than `size`. Empty arrays produce an empty chunk list.
    /// Used by the S3 `DeleteObjects` batcher (1000-key cap) and the
    /// recursive folder delete path in the File Provider.
    func chunked(by size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        guard !isEmpty else { return [] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
