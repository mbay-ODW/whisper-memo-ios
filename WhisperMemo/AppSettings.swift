import Foundation
import Combine

final class AppSettings: ObservableObject {
    @Published var serverURL: String
    @Published var oidcIssuer: String
    @Published var oidcClientId: String
    @Published var defaultModel: String
    @Published var availableModels: [String]
    @Published var defaultPrompt: String

    static let defaultPrompt = "Elektroinstallation Holzständerbau: Gefach, Ständer, Fertigwand, Fertigfußboden FFB, Laibung, NYM 3x1,5 mm², 5x1,5, 3x2,5, 4x1,5, Rollladen, Schalterdose, Steckdose, Spiegelschrank, Heizkreisverteiler, Stellantrieb, Pendellüfter, Empore, HWR, Zentimeter, Meter"

    private var cancellables = Set<AnyCancellable>()
    private let ud = UserDefaults.standard

    init() {
        serverURL       = ud.string(forKey: "serverURL")      ?? ""
        oidcIssuer      = ud.string(forKey: "oidcIssuer")     ?? ""
        oidcClientId    = ud.string(forKey: "oidcClientId")   ?? "whisper-ios"
        defaultModel    = ud.string(forKey: "defaultModel")   ?? "large-v3"
        availableModels = (ud.array(forKey: "availableModels") as? [String]) ?? ["large-v3", "medium", "small", "base"]
        defaultPrompt   = ud.string(forKey: "defaultPrompt")  ?? Self.defaultPrompt

        $serverURL      .dropFirst().sink { [weak self] v in self?.ud.set(v, forKey: "serverURL") }.store(in: &cancellables)
        $oidcIssuer     .dropFirst().sink { [weak self] v in self?.ud.set(v, forKey: "oidcIssuer") }.store(in: &cancellables)
        $oidcClientId   .dropFirst().sink { [weak self] v in self?.ud.set(v, forKey: "oidcClientId") }.store(in: &cancellables)
        $defaultModel   .dropFirst().sink { [weak self] v in self?.ud.set(v, forKey: "defaultModel") }.store(in: &cancellables)
        $availableModels.dropFirst().sink { [weak self] v in self?.ud.set(v, forKey: "availableModels") }.store(in: &cancellables)
        $defaultPrompt  .dropFirst().sink { [weak self] v in self?.ud.set(v, forKey: "defaultPrompt") }.store(in: &cancellables)
    }
}
