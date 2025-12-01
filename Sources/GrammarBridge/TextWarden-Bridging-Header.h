//
//  TextWarden-Bridging-Header.h
//  TextWarden
//
//  Bridging header for Rust FFI integration via swift-bridge
//

#ifndef TextWarden_Bridging_Header_h
#define TextWarden_Bridging_Header_h

// Import swift-bridge generated headers from GrammarEngine/generated
#import "../../GrammarEngine/generated/SwiftBridgeCore.h"
#import "../../GrammarEngine/generated/grammar-engine/grammar-engine.h"

// MARK: - Unified Logging Callback (Rust → Swift)

/// Callback type for receiving log messages from Rust
/// @param level Log level: 0=ERROR, 1=WARN, 2=INFO, 3=DEBUG, 4=TRACE
/// @param message Null-terminated C string containing the log message
typedef void (*RustLogCallback)(int32_t level, const char* message);

/// Register a callback function to receive log messages from Rust
/// This must be called BEFORE initialize_logging() for the callback
/// to capture initialization logs
/// @param callback The Swift callback function to receive logs
void register_rust_log_callback(RustLogCallback callback);

#endif /* TextWarden_Bridging_Header_h */
