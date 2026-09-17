import Foundation

/// Where `Localizable.strings` lives. A packaged `.app` carries the `.lproj`
/// folders in `Contents/Resources`; running straight from SwiftPM they sit in
/// the module bundle instead.
private let stringsBundle: Bundle = {
    if Bundle.main.url(forResource: "en", withExtension: "lproj") != nil { return .main }
    return .module
}()

/// SwiftUI's automatic `LocalizedStringKey` lookup only searches `Bundle.main`,
/// so all strings go through here.
func L(_ key: String) -> String {
    stringsBundle.localizedString(forKey: key, value: key, table: nil)
}

func L(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: stringsBundle.localizedString(forKey: key, value: key, table: nil),
           arguments: arguments)
}
