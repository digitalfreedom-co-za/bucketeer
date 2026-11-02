//
//  SyncLabels.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 02.11.26.
//

import SwiftUI
import BucketeerCore

/// User-facing names for sync modes and schedules. The raw values are
/// storage identifiers (`interval=3600`) and must not reach the UI.
extension SyncMode {
    var labelKey: LocalizedStringKey {
        switch self {
        case .copy:   return "sync.mode.copy"
        case .move:   return "sync.mode.move"
        case .mirror: return "sync.mode.mirror"
        }
    }
}

extension SyncSchedule {
    var label: Text {
        switch self {
        case .manual:                return Text("sync.schedule.manual")
        case .onLaunch:              return Text("sync.schedule.onLaunch")
        case .interval(let seconds): return Text("sync.field.intervalMinutes \(seconds / 60)")
        case .onLocalChange:         return Text("sync.schedule.onLocalChange")
        }
    }
}
