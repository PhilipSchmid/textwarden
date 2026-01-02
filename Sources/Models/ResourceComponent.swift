// ResourceComponent.swift
// Represents different components of the application for resource tracking

import Foundation
import SwiftUI

/// Represents different components of the application for resource tracking
public enum ResourceComponent: String, Codable, CaseIterable, Sendable {
    case swiftApp = "Swift Application"
    case grammarEngine = "Grammar Engine (Rust)"
    case styleEngine = "Style Engine (Rust)" // Future: LLM/AI model

    var identifier: String {
        rawValue
    }

    var color: Color {
        switch self {
        case .swiftApp: .blue
        case .grammarEngine: .orange
        case .styleEngine: .purple
        }
    }
}
