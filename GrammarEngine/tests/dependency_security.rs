use harper_core::weirpack::{Error, Weirpack, WeirpackManifest};

#[test]
fn weirpack_rejects_conflicting_zip_headers() {
    let manifest = WeirpackManifest::from_reader(
        br#"{"author":"Test","version":"1.0","description":"Security regression","license":"MIT"}"#
            .as_slice(),
    )
    .expect("valid manifest");
    let mut pack = Weirpack::new(manifest);
    pack.add_rule("ExampleRule", "expr main test");
    let mut bytes = pack.to_bytes().expect("serialize archive");
    let parsed = Weirpack::from_bytes(&bytes).expect("read valid archive");
    assert_eq!(parsed.rules.get("ExampleRule").unwrap(), "expr main test");

    assert_eq!(&bytes[..4], b"PK\x03\x04");
    assert_eq!(&bytes[30..43], b"manifest.json");
    // Change only the local header; the central directory still names manifest.json.
    bytes[30..43].copy_from_slice(b"conflict.json");
    let result = Weirpack::from_bytes(&bytes);
    assert!(matches!(&result, Err(Error::Zip(_))), "{result:?}");
}
