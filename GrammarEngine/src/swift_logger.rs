// Swift Logger Bridge - Custom tracing Layer for forwarding logs to Swift
//
// This module provides a custom `tracing` Layer that forwards all log events
// to Swift via an FFI callback, enabling unified logging across Rust and Swift.

use std::fmt::Write as FmtWrite;
use std::sync::atomic::{AtomicPtr, Ordering};
use tracing::{Event, Level, Subscriber};
use tracing_subscriber::layer::Context;
use tracing_subscriber::Layer;

/// FFI callback type for forwarding logs to Swift
/// Parameters: level (0=ERROR, 1=WARN, 2=INFO, 3=DEBUG, 4=TRACE), message (null-terminated C string)
pub type SwiftLogCallback = extern "C" fn(level: i32, message: *const std::ffi::c_char);

/// Global callback pointer - set by Swift at initialization
static SWIFT_LOG_CALLBACK: AtomicPtr<()> = AtomicPtr::new(std::ptr::null_mut());

/// Register the Swift log callback
///
/// # Safety
/// This function must be called with a valid function pointer from Swift.
/// The callback must remain valid for the lifetime of the application.
pub fn register_swift_callback(callback: SwiftLogCallback) {
    SWIFT_LOG_CALLBACK.store(callback as *mut (), Ordering::SeqCst);
}

/// Check if a Swift callback is registered
pub fn has_swift_callback() -> bool {
    !SWIFT_LOG_CALLBACK.load(Ordering::SeqCst).is_null()
}

/// Custom tracing Layer that forwards logs to Swift
pub struct SwiftLoggerLayer {
    /// Minimum log level to forward
    min_level: Level,
}

impl SwiftLoggerLayer {
    /// Create a new Swift logger layer
    pub fn new(min_level: Level) -> Self {
        Self { min_level }
    }

    /// Convert tracing Level to integer for FFI
    fn level_to_int(level: &Level) -> i32 {
        match *level {
            Level::ERROR => 0,
            Level::WARN => 1,
            Level::INFO => 2,
            Level::DEBUG => 3,
            Level::TRACE => 4,
        }
    }

    /// Send a log message to Swift
    fn send_to_swift(level: i32, message: &str) {
        let callback_ptr = SWIFT_LOG_CALLBACK.load(Ordering::SeqCst);
        if callback_ptr.is_null() {
            return;
        }

        // Convert to C string - truncate if needed to avoid allocation issues
        let truncated = if message.len() > 4096 {
            format!(
                "{}... [truncated]",
                &message[..message.floor_char_boundary(4000)]
            )
        } else {
            message.to_string()
        };

        if let Ok(c_str) = std::ffi::CString::new(truncated) {
            let callback: SwiftLogCallback = unsafe { std::mem::transmute(callback_ptr) };
            callback(level, c_str.as_ptr());
        }
    }
}

impl<S> Layer<S> for SwiftLoggerLayer
where
    S: Subscriber,
{
    fn on_event(&self, event: &Event<'_>, _ctx: Context<'_, S>) {
        let metadata = event.metadata();
        let level = metadata.level();

        // Filter by minimum level
        if *level > self.min_level {
            return;
        }

        // Build the log message
        let mut message = String::with_capacity(256);

        // Add target (module path)
        let target = metadata.target();
        // Simplify target: remove grammar_engine:: prefix
        let target = target.strip_prefix("grammar_engine::").unwrap_or(target);
        write!(message, "[{}] ", target).ok();

        // Add the actual log message
        let mut visitor = MessageVisitor::new(&mut message);
        event.record(&mut visitor);

        // Send to Swift
        Self::send_to_swift(Self::level_to_int(level), &message);
    }
}

/// Visitor to extract the message field from log events
struct MessageVisitor<'a> {
    message: &'a mut String,
    has_message: bool,
}

impl<'a> MessageVisitor<'a> {
    fn new(message: &'a mut String) -> Self {
        Self {
            message,
            has_message: false,
        }
    }
}

impl<'a> tracing::field::Visit for MessageVisitor<'a> {
    fn record_debug(&mut self, field: &tracing::field::Field, value: &dyn std::fmt::Debug) {
        if field.name() == "message" {
            write!(self.message, "{:?}", value).ok();
            self.has_message = true;
        } else if !self.has_message {
            // Include other fields if no message field yet
            if !self.message.is_empty() && !self.message.ends_with(' ') {
                self.message.push(' ');
            }
            write!(self.message, "{}={:?}", field.name(), value).ok();
        }
    }

    fn record_str(&mut self, field: &tracing::field::Field, value: &str) {
        if field.name() == "message" {
            self.message.push_str(value);
            self.has_message = true;
        } else if !self.has_message {
            if !self.message.is_empty() && !self.message.ends_with(' ') {
                self.message.push(' ');
            }
            write!(self.message, "{}={}", field.name(), value).ok();
        }
    }

