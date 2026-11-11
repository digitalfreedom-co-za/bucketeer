import BucketeerCore
import Foundation

extension S3Provider {
    /// Provider brands stay verbatim; generic labels use the host app's catalog.
    var localizedDisplayName: String {
        self == .custom ? String(localized: "provider.custom") : displayName
    }
}
