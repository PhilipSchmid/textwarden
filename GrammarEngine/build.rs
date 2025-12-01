// Build script to configure swift-bridge code generation
use std::path::PathBuf;

fn main() {
    let out_dir = PathBuf::from("./generated");

    // Ensure cargo reruns build script when bridge module changes
    let bridges = vec!["src/bridge.rs"];
    for path in &bridges {
        println!("cargo:rerun-if-changed={path}");
    }

    // Configure swift-bridge to generate Swift and C header files
    swift_bridge_build::parse_bridges(bridges)
        .write_all_concatenated(out_dir, env!("CARGO_PKG_NAME"));
}
