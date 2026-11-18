import Foundation

// The system installer handles replacement/permissions; inspect its manifest first
// so a correctly hashed but wrong-version/wrong-application package is not opened.
enum PackageValidator {
    static func validate(_ package: URL, version: String) throws {
        let directory = package.deletingLastPathComponent().appendingPathComponent("manifest-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/pkgutil")
        process.arguments = ["--expand", package.path, directory.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              matches(try Data(contentsOf: directory.appendingPathComponent("PackageInfo")), version: version) else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }

    static func matches(_ xml: Data, version: String) -> Bool {
        let delegate = Manifest(version: version)
        let parser = XMLParser(data: xml)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        return parser.parse() && delegate.packageMatches && delegate.applicationMatches && delegate.applicationCount == 1
    }

    private final class Manifest: NSObject, XMLParserDelegate {
        let version: String
        var packageMatches = false
        var applicationMatches = false
        var applicationCount = 0
        init(version: String) { self.version = version }
        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
            if name == "pkg-info" {
                packageMatches = attributes["identifier"] == "com.example.Daylight.installer" && attributes["version"] == version
            } else if name == "bundle", attributes["id"] == "com.example.Daylight", attributes["path"] != nil {
                // pkgbuild repeats bare bundle IDs in bundle-version/upgrade-bundle.
                // Only the payload manifest carries a path and application version.
                applicationCount += 1
                applicationMatches = attributes["CFBundleShortVersionString"] == version &&
                    ["Applications/Daily.app", "./Applications/Daily.app"].contains(attributes["path"] ?? "")
            }
        }
    }
}
