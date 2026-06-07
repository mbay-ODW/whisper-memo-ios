import Foundation
import Combine

final class AppSettings: ObservableObject {
    @Published var serverURL: String {
        didSet { UserDefaults.standard.set(serverURL, forKey: "serverURL") }
    }
    @Published var oidcIssuer: String {
        didSet { UserDefaults.standard.set(oidcIssuer, forKey: "oidcIssuer") }
    }
    @Published var oidcClientId: String {
        didSet { UserDefaults.standard.set(oidcClientId, forKey: "oidcClientId") }
    }
    @Published var defaultModel: String {
        didSet { UserDefaults.standard.set(defaultModel, forKey: "defaultModel") }
    }
    @Published var availableModels: [String] {
        didSet { UserDefaults.standard.set(availableModels, forKey: "availableModels") }
    }
    @Published var defaultPrompt: String {
        didSet { UserDefaults.standard.set(defaultPrompt, forKey: "defaultPrompt") }
    }

    static let defaultPrompt = "Elektroinstallation Holzständerbau: Gefach, Ständer, Fertigwand, Fertigfußboden FFB, Laibung, NYM 3x1,5 mm², 5x1,5, 3x2,5, 4x1,5, Rollladen, Schalterdose, Steckdose, Spiegelschrank, Heizkreisverteiler, Stellantrieb, Pendellüfter, Empore, HWR, Zentimeter, Meter"

    init() {
        let ud = UserDefaults.standard
        serverURL      = ud.string(forKey: "serverURL")      ?? ""
        oidcIssuer     = ud.string(forKey: "oidcIssuer")     ?? ""
        oidcClientId   = ud.string(forKey: "oidcClientId")   ?? "whisper-ios"
        defaultModel   = ud.string(forKey: "defaultModel")   ?? "large-v3"
        availableModels = (ud.array(forKey: "availableModels") as? [String]) ?? ["large-v3", "medium", "small", "base"]
        defaultPrompt  = ud.string(forKey: "defaultPrompt")  ?? Self.defaultPrompt
    }
}
