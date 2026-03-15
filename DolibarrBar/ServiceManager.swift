import Foundation
import AppKit

// MARK: - Statut des services

enum ServiceStatus {
    case running, stopped, unknown
}

struct ServicesStatus {
    var php: ServiceStatus = .unknown
    var mariadb: ServiceStatus = .unknown

    var allRunning: Bool { php == .running && mariadb == .running }
    var allStopped: Bool { php == .stopped && mariadb == .stopped }
}

// MARK: - Résultat d'une commande shell

struct ShellResult {
    let output: String
    let exitCode: Int32
    var success: Bool { exitCode == 0 }
}

// MARK: - ServiceManager

class DolibarrServiceManager: ObservableObject {
    static let shared = DolibarrServiceManager()

    @Published var status = ServicesStatus()

    private let state = AppState.shared

    // Chemin Homebrew sur Apple Silicon
    private let brewPrefix = "/opt/homebrew"
    private var brewBin: String { "\(brewPrefix)/bin/brew" }

    // MARK: - Commandes shell bas niveau

    @discardableResult
    func run(_ args: [String], env: [String: String]? = nil) -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args

        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "\(brewPrefix)/bin:\(brewPrefix)/sbin:/usr/bin:/bin:/usr/sbin:/sbin"
        if let extra = env { environment.merge(extra) { _, new in new } }
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError  = pipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ShellResult(output: error.localizedDescription, exitCode: -1)
        }

        let data   = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return ShellResult(output: output, exitCode: process.terminationStatus)
    }

    /// Exécute une commande en arrière-plan et transmet les lignes de log via le callback.
    func runStreaming(_ args: [String], onLine: @escaping (String) -> Void, completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = args

            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "\(self.brewPrefix)/bin:\(self.brewPrefix)/sbin:/usr/bin:/bin:/usr/sbin:/sbin"
            env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
            env["HOMEBREW_NO_ANALYTICS"]   = "1"
            process.environment = env

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError  = pipe

            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if let line = String(data: data, encoding: .utf8), !line.isEmpty {
                    DispatchQueue.main.async { onLine(line) }
                }
            }

            do {
                try process.run()
                process.waitUntilExit()
                pipe.fileHandleForReading.readabilityHandler = nil
                DispatchQueue.main.async { completion(process.terminationStatus == 0) }
            } catch {
                DispatchQueue.main.async {
                    onLine("Erreur : \(error.localizedDescription)")
                    completion(false)
                }
            }
        }
    }

    // MARK: - Statut des services

    func refreshStatus() {
        DispatchQueue.global(qos: .background).async {
            let phpVer   = AppState.shared.phpVersion
            let phpRes   = self.run(["pgrep", "-f", "php-fpm: master"])
            let mariaRes = self.run([self.brewBin, "services", "list"])

            let phpRunning    = phpRes.success
            let mariaRunning  = mariaRes.output.contains("mariadb") && mariaRes.output.contains("started")

            DispatchQueue.main.async {
                self.status.php     = phpRunning   ? .running : .stopped
                self.status.mariadb = mariaRunning ? .running : .stopped
            }
        }
    }

    // MARK: - Démarrage / Arrêt

    func startServices(onLine: @escaping (String) -> Void, completion: @escaping (Bool) -> Void) {
        let phpVer = state.phpVersion
        runStreaming([brewBin, "services", "start", "mariadb"], onLine: onLine) { ok in
            guard ok else { completion(false); return }
            self.runStreaming([self.brewBin, "services", "start", "php@\(phpVer)"], onLine: onLine) { ok2 in
                self.refreshStatus()
                completion(ok2)
            }
        }
    }

    func stopServices(onLine: @escaping (String) -> Void, completion: @escaping (Bool) -> Void) {
        let phpVer = state.phpVersion
        runStreaming([brewBin, "services", "stop", "php@\(phpVer)"], onLine: onLine) { _ in
            self.runStreaming([self.brewBin, "services", "stop", "mariadb"], onLine: onLine) { ok in
                self.refreshStatus()
                completion(ok)
            }
        }
    }

    func restartServices(onLine: @escaping (String) -> Void, completion: @escaping (Bool) -> Void) {
        stopServices(onLine: onLine) { _ in
            self.startServices(onLine: onLine, completion: completion)
        }
    }

    // MARK: - Installation (étapes individuelles)

    func isBrewInstalled() -> Bool {
        FileManager.default.fileExists(atPath: brewBin)
    }

    func isPhpInstalled() -> Bool {
        let phpVer = state.phpVersion
        return FileManager.default.fileExists(atPath: "\(brewPrefix)/opt/php@\(phpVer)/bin/php")
    }

    func isMariaDBInstalled() -> Bool {
        FileManager.default.fileExists(atPath: "\(brewPrefix)/bin/mariadb")
    }

    func isDolibarrInstalled() -> Bool {
        FileManager.default.fileExists(atPath: "\(state.dolibarrPath)/htdocs/index.php")
    }

    func installHomebrew(onLine: @escaping (String) -> Void, completion: @escaping (Bool) -> Void) {
        let script = "/bin/bash"
        let url    = "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
        runStreaming([script, "-c", "curl -fsSL \(url) | bash"], onLine: onLine, completion: completion)
    }

    func installPhp(onLine: @escaping (String) -> Void, completion: @escaping (Bool) -> Void) {
        let phpVer = state.phpVersion
        runStreaming([brewBin, "install", "php@\(phpVer)"], onLine: onLine) { ok in
            guard ok else { completion(false); return }
            // Activer les extensions utiles pour Dolibarr
            let phpIni = "\(self.brewPrefix)/etc/php/\(phpVer)/php.ini"
            let extensions = "extension=gd\nextension=intl\nextension=mbstring\nextension=pdo_mysql\n"
            try? extensions.appendLine(to: phpIni)
            completion(true)
        }
    }

    func installMariaDB(onLine: @escaping (String) -> Void, completion: @escaping (Bool) -> Void) {
        runStreaming([brewBin, "install", "mariadb"], onLine: onLine) { ok in
            guard ok else { completion(false); return }
            // Démarrer MariaDB pour initialiser la BDD
            self.runStreaming([self.brewBin, "services", "start", "mariadb"], onLine: onLine) { _ in
                // Attendre que MariaDB soit prêt
                Thread.sleep(forTimeInterval: 3)
                self.setupDatabase(onLine: onLine, completion: completion)
            }
        }
    }

    private func setupDatabase(onLine: @escaping (String) -> Void, completion: @escaping (Bool) -> Void) {
        let st = AppState.shared
        let sql = """
        CREATE DATABASE IF NOT EXISTS `\(st.dbName)` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
        CREATE USER IF NOT EXISTS '\(st.dbUser)'@'localhost' IDENTIFIED BY '\(st.dbPassword)';
        GRANT ALL PRIVILEGES ON `\(st.dbName)`.* TO '\(st.dbUser)'@'localhost';
        FLUSH PRIVILEGES;
        """
        onLine("Création de la base de données '\(st.dbName)'…")
        let result = run(["\(brewPrefix)/bin/mariadb", "-u", "root", "-e", sql])
        completion(result.success)
    }

    func installDolibarr(onLine: @escaping (String) -> Void, completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let st   = AppState.shared
            let path = st.dolibarrPath
            let fm   = FileManager.default

            // 1. Récupérer la dernière version depuis GitHub
            DispatchQueue.main.async { onLine("Récupération de la dernière version de Dolibarr…") }
            let apiResult = self.run(["curl", "-fsSL",
                "https://api.github.com/repos/Dolibarr/dolibarr/releases/latest"])
            guard apiResult.success,
                  let data  = apiResult.output.data(using: .utf8),
                  let json  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag   = json["tag_name"] as? String else {
                DispatchQueue.main.async {
                    onLine("Erreur : impossible de récupérer la version de Dolibarr")
                    completion(false)
                }
                return
            }

            let version  = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            let zipURL   = "https://github.com/Dolibarr/dolibarr/archive/refs/tags/\(tag).tar.gz"
            let tmpTar   = "/tmp/dolibarr-\(version).tar.gz"
            let tmpDir   = "/tmp/dolibarr-src"

            DispatchQueue.main.async { onLine("Téléchargement de Dolibarr \(version)…") }
            let dlResult = self.run(["curl", "-fsSL", "-o", tmpTar, zipURL])
            guard dlResult.success else {
                DispatchQueue.main.async { onLine("Erreur téléchargement : \(dlResult.output)"); completion(false) }
                return
            }

            // 2. Décompresser
            DispatchQueue.main.async { onLine("Décompression de l'archive…") }
            try? fm.removeItem(atPath: tmpDir)
            let tarResult = self.run(["tar", "-xzf", tmpTar, "-C", "/tmp"])
            guard tarResult.success else {
                DispatchQueue.main.async { onLine("Erreur décompression : \(tarResult.output)"); completion(false) }
                return
            }

            // 3. Déplacer vers le répertoire cible
            DispatchQueue.main.async { onLine("Installation dans \(path)…") }
            try? fm.removeItem(atPath: path)
            let srcDir = "/tmp/dolibarr-\(version)"
            do {
                try fm.moveItem(atPath: srcDir, toPath: path)
            } catch {
                DispatchQueue.main.async { onLine("Erreur déplacement : \(error.localizedDescription)"); completion(false) }
                return
            }

            // 4. Créer les dossiers nécessaires
            let dirs = [
                "\(path)/documents",
                "\(path)/htdocs/conf"
            ]
            for dir in dirs {
                try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
            }

            // 5. Créer conf.php
            DispatchQueue.main.async { onLine("Écriture de la configuration…") }
            let phpVer   = st.phpVersion
            let phpBin   = "\(self.brewPrefix)/opt/php@\(phpVer)/bin/php"
            let confContent = """
            <?php
            $dolibarr_main_url_root          = 'http://localhost:\(st.dolibarrPort)';
            $dolibarr_main_document_root      = '\(path)/htdocs';
            $dolibarr_main_url_root_alt       = '';
            $dolibarr_main_document_root_alt  = '';
            $dolibarr_main_data_root          = '\(path)/documents';
            $dolibarr_main_db_host            = 'localhost';
            $dolibarr_main_db_port            = '3306';
            $dolibarr_main_db_name            = '\(st.dbName)';
            $dolibarr_main_db_prefix          = 'llx_';
            $dolibarr_main_db_user            = '\(st.dbUser)';
            $dolibarr_main_db_pass            = '\(st.dbPassword)';
            $dolibarr_main_db_type            = 'mysqli';
            $dolibarr_main_db_character_set   = 'utf8';
            $dolibarr_main_db_collation       = 'utf8_unicode_ci';
            $dolibarr_main_authentication_type = '';
            $dolibarr_main_demo               = '0';
            $dolibarr_mailing_limit_sendbyweb = '0';
            $dolibarr_main_prod               = '0';
            """
            try? confContent.write(toFile: st.doliconfPath, atomically: true, encoding: .utf8)

            // 6. Configurer PHP-FPM + caddy/nginx léger via PHP built-in server
            DispatchQueue.main.async { onLine("Configuration du serveur PHP…") }
            self.writePhpServerLaunchAgent(phpBin: phpBin, dolibarrPath: path, port: st.dolibarrPort)

            DispatchQueue.main.async {
                onLine("✓ Dolibarr \(version) installé avec succès !")
                completion(true)
            }
        }
    }

    /// Crée un LaunchAgent pour démarrer le serveur PHP au login
    private func writePhpServerLaunchAgent(phpBin: String, dolibarrPath: String, port: Int) {
        let label   = "com.dolibarr.phpserver"
        let plist   = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
            "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(phpBin)</string>
                <string>-S</string>
                <string>localhost:\(port)</string>
                <string>-t</string>
                <string>\(dolibarrPath)/htdocs</string>
            </array>
            <key>RunAtLoad</key>
            <false/>
            <key>StandardOutPath</key>
            <string>\(NSHomeDirectory())/Library/Logs/dolibarr-php.log</string>
            <key>StandardErrorPath</key>
            <string>\(NSHomeDirectory())/Library/Logs/dolibarr-php-error.log</string>
        </dict>
        </plist>
        """
        let agentsDir = "\(NSHomeDirectory())/Library/LaunchAgents"
        try? FileManager.default.createDirectory(atPath: agentsDir, withIntermediateDirectories: true)
        try? plist.write(toFile: "\(agentsDir)/\(label).plist", atomically: true, encoding: .utf8)
    }

    // MARK: - Démarrage/arrêt via LaunchAgent PHP

    func startPhpServer(completion: @escaping (Bool) -> Void) {
        let label  = "com.dolibarr.phpserver"
        let plist  = "\(NSHomeDirectory())/Library/LaunchAgents/\(label).plist"
        let result = run(["launchctl", "load", plist])
        refreshStatus()
        completion(result.success)
    }

    func stopPhpServer(completion: @escaping (Bool) -> Void) {
        let label  = "com.dolibarr.phpserver"
        let plist  = "\(NSHomeDirectory())/Library/LaunchAgents/\(label).plist"
        let result = run(["launchctl", "unload", plist])
        refreshStatus()
        completion(result.success)
    }

    // MARK: - Mise à jour Dolibarr

    func updateDolibarr(onLine: @escaping (String) -> Void, completion: @escaping (Bool) -> Void) {
        onLine("Arrêt des services pour mise à jour…")
        stopServices(onLine: onLine) { _ in
            self.installDolibarr(onLine: onLine) { ok in
                if ok {
                    self.startServices(onLine: onLine, completion: completion)
                } else {
                    completion(false)
                }
            }
        }
    }

    // MARK: - Sauvegarde / Restauration

    func backupDatabase(to dir: String, onLine: @escaping (String) -> Void, completion: @escaping (Bool, String) -> Void) {
        let st        = AppState.shared
        let fm        = FileManager.default
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        let filename  = "dolibarr_backup_\(timestamp).sql.gz"
        let outPath   = "\(dir)/\(filename)"

        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)

        onLine("Sauvegarde de la base '\(st.dbName)'…")
        let dump = run([
            "\(brewPrefix)/bin/mariadb-dump",
            "-u", st.dbUser,
            "-p\(st.dbPassword)",
            st.dbName
        ])

        guard dump.success else {
            onLine("Erreur mysqldump : \(dump.output)")
            completion(false, "")
            return
        }

        // Préfixer le dump avec les métadonnées DoliMac (version, date, BDD).
        // Cet en-tête est utilisé par checkBackupCompatibility() lors de la restauration.
        let installedVersion = readInstalledDolibarrVersion() ?? "inconnue"
        let header = """
        -- ============================================================
        -- DoliMac backup v\(installedVersion)
        -- Date       : \(ISO8601DateFormatter().string(from: Date()))
        -- Base       : \(st.dbName)
        -- Utilisateur: \(st.dbUser)
        -- ============================================================\n\n
        """
        let fullSQL = header + dump.output

        // Compresser avec zlib
        guard let data = fullSQL.data(using: .utf8) else {
            completion(false, ""); return
        }
        do {
            try (data as NSData).compressed(using: .zlib).write(to: URL(fileURLWithPath: outPath))
            onLine("✓ Sauvegarde créée : \(filename) (Dolibarr v\(installedVersion))")
            completion(true, outPath)
        } catch {
            onLine("Erreur compression : \(error.localizedDescription)")
            completion(false, "")
        }
    }

    // MARK: - Vérification de compatibilité d'une sauvegarde

    /// Résultat de la vérification de compatibilité.
    enum CompatibilityResult {
        /// La sauvegarde est compatible (ou la version n'a pas pu être déterminée).
        case compatible(backupVersion: String?, installedVersion: String?)
        /// Versions différentes — restauration risquée.
        case mismatch(backupVersion: String, installedVersion: String)
        /// Sauvegarde d'une version majeure différente — restauration très risquée.
        case majorMismatch(backupVersion: String, installedVersion: String)
        /// Impossible de lire / décompresser le fichier.
        case unreadable(reason: String)
    }

    /// Décompresse et inspecte un fichier `.sql.gz` pour en extraire
    /// la version de Dolibarr qui l'a produit, puis la compare à la version installée.
    func checkBackupCompatibility(at path: String) -> CompatibilityResult {
        // 1. Lire et décompresser
        guard let compressed = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return .unreadable(reason: "Fichier introuvable ou illisible")
        }
        guard let data = try? (compressed as NSData).decompressed(using: .zlib),
              let sql  = String(data: data as Data, encoding: .utf8) else {
            return .unreadable(reason: "Impossible de décompresser l'archive (format non reconnu)")
        }

        // 2. Extraire la version depuis le dump SQL.
        //    DoliMac écrit en en-tête : -- DoliMac backup v17.0.2
        //    Dolibarr natif écrit dans llx_const :
        //      INSERT INTO llx_const ... 'MAIN_VERSION_LAST_INSTALL','17.0.2'
        let backupVersion = extractVersionFromSQL(sql)

        // 3. Lire la version installée (fichier filefunc.lib.php)
        let installedVersion = readInstalledDolibarrVersion()

        // 4. Comparer
        guard let bv = backupVersion, let iv = installedVersion else {
            // Impossible de comparer → on laisse passer avec avertissement
            return .compatible(backupVersion: backupVersion, installedVersion: installedVersion)
        }

        let bParts = bv.split(separator: ".").compactMap { Int($0) }
        let iParts = iv.split(separator: ".").compactMap { Int($0) }

        // Majeure différente : bloquant
        if let bMajor = bParts.first, let iMajor = iParts.first, bMajor != iMajor {
            return .majorMismatch(backupVersion: bv, installedVersion: iv)
        }

        // Mineure différente : avertissement
        if bv != iv {
            return .mismatch(backupVersion: bv, installedVersion: iv)
        }

        return .compatible(backupVersion: bv, installedVersion: iv)
    }

    /// Cherche la version Dolibarr dans le contenu SQL brut.
    /// Stratégie 1 — en-tête DoliMac : `-- DoliMac backup v17.0.2`
    /// Stratégie 2 — dump natif Dolibarr : valeur de MAIN_VERSION_LAST_INSTALL dans llx_const
    /// Stratégie 3 — commentaire mysqldump : `-- Dolibarr version: 17.0.2`
    private func extractVersionFromSQL(_ sql: String) -> String? {
        let patterns: [String] = [
            #"-- DoliMac backup v(\d+\.\d+(?:\.\d+)?)"#,
            #"MAIN_VERSION_LAST_INSTALL[^']*'([0-9]+\.[0-9]+(?:\.[0-9]+)?)'[^;]*;"#,
            #"-- Dolibarr version[:\s]+(\d+\.\d+(?:\.\d+)?)"#,
            #"'MAIN_VERSION_LAST_INSTALL'\s*,\s*'([0-9]+\.[0-9]+(?:\.[0-9]+)?)'"#,
        ]

        // On n'inspecte que les 300 premières lignes et les lignes contenant les mots-clés
        // pour éviter de parcourir plusieurs Mo de SQL.
        let relevantLines = sql
            .components(separatedBy: "\n")
            .prefix(300)
            .filter { $0.contains("DoliMac") || $0.contains("VERSION") || $0.contains("Dolibarr") }
            .joined(separator: "\n")

        // Fallback : chercher dans tout le SQL si rien trouvé dans l'en-tête
        let searchTargets = [relevantLines, sql]

        for target in searchTargets {
            for pattern in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                   let match = regex.firstMatch(in: target,
                                                range: NSRange(target.startIndex..., in: target)),
                   let range = Range(match.range(at: 1), in: target) {
                    return String(target[range])
                }
            }
            if target != sql { continue } // passe au fallback
            break
        }
        return nil
    }

    /// Lit la version installée depuis `filefunc.lib.php` de Dolibarr
    /// (constante `DOL_VERSION`) ou depuis `conf.php` en dernier recours.
    private func readInstalledDolibarrVersion() -> String? {
        let doliPath = AppState.shared.dolibarrPath

        // Méthode 1 : constante DOL_VERSION dans filefunc.lib.php
        let libPath = "\(doliPath)/htdocs/core/lib/functions.lib.php"
        if let content = try? String(contentsOfFile: libPath, encoding: .utf8) {
            let pattern = #"define\s*\(\s*['"]DOL_VERSION['"]\s*,\s*['"]([0-9]+\.[0-9]+(?:\.[0-9]+)?)['"]\s*\)"#
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
               let range = Range(match.range(at: 1), in: content) {
                return String(content[range])
            }
        }

        // Méthode 2 : requête SQL directe dans llx_const
        let result = run([
            "\(brewPrefix)/bin/mariadb",
            "-u", AppState.shared.dbUser,
            "-p\(AppState.shared.dbPassword)",
            "--batch", "--skip-column-names",
            AppState.shared.dbName,
            "-e", "SELECT value FROM llx_const WHERE name='MAIN_VERSION_LAST_INSTALL' LIMIT 1;"
        ])
        let version = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.success && !version.isEmpty {
            return version
        }

        return nil
    }

    // MARK: - Restauration (avec vérification de compatibilité)

    /// Résultat intermédiaire de l'analyse avant restauration.
    struct RestoreAnalysis {
        let sql:              String
        let compatibility:    CompatibilityResult
        let backupVersion:    String?
        let installedVersion: String?
        let sizeKB:           Int
    }

    /// Pré-analyse une sauvegarde avant restauration.
    /// Retourne le SQL décompressé + le résultat de compatibilité
    /// sans effectuer la restauration.
    func analyzeBackup(at path: String) -> Result<RestoreAnalysis, String> {
        guard let compressed = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return .failure("Fichier introuvable ou illisible")
        }
        guard let data = try? (compressed as NSData).decompressed(using: .zlib),
              let sql  = String(data: data as Data, encoding: .utf8) else {
            return .failure("Impossible de décompresser l'archive (format non reconnu)")
        }

        let compat      = checkBackupCompatibility(at: path)
        let bVersion    = extractVersionFromSQL(sql)
        let iVersion    = readInstalledDolibarrVersion()
        let sizeKB      = data.count / 1024

        return .success(RestoreAnalysis(
            sql:              sql,
            compatibility:    compat,
            backupVersion:    bVersion,
            installedVersion: iVersion,
            sizeKB:           sizeKB
        ))
    }

    /// Restaure la base de données depuis un fichier `.sql.gz`.
    /// Effectue une vérification de compatibilité et refuse la restauration
    /// si les versions majeures sont incompatibles (sauf si `force: true`).
    func restoreDatabase(
        from path: String,
        force: Bool = false,
        onLine: @escaping (String) -> Void,
        completion: @escaping (Bool) -> Void
    ) {
        let st = AppState.shared
        onLine("Décompression et analyse de la sauvegarde…")

        // 1. Pré-analyse
        let analysisResult = analyzeBackup(at: path)
        switch analysisResult {
        case .failure(let reason):
            onLine("✗ Erreur : \(reason)")
            completion(false)
            return
        case .success(let analysis):
            // 2. Vérification de compatibilité
            switch analysis.compatibility {
            case .unreadable(let reason):
                onLine("✗ Sauvegarde illisible : \(reason)")
                completion(false)
                return

            case .majorMismatch(let bv, let iv):
                if !force {
                    onLine("✗ Incompatibilité majeure détectée :")
                    onLine("    Version sauvegarde  : \(bv)")
                    onLine("    Version installée   : \(iv)")
                    onLine("  La restauration entre versions majeures différentes")
                    onLine("  peut corrompre la base. Lancez la restauration avec")
                    onLine("  'Forcer la restauration' pour ignorer cet avertissement.")
                    completion(false)
                    return
                }
                onLine("⚠ Incompatibilité majeure ignorée (mode forcé)")
                onLine("    Sauvegarde : v\(bv) → Installé : v\(iv)")

            case .mismatch(let bv, let iv):
                onLine("⚠ Versions différentes (restauration autorisée)")
                onLine("    Sauvegarde : v\(bv) → Installé : v\(iv)")

            case .compatible(let bv, let iv):
                if let bv, let iv {
                    onLine("✓ Compatibilité vérifiée : v\(bv) ↔ v\(iv)")
                } else {
                    onLine("— Version non détectée dans la sauvegarde (restauration autorisée)")
                }
            }

            // 3. Restauration effective
            onLine("Restauration de \(analysis.sizeKB) Ko dans '\(st.dbName)'…")
            let tmpSQL = "/tmp/dolibarr_restore_\(Int(Date().timeIntervalSince1970)).sql"
            do {
                try analysis.sql.write(toFile: tmpSQL, atomically: true, encoding: .utf8)
            } catch {
                onLine("✗ Erreur écriture fichier temporaire : \(error.localizedDescription)")
                completion(false)
                return
            }

            let result = run([
                "\(brewPrefix)/bin/mariadb",
                "-u", st.dbUser,
                "-p\(st.dbPassword)",
                st.dbName,
                "-e", "source \(tmpSQL)"
            ])

            try? FileManager.default.removeItem(atPath: tmpSQL)

            if result.success {
                onLine("✓ Restauration réussie")
            } else {
                onLine("✗ Erreur SQL : \(result.output)")
            }
            completion(result.success)
        }
    }

    // MARK: - Logs

    func logPath(for service: String) -> String {
        switch service {
        case "php":      return "\(NSHomeDirectory())/Library/Logs/dolibarr-php.log"
        case "mariadb":  return "\(brewPrefix)/var/mysql/\(Host.current().localizedName ?? "localhost").err"
        case "dolibarr": return "\(AppState.shared.dolibarrPath)/documents/dolibarr.log"
        default:         return ""
        }
    }
}

// MARK: - Extension utilitaire

private extension String {
    func appendLine(to filePath: String) throws {
        if var content = try? String(contentsOfFile: filePath, encoding: .utf8) {
            if !content.contains(self) {
                content += "\n\(self)"
                try content.write(toFile: filePath, atomically: true, encoding: .utf8)
            }
        }
    }
}
