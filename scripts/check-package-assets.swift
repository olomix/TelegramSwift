// Check that every image in the local packages' asset catalogs loads from
// the built app. Generated `NSImage(resource:)` force-unwraps, so a missing
// image crashes the app when the screen using it first appears.
//
// Usage: swift scripts/check-package-assets.swift <path/to/Telegram.app>

import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write("usage: check-package-assets.swift <Telegram.app>\n".data(using: .utf8)!)
    exit(2)
}

let fileManager = FileManager.default
let appResources = URL(fileURLWithPath: arguments[1]).appendingPathComponent("Contents/Resources")
let packagesDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("packages")

func catalogs(in package: URL) -> [URL] {
    let sources = package.appendingPathComponent("Sources")
    guard let walker = fileManager.enumerator(at: sources, includingPropertiesForKeys: nil) else {
        return []
    }
    return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "xcassets" }
}

func imageNames(in catalog: URL) -> [String] {
    guard let walker = fileManager.enumerator(at: catalog, includingPropertiesForKeys: nil) else {
        return []
    }
    return walker.compactMap { $0 as? URL }
        .filter { $0.pathExtension == "imageset" }
        .map { $0.deletingPathExtension().lastPathComponent }
        .sorted()
}

func resourceBundle(for packageName: String) -> Bundle? {
    let names = (try? fileManager.contentsOfDirectory(atPath: appResources.path)) ?? []
    guard let name = names.first(where: { $0.hasPrefix("\(packageName)_") && $0.hasSuffix(".bundle") }) else {
        return nil
    }
    return Bundle(url: appResources.appendingPathComponent(name))
}

var failures: [String] = []
var checked = 0

let packages = (try? fileManager.contentsOfDirectory(at: packagesDir, includingPropertiesForKeys: nil)) ?? []
for package in packages.sorted(by: { $0.path < $1.path }) {
    let names = catalogs(in: package).flatMap(imageNames(in:))
    if names.isEmpty {
        continue
    }
    let packageName = package.lastPathComponent
    guard let bundle = resourceBundle(for: packageName) else {
        failures.append("\(packageName): no resource bundle in \(appResources.path)")
        continue
    }
    if bundle.url(forResource: "Assets", withExtension: "car") == nil {
        failures.append("\(packageName): \(bundle.bundleURL.lastPathComponent) has no compiled Assets.car")
    }
    for name in names {
        checked += 1
        if bundle.image(forResource: name) == nil {
            failures.append("\(packageName): image \(name) does not load")
        }
    }
}

if failures.isEmpty {
    print("OK: \(checked) package images load from \(arguments[1])")
} else {
    failures.forEach { print("FAIL: \($0)") }
    exit(1)
}
