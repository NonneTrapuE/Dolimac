import Foundation

/// État global de l'application, persisté dans UserDefaults.
class AppState: ObservableObject {
    static let shared = AppState()

    private let defaults = UserDefaults.standard

    // MARK: - Clés UserDefaults
    private enum Key {
        static let installed     = "dolibarr.installed"
        static let dolibarrPath  = "dolibarr.path"
        static let phpVersion    = "dolibarr.phpVersion"
        static let dbName        = "dolibarr.dbName"
        static let dbUser        = "dolibarr.dbUser"
        static let dbPassword    = "dolibarr.dbPassword"
        static let dolibarrPort  = "dolibarr.port"
        static let backupDir     = "dolibarr.backupDir"
    }

    // MARK: - Propriétés publiées

    @Published var isInstalled: Bool {
        didSet { defaults.set(isInstalled, forKey: Key.installed) }
    }

    @Published var dolibarrPath: String {
        didSet { defaults.set(dolibarrPath, forKey: Key.dolibarrPath) }
    }

    @Published var phpVersion: String {
        didSet { defaults.set(phpVersion, forKey: Key.phpVersion) }
    }

    @Published var dbName: String {
        didSet { defaults.set(dbName, forKey: Key.dbName) }
    }

    @Published var dbUser: String {
        didSet { defaults.set(dbUser, forKey: Key.dbUser) }
    }

    @Published var dbPassword: String {
        didSet { defaults.set(dbPassword, forKey: Key.dbPassword) }
    }

    @Published var dolibarrPort: Int {
        didSet { defaults.set(dolibarrPort, forKey: Key.dolibarrPort) }
    }

    @Published var backupDir: String {
        didSet { defaults.set(backupDir, forKey: Key.backupDir) }
    }

    // MARK: - Init (lecture des valeurs sauvegardées)

    private init() {
        isInstalled    = defaults.bool(forKey: Key.installed)
        dolibarrPath   = defaults.string(forKey: Key.dolibarrPath)  ?? "\(NSHomeDirectory())/Dolibarr"
        phpVersion     = defaults.string(forKey: Key.phpVersion)    ?? "8.2"
        dbName         = defaults.string(forKey: Key.dbName)        ?? "dolibarr"
        dbUser         = defaults.string(forKey: Key.dbUser)        ?? "dolibarr"
        dbPassword     = defaults.string(forKey: Key.dbPassword)    ?? ""
        dolibarrPort   = defaults.integer(forKey: Key.dolibarrPort) == 0
                            ? 8080
                            : defaults.integer(forKey: Key.dolibarrPort)
        backupDir      = defaults.string(forKey: Key.backupDir)
                            ?? "\(NSHomeDirectory())/Documents/DolibarrBackups"
    }

    // MARK: - Helpers

    var dolibarrURL: URL {
        URL(string: "http://localhost:\(dolibarrPort)")!
    }

    /// Chemin vers le répertoire de configuration Dolibarr
    var doliconfPath: String { "\(dolibarrPath)/htdocs/conf/conf.php" }

    /// Réinitialise complètement (désinstallation logique)
    func reset() {
        isInstalled  = false
        dbPassword   = ""
        defaults.removeObject(forKey: Key.installed)
    }
}
