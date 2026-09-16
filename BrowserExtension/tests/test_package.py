import base64
import hashlib
import importlib.util
import json
import plistlib
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

spec = importlib.util.spec_from_file_location('extension', Path(__file__).resolve().parents[2] / 'Scripts/browser-extension.py')
extension = importlib.util.module_from_spec(spec)
spec.loader.exec_module(extension)


class PackageTests(unittest.TestCase):
    def test_versions_and_exact_runtime_package(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            app = root / 'TextWarden.app'
            plist = app / 'Contents/Info.plist'
            plist.parent.mkdir(parents=True)
            def write(name, build):
                plist.write_bytes(plistlib.dumps({'CFBundleShortVersionString': name, 'CFBundleVersion': build}))
            for name, build, numeric in [('0.5.2', '38', '0.5.2.38'), ('0.6.0-beta.1', '39', '0.6.0.39'), ('0.6.0', '40', '0.6.0.40')]:
                write(name, build)
                self.assertEqual(extension.version(plist), (numeric, name))
            for name, build in [('0.6.0', '65536'), ('0.6.0', '-1'), ('0.06.0', '40'), ('bad', '40')]:
                write(name, build)
                with self.assertRaises(ValueError): extension.version(plist)
            write('0.6.0', '40')
            destination = app / 'Contents/Resources/BrowserExtension'
            shared = root / 'shared-source'
            extension.prepare(plist, shared)
            source_manifest = json.loads((shared / 'manifest.json').read_text())
            self.assertEqual(source_manifest['version'], '0.6.0.40')
            self.assertIn('browser_specific_settings', source_manifest)
            self.assertIn('scripts', source_manifest['background'])
            self.assertIn('service_worker', source_manifest['background'])
            extension.prepare(plist, destination, 'chromium')
            chromium = json.loads((destination / 'manifest.json').read_text())
            self.assertEqual(chromium['background'], {'service_worker': 'background.js'})
            self.assertNotIn('browser_specific_settings', chromium)
            firefox_destination = destination.with_name('BrowserExtension-Firefox')
            extension.prepare(plist, firefox_destination, 'firefox')
            firefox = json.loads((firefox_destination / 'manifest.json').read_text())
            self.assertEqual(firefox['background'], {'scripts': ['background.js']})
            self.assertNotIn('key', firefox)
            self.assertEqual(firefox['browser_specific_settings']['gecko']['id'], 'browser@textwarden.io')
            (destination / 'private-test.txt').write_text('Excluded fixture')
            archive = root / 'extension.zip'
            extension.package(app, archive)
            extension.verify(archive, '0.6.0', '0.6.0.40')
            with zipfile.ZipFile(archive) as zipped:
                self.assertEqual(set(zipped.namelist()), set(extension.FILES))
                manifest = json.loads(zipped.read('manifest.json'))
                digest = hashlib.sha256(base64.b64decode(manifest['key'], validate=True)).hexdigest()[:32]
                identifier = ''.join(chr(97 + int(n, 16)) for n in digest)
                self.assertEqual(identifier, 'cjihinlobjameeehbonjbheadlfmfnkk')
                self.assertEqual(manifest['background'], {'service_worker': 'background.js'})
                self.assertNotIn('browser_specific_settings', manifest)
            with self.assertRaises(ValueError): extension.verify(archive, '0.5.2', '0.5.2.38')
            extension.package(app, archive, 'firefox')
            extension.verify(archive, '0.6.0', '0.6.0.40', 'firefox')
            with zipfile.ZipFile(archive) as zipped:
                self.assertEqual(set(zipped.namelist()), set(extension.FILES))
                manifest = json.loads(zipped.read('manifest.json'))
                for key in ('key', 'minimum_chrome_version', 'version_name'):
                    self.assertNotIn(key, manifest)
                self.assertEqual(manifest['background'], {'scripts': ['background.js']})
            with self.assertRaises(ValueError): extension.verify(archive, '0.6.0', '0.6.0.40')
            write('0.6.1', '41')
            with self.assertRaises(ValueError): extension.package(app, archive)

    @unittest.skipUnless(sys.platform == 'darwin', 'Requires macOS codesign')
    def test_release_export_preserves_safari_sandbox(self):
        project = Path(__file__).resolve().parents[2]
        source = (project / 'Scripts/release.sh').read_text()
        export_function = 'export_app() {' + source.split('export_app() {', 1)[1].split('\n}\n', 1)[0] + '\n}'
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            binary = root / 'fixture'
            subprocess.run(['cc', '-x', 'c', '-o', str(binary), '-'], input=b'int main(void) { return 0; }', check=True, capture_output=True)
            archive = root / 'archive'
            app = archive / 'Products/Applications/TextWarden.app'
            safari = app / 'Contents/PlugIns/TextWardenBrowserExtension.appex'
            for bundle, identifier in [(safari, 'io.textwarden.fixture.extension'), (app, 'io.textwarden.fixture')]:
                (bundle / 'Contents/MacOS').mkdir(parents=True, exist_ok=True)
                shutil.copyfile(binary, bundle / 'Contents/MacOS/fixture')
                (bundle / 'Contents/Info.plist').write_bytes(plistlib.dumps({
                    'CFBundleIdentifier': identifier, 'CFBundleExecutable': 'fixture',
                    'CFBundlePackageType': 'XPC!' if bundle == safari else 'APPL',
                }))
                entitlements = project / ('SafariExtension/TextWardenBrowserExtension.entitlements' if bundle == safari else 'TextWarden.entitlements')
                if bundle == safari:
                    development = plistlib.loads(entitlements.read_bytes())
                    development['com.apple.security.get-task-allow'] = True
                    entitlements = root / 'development.plist'
                    entitlements.write_bytes(plistlib.dumps(development))
                subprocess.run(['codesign', '--force', '--sign', '-', '--entitlements', str(entitlements), str(bundle)], check=True, capture_output=True)
            # Exercise the real export function; ad-hoc signatures cannot use a timestamp server.
            script = 'codesign() { local args=(); for arg in "$@"; do [[ "$arg" == --timestamp ]] || args+=("$arg"); done; /usr/bin/codesign "${args[@]}"; }\n'
            script += export_function + '\nexport_app "$ARCHIVE"'
            environment = dict(os.environ, PROJECT_ROOT=str(project), RELEASE_DIR=str(root / 'release'),
                APP_NAME='TextWarden', ENTITLEMENTS='TextWarden.entitlements', DEVELOPER_ID='-', ARCHIVE=str(archive))
            subprocess.run(['bash', '-e', '-c', script], env=environment, check=True, capture_output=True)
            exported = root / 'release/export/TextWarden.app'
            def entitlements(bundle):
                result = subprocess.run(['codesign', '-d', '--entitlements', '-', '--xml', str(bundle)], check=True, capture_output=True)
                return plistlib.loads(result.stdout)
            child = entitlements(exported / 'Contents/PlugIns/TextWardenBrowserExtension.appex')
            self.assertTrue(child.get('com.apple.security.app-sandbox'), 'Release export must preserve the Safari sandbox')
            self.assertEqual(child['com.apple.security.application-groups'], ['KSW8RTNTKJ.io.textwarden.browser'])
            self.assertNotIn('com.apple.security.files.user-selected.read-write', child)
            self.assertNotIn('com.apple.security.get-task-allow', child)
            self.assertEqual(entitlements(exported), plistlib.loads((project / 'TextWarden.entitlements').read_bytes()))
            failed_signing = 'codesign() { return 99; }\n' + export_function + '\nif result=$(export_app "$ARCHIVE"); then exit 1; fi'
            subprocess.run(['bash', '-c', failed_signing], env=environment, check=True, capture_output=True)

    def test_safari_shares_versions_and_packages_only_runtime_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            plist = root / 'app.plist'
            plist.write_bytes(plistlib.dumps({'CFBundleShortVersionString': '0.6.0', 'CFBundleVersion': '40'}))
            extension.prepare_safari(plist, root / 'resources', root / 'SafariInfo.plist')
            manifest = json.loads((root / 'resources/manifest.json').read_text())
            info = plistlib.loads((root / 'SafariInfo.plist').read_bytes())
            self.assertEqual(set(p.name for p in (root / 'resources').iterdir()), set(extension.FILES))
            self.assertEqual(manifest['version'], '0.6.0.40')
            self.assertEqual(info['CFBundleShortVersionString'], '0.6.0')
            self.assertEqual(info['CFBundleVersion'], '40')
            self.assertEqual(info['LSMinimumSystemVersion'], '14.0')
            self.assertEqual(manifest['permissions'], ['activeTab', 'scripting', 'nativeMessaging'])
            self.assertNotIn('key', manifest)
            self.assertNotIn('browser_specific_settings', manifest)
            self.assertEqual(manifest['background'], {'scripts': ['background.js'], 'persistent': False})


if __name__ == '__main__': unittest.main()
