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
class RetryScheduler {
    private var workItem: DispatchWorkItem?
    private let config: RetryConfig

    /// Initialize with custom configuration
    init(config: RetryConfig = .accessibilityAPI) {
        self.config = config
    }

    /// Cancel any pending retry
    func cancel() {
        workItem?.cancel()
        workItem = nil
    }

    /// Execute operation with automatic retry logic
    /// - Parameters:
    ///   - attempt: Current attempt number (starts at 0)
    ///   - operation: Closure that returns RetryResult
    ///   - completion: Called with final success or failure
    func execute<T>(
        attempt: Int = 0,
        operation: @escaping () -> RetryResult<T>,
        completion: @escaping (Result<T, Error>) -> Void
    ) {
        // Check if we've exceeded max attempts
        guard attempt <= config.maxAttempts else {
            completion(.failure(RetryError.maxAttemptsExceeded(config.maxAttempts)))
            return
        }

        // Execute the operation
        let result = operation()

        switch result {
        case .success(let value):
            // Success - cancel any pending retries and complete
            cancel()
            completion(.success(value))

        case .retry(let error):
            // Retry requested
            if attempt < config.maxAttempts {
                scheduleRetry(attempt: attempt) { [weak self] in
                    self?.execute(attempt: attempt + 1, operation: operation, completion: completion)
                }
            } else {
                // Max attempts reached
                completion(.failure(RetryError.maxAttemptsExceeded(config.maxAttempts, lastError: error)))
            }

        case .failure(let error):
            // Permanent failure - don't retry
            cancel()
            completion(.failure(error))
        }
    }

    /// Schedule a retry with exponential backoff
    private func scheduleRetry(attempt: Int, action: @escaping () -> Void) {
        // Cancel any existing retry
        cancel()

        // Calculate delay
        let delay = config.delay(for: attempt)

        Logger.debug("RetryScheduler: Scheduling retry \(attempt + 1)/\(config.maxAttempts) in \(String(format: "%.3f", delay))s", category: Logger.general)

        // Schedule retry
        let item = DispatchWorkItem(block: action)
        workItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
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
