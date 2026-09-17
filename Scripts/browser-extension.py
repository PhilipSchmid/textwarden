#!/usr/bin/env python3
"""Build browser extension packages using the Mac app's version."""
import argparse
import json
import plistlib
import re
import shutil
import zipfile
from pathlib import Path

FILES = ('manifest.json', 'background.js', 'content.js', 'popup.html', 'popup.css', 'popup.js', 'icon.png',
         'toolbar.png', 'toolbar-16.png', 'toolbar-dark.png', 'toolbar-dark-16.png',
         'toolbar-paused.png', 'toolbar-paused-16.png', 'toolbar-paused-dark.png', 'toolbar-paused-dark-16.png')
ROOT = Path(__file__).resolve().parent.parent


def version(plist):
    info = plistlib.loads(Path(plist).read_bytes())
    name, build = info['CFBundleShortVersionString'], str(info['CFBundleVersion'])
    match = re.fullmatch(r'(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-(?:alpha|beta|rc)\.[1-9]\d*)?', name)
    if not match or not re.fullmatch(r'0|[1-9]\d*', build):
        raise ValueError('Invalid app version or build number')
    parts = [int(n) for n in (*match.groups(), build)]
    if max(parts) > 65535 or not any(parts):
        raise ValueError('Chrome version components must be 0–65535 and not all zero')
    return '.'.join(map(str, parts)), name


def prepare(plist, destination, browser='shared'):
    destination = Path(destination)
    destination.mkdir(parents=True, exist_ok=True)
    for file in FILES:
        source = ROOT / 'BrowserExtension' / file
        if source.resolve() != (destination / file).resolve():
            shutil.copyfile(source, destination / file)
    manifest = destination / 'manifest.json'
    data = json.loads(manifest.read_text())
    data['version'], data['version_name'] = version(plist)
    if browser == 'firefox':
        for key in ('key', 'minimum_chrome_version', 'version_name'):
            data.pop(key, None)
        data['background'] = {'scripts': ['background.js']}
    elif browser == 'chromium':
        data.pop('browser_specific_settings', None)
        data['background'] = {'service_worker': 'background.js'}
    elif browser != 'shared':
        raise ValueError('Unsupported browser package')
    manifest.write_text(json.dumps(data, indent=2) + '\n')


def prepare_safari(plist, destination, info_path):
    prepare(plist, destination)
    manifest = Path(destination) / 'manifest.json'
    data = json.loads(manifest.read_text())
    data.pop('key', None)
    data.pop('minimum_chrome_version', None)
    data.pop('browser_specific_settings', None)
    data['action']['default_icon'] = {'16': 'toolbar-dark-16.png', '32': 'toolbar-dark.png'}
    data['background'] = {'scripts': ['background.js'], 'persistent': False}
    manifest.write_text(json.dumps(data, indent=2) + '\n')
    app = plistlib.loads(Path(plist).read_bytes())
    info = {
        'CFBundleIdentifier': 'io.textwarden.TextWarden.BrowserExtension',
        'CFBundleExecutable': 'TextWardenBrowserExtension',
        'CFBundleName': 'TextWarden Browser Extension',
        'CFBundleDisplayName': 'TextWarden Browser Extension (Preview)',
        'CFBundlePackageType': 'XPC!',
        'CFBundleVersion': str(app['CFBundleVersion']),
        'CFBundleShortVersionString': app['CFBundleShortVersionString'],
        'LSMinimumSystemVersion': '14.0',
        'NSExtension': {
            'NSExtensionPointIdentifier': 'com.apple.Safari.web-extension',
            'NSExtensionPrincipalClass': 'TextWardenBrowserExtension.SafariWebExtensionHandler',
        },
    }
    Path(info_path).write_bytes(plistlib.dumps(info))


def package(app, output, browser='chromium'):
    app, output = Path(app), Path(output)
    expected = version(app / 'Contents/Info.plist')
    if browser not in ('chromium', 'firefox'):
        raise ValueError('Unsupported browser package')
    extension = app / 'Contents/Resources' / ('BrowserExtension-Firefox' if browser == 'firefox' else 'BrowserExtension')
    data = json.loads((extension / 'manifest.json').read_text())
    if data.get('version') != expected[0] or (browser == 'chromium' and data.get('version_name') != expected[1]):
        raise ValueError('Bundled extension does not match the app')
    with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as archive:
        for file in FILES:
            if file == 'manifest.json':
                archive.writestr(file, json.dumps(data, indent=2) + '\n')
            else:
                archive.write(extension / file, file)


def verify(archive, expected_version, expected_numeric, browser='chromium'):
    with zipfile.ZipFile(archive) as zipped:
        if sorted(zipped.namelist()) != sorted(FILES):
            raise ValueError('Unexpected extension package contents')
        data = json.loads(zipped.read('manifest.json'))
        if data.get('version') != expected_numeric or (browser == 'chromium' and data.get('version_name') != expected_version):
            raise ValueError('Extension package does not match the release tag')
        if browser == 'firefox':
            if data.get('browser_specific_settings', {}).get('gecko', {}).get('id') != 'browser@textwarden.io' or data.get('background') != {'scripts': ['background.js']}:
                raise ValueError('Invalid Firefox package')
        elif browser == 'chromium':
            if data.get('background') != {'service_worker': 'background.js'} or not data.get('key'):
                raise ValueError('Invalid Chromium package')
        else:
            raise ValueError('Unsupported browser package')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    build = commands.add_parser('prepare')
    build.add_argument('plist'); build.add_argument('destination')
    build.add_argument('--browser', choices=['shared', 'chromium', 'firefox'], default='shared')
    safari = commands.add_parser('prepare-safari')
    safari.add_argument('plist'); safari.add_argument('destination'); safari.add_argument('info')
    pack = commands.add_parser('package')
    pack.add_argument('app'); pack.add_argument('output')
    pack.add_argument('--browser', choices=['chromium', 'firefox'], default='chromium')
    check = commands.add_parser('verify')
    check.add_argument('archive'); check.add_argument('version'); check.add_argument('numeric')
    check.add_argument('--browser', choices=['chromium', 'firefox'], default='chromium')
    args = parser.parse_args()
    if args.command == 'prepare': prepare(args.plist, args.destination, args.browser)
    elif args.command == 'prepare-safari': prepare_safari(args.plist, args.destination, args.info)
    elif args.command == 'package': package(args.app, args.output, args.browser)
    else: verify(args.archive, args.version, args.numeric, args.browser)
