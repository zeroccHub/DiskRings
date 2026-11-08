// Linux type-check shim for UniformTypeIdentifiers (macOS 11+). APPROXIMATION of the SDK.
@_exported import Foundation
public struct UTType: Hashable, Sendable {
    public init?(filenameExtension: String) {}
    public init?(_ identifier: String) {}
    public init?(filenameExtension: String, conformingTo supertype: UTType) {}
    public var identifier: String { "" }
    public var preferredFilenameExtension: String? { nil }
    public var localizedDescription: String? { nil }
    @discardableResult public func conforms(to type: UTType) -> Bool { false }
    public static let item = UTType("public.item")!, content = UTType("public.content")!, data = UTType("public.data")!,
        folder = UTType("public.folder")!, directory = UTType("public.directory")!, volume = UTType("public.volume")!,
        application = UTType("com.apple.application")!, applicationBundle = UTType("com.apple.application-bundle")!,
        package = UTType("com.apple.package")!, image = UTType("public.image")!, movie = UTType("public.movie")!,
        audio = UTType("public.audio")!, text = UTType("public.text")!, archive = UTType("public.archive")!,
        diskImage = UTType("public.disk-image")!, sourceCode = UTType("public.source-code")!, pdf = UTType("com.adobe.pdf")!,
        aliasFile = UTType("com.apple.alias-file")!, symbolicLink = UTType("public.symlink")!
}