    fn record_i64(&mut self, field: &tracing::field::Field, value: i64) {
        if !self.message.is_empty() && !self.message.ends_with(' ') {
            self.message.push(' ');
        }
        write!(self.message, "{}={}", field.name(), value).ok();
    }

    fn record_u64(&mut self, field: &tracing::field::Field, value: u64) {
        if !self.message.is_empty() && !self.message.ends_with(' ') {
            self.message.push(' ');
        }
        write!(self.message, "{}={}", field.name(), value).ok();
    }

    fn record_bool(&mut self, field: &tracing::field::Field, value: bool) {
        if !self.message.is_empty() && !self.message.ends_with(' ') {
            self.message.push(' ');
        }
        write!(self.message, "{}={}", field.name(), value).ok();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_callback_receives_bounded_unicode_messages() {
        // Registration lasts for the process lifetime. A child keeps this callback
        // isolated from other tests without changing the production registration API.
        const CHILD: &str = "TEXTWARDEN_TEST_LOG_CALLBACK_CHILD";
        if std::env::var_os(CHILD).is_none() {
            let output = std::process::Command::new(std::env::current_exe().unwrap())
                .args([
                    "--exact",
                    "swift_logger::tests::test_callback_receives_bounded_unicode_messages",
                    "--nocapture",
                ])
                .env(CHILD, "1")
                .output()
                .unwrap();
            assert!(
                output.status.success(),
                "{}\n{}",
                String::from_utf8_lossy(&output.stdout),
                String::from_utf8_lossy(&output.stderr)
            );
            return;
        }

        static RECEIVED: std::sync::Mutex<Vec<(i32, Vec<u8>)>> = std::sync::Mutex::new(Vec::new());
        extern "C" fn receive(level: i32, message: *const std::ffi::c_char) {
            // send_to_swift keeps its CString alive throughout the callback.
            let bytes = unsafe { std::ffi::CStr::from_ptr(message) }
                .to_bytes()
                .to_vec();
            if let Ok(mut received) = RECEIVED.lock() {
                received.push((level, bytes));
            }
        }

        assert!(!has_swift_callback());
        register_swift_callback(receive);
        register_swift_callback(receive);
        assert!(has_swift_callback());

        let mut cases = vec![
            (String::new(), String::new()),
            (
                "Hello 日本語 مرحبا 👩🏽‍💻".into(),
                "Hello 日本語 مرحبا 👩🏽‍💻".into(),
            ),
            ("a".repeat(4096), "a".repeat(4096)),
            (
                "a".repeat(4097),
                format!("{}... [truncated]", "a".repeat(4000)),
            ),
            ("😀".repeat(1024), "😀".repeat(1024)),
            (
                "😀".repeat(1025),
                format!("{}... [truncated]", "😀".repeat(1000)),
            ),
        ];
        for (prefix_length, suffix) in
            [(3999, "😀"), (3998, "界"), (3999, "\u{0301}"), (3999, "👩🏽‍💻")]
        {
            let prefix = "a".repeat(prefix_length);
            cases.push((
                format!("{prefix}{}", suffix.repeat(100)),
                format!("{prefix}... [truncated]"),
            ));
        }
        for (index, (input, _)) in cases.iter().enumerate() {
            SwiftLoggerLayer::send_to_swift((index % 5) as i32, input);
        }
        // Interior NULs cannot cross the C-string boundary; retain the existing drop behavior.
        SwiftLoggerLayer::send_to_swift(2, "before\0after");

        let received = RECEIVED.lock().unwrap();
        assert_eq!(received.len(), cases.len());
        for (index, ((level, bytes), (_, expected))) in received.iter().zip(&cases).enumerate() {
            assert_eq!(*level, (index % 5) as i32);
            assert_eq!(std::str::from_utf8(bytes).unwrap(), expected);
            assert!(bytes.len() <= 4096);
        }
    }

    #[test]
    fn test_level_to_int() {
        assert_eq!(SwiftLoggerLayer::level_to_int(&Level::ERROR), 0);
        assert_eq!(SwiftLoggerLayer::level_to_int(&Level::WARN), 1);
        assert_eq!(SwiftLoggerLayer::level_to_int(&Level::INFO), 2);
        assert_eq!(SwiftLoggerLayer::level_to_int(&Level::DEBUG), 3);
        assert_eq!(SwiftLoggerLayer::level_to_int(&Level::TRACE), 4);
    }

    #[test]
    fn test_no_callback_registered() {
        // Should not panic even without callback
        SwiftLoggerLayer::send_to_swift(2, "Test message");
    }
}
