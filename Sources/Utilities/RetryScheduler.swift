//
//  RetryScheduler.swift
//  TextWarden
//
//  Reusable retry scheduler with exponential backoff
//

import Foundation

/// Configuration for retry behavior
struct RetryConfig {
    /// Initial delay before first retry (in seconds)
    let initialDelay: TimeInterval

    /// Multiplier applied to delay for each retry attempt
    let multiplier: Double

    /// Maximum number of retry attempts
    let maxAttempts: Int

    /// Default configuration for accessibility API retries
    static let accessibilityAPI = RetryConfig(
        initialDelay: 0.3,  // 300ms
        multiplier: 1.25,
        maxAttempts: 10     // ~10 seconds total
    )

    /// Calculate delay for a specific retry attempt
    func delay(for attempt: Int) -> TimeInterval {
        return initialDelay * pow(multiplier, Double(attempt))
    }
}

/// Result of a retryable operation
enum RetryResult<T> {
    case success(T)
    case retry(Error)
    case failure(Error)
}

/// Reusable retry scheduler with exponential backoff
/// Handles automatic retry logic with configurable delays and max attempts
final class RetryScheduler: @unchecked Sendable {
    private var currentTask: Task<Void, Never>?
    private let config: RetryConfig
    private let lock = NSLock()

    /// Initialize with custom configuration
    init(config: RetryConfig = .accessibilityAPI) {
        self.config = config
    }

    /// Cancel any pending retry
    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        currentTask?.cancel()
        currentTask = nil
    }

    /// Execute operation with automatic retry logic using async/await
    /// - Parameters:
    ///   - operation: Closure that returns RetryResult
    /// - Returns: The successful result value
    /// - Throws: RetryError if max attempts exceeded or permanent failure
    func execute<T>(
        operation: @escaping () -> RetryResult<T>
    ) async throws -> T {
        var attempt = 0

        while attempt <= config.maxAttempts {
            // Check for cancellation
            try Task.checkCancellation()

            // Execute the operation
            let result = operation()

            switch result {
            case .success(let value):
                return value

            case .retry(let error):
                if attempt < config.maxAttempts {
                    // Calculate delay and sleep
                    let delay = config.delay(for: attempt)
                    Logger.debug("RetryScheduler: Scheduling retry \(attempt + 1)/\(config.maxAttempts) in \(String(format: "%.3f", delay))s", category: Logger.general)

                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    attempt += 1
                } else {
                    throw RetryError.maxAttemptsExceeded(config.maxAttempts, lastError: error)
                }

            case .failure(let error):
                throw error
            }
        }

        throw RetryError.maxAttemptsExceeded(config.maxAttempts)
    }

    /// Execute operation with completion handler (legacy compatibility)
    /// - Parameters:
    ///   - attempt: Current attempt number (starts at 0)
    ///   - operation: Closure that returns RetryResult
    ///   - completion: Called with final success or failure
    func execute<T>(
        attempt: Int = 0,
        operation: @escaping () -> RetryResult<T>,
        completion: @escaping (Result<T, Error>) -> Void
    ) {
        Task {
            do {
                let result = try await self.execute(operation: operation)
                await MainActor.run {
                    completion(.success(result))
                }
            } catch {
                await MainActor.run {
                    completion(.failure(error))
                }
            }
        }
    }
}

/// Errors thrown by RetryScheduler
enum RetryError: LocalizedError {
    case maxAttemptsExceeded(Int, lastError: Error? = nil)

    var errorDescription: String? {
        switch self {
        case .maxAttemptsExceeded(let attempts, let lastError):
            if let lastError = lastError {
                return "Maximum retry attempts (\(attempts)) exceeded. Last error: \(lastError.localizedDescription)"
            }
            return "Maximum retry attempts (\(attempts)) exceeded"
        }
    }
}
