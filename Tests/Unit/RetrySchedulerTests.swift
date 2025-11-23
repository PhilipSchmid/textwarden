//
//  RetrySchedulerTests.swift
//  TextWarden
//
//  Unit tests for RetryScheduler
//

import XCTest
@testable import TextWarden

final class RetrySchedulerTests: XCTestCase {

    // MARK: - RetryConfig Tests

    func testRetryConfigDefaultAccessibilityAPI() {
        let config = RetryConfig.accessibilityAPI

        XCTAssertEqual(config.initialDelay, 0.3, "Initial delay should be 300ms")
        XCTAssertEqual(config.multiplier, 1.25, "Multiplier should be 1.25x")
        XCTAssertEqual(config.maxAttempts, 10, "Max attempts should be 10")
    }

    func testRetryConfigDelayCalculation() {
        let config = RetryConfig.accessibilityAPI

        // Test exponential backoff calculation
        XCTAssertEqual(config.delay(for: 0), 0.3, accuracy: 0.001, "First retry at 300ms")
        XCTAssertEqual(config.delay(for: 1), 0.375, accuracy: 0.001, "Second retry at 375ms (300 * 1.25)")
        XCTAssertEqual(config.delay(for: 2), 0.46875, accuracy: 0.001, "Third retry at 468.75ms (300 * 1.25^2)")
    }

    func testCustomRetryConfig() {
        let customConfig = RetryConfig(
            initialDelay: 0.5,
            multiplier: 2.0,
            maxAttempts: 5
        )

        XCTAssertEqual(customConfig.initialDelay, 0.5)
        XCTAssertEqual(customConfig.multiplier, 2.0)
        XCTAssertEqual(customConfig.maxAttempts, 5)
        XCTAssertEqual(customConfig.delay(for: 0), 0.5, accuracy: 0.001)
        XCTAssertEqual(customConfig.delay(for: 1), 1.0, accuracy: 0.001, "0.5 * 2^1")
        XCTAssertEqual(customConfig.delay(for: 2), 2.0, accuracy: 0.001, "0.5 * 2^2")
    }

    // MARK: - RetryScheduler Tests

    func testRetrySchedulerCancel() {
        let scheduler = RetryScheduler()
        let expectation = self.expectation(description: "Cancel should prevent retry")
        expectation.isInverted = true  // Should NOT fulfill

        // Schedule a retry that should be canceled
        scheduler.execute(attempt: 0) { () -> RetryResult<String> in
            .retry(NSError(domain: "test", code: 1))
        } completion: { result in
            expectation.fulfill()
        }

        // Cancel immediately
        scheduler.cancel()

        // Wait to ensure it doesn't execute
        wait(for: [expectation], timeout: 1.0)
    }

    func testRetrySchedulerSuccess() {
        let scheduler = RetryScheduler()
        let expectation = self.expectation(description: "Success should complete immediately")

        scheduler.execute(attempt: 0) { () -> RetryResult<String> in
            .success("test value")
        } completion: { result in
            if case .success(let value) = result {
                XCTAssertEqual(value, "test value")
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 0.5)
    }

    func testRetrySchedulerPermanentFailure() {
        let scheduler = RetryScheduler()
        let expectation = self.expectation(description: "Permanent failure should not retry")

        let testError = NSError(domain: "test", code: 42)

        scheduler.execute(attempt: 0) { () -> RetryResult<String> in
            .failure(testError)
        } completion: { result in
            if case .failure(let error as NSError) = result {
                XCTAssertEqual(error.code, 42)
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 0.5)
    }

    func testRetrySchedulerMaxAttemptsExceeded() {
        let config = RetryConfig(initialDelay: 0.01, multiplier: 1.1, maxAttempts: 2)
        let scheduler = RetryScheduler(config: config)
        let expectation = self.expectation(description: "Should fail after max attempts")

        var attemptCount = 0

        scheduler.execute(attempt: 0) { () -> RetryResult<String> in
            attemptCount += 1
            return .retry(NSError(domain: "test", code: attemptCount))
        } completion: { result in
            if case .failure(let error as RetryError) = result {
                if case .maxAttemptsExceeded(let attempts, _) = error {
                    XCTAssertEqual(attempts, 2, "Should report max attempts")
                    XCTAssert(attemptCount > 1, "Should have retried at least once")
                    expectation.fulfill()
                }
            }
        }

        wait(for: [expectation], timeout: 2.0)
    }

    func testRetrySchedulerEventualSuccess() {
        let config = RetryConfig(initialDelay: 0.01, multiplier: 1.1, maxAttempts: 5)
        let scheduler = RetryScheduler(config: config)
        let expectation = self.expectation(description: "Should succeed after retries")

        var attemptCount = 0

        scheduler.execute(attempt: 0) { () -> RetryResult<String> in
            attemptCount += 1
            if attemptCount < 3 {
                return .retry(NSError(domain: "test", code: attemptCount))
            }
            return .success("success after \(attemptCount) attempts")
        } completion: { result in
            if case .success(let value) = result {
                XCTAssertEqual(attemptCount, 3, "Should succeed on third attempt")
                XCTAssertEqual(value, "success after 3 attempts")
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - RetryError Tests

    func testRetryErrorDescription() {
        let error1 = RetryError.maxAttemptsExceeded(5)
        XCTAssertTrue(error1.localizedDescription.contains("5"))

        let innerError = NSError(domain: "test", code: 123, userInfo: [NSLocalizedDescriptionKey: "inner error"])
        let error2 = RetryError.maxAttemptsExceeded(10, lastError: innerError)
        XCTAssertTrue(error2.localizedDescription.contains("10"))
        XCTAssertTrue(error2.localizedDescription.contains("inner error"))
    }
}
