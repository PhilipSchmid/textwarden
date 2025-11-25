// ResourceComponent.swift
// Represents different components of the application for resource tracking

import Foundation
import SwiftUI

/// Represents different components of the application for resource tracking
public enum ResourceComponent: String, Codable, CaseIterable {
    case swiftApp = "Swift Application"
    case grammarEngine = "Grammar Engine (Rust)"
    case styleEngine = "Style Engine (Rust)"  // Future: LLM/AI model

    var identifier: String {
        return self.rawValue
    }

    var color: Color {
        switch self {
        case .swiftApp: return .blue
        case .grammarEngine: return .orange
        case .styleEngine: return .purple
        }
    }
}
