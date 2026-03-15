import AppKit
import SwiftUI

class StatusBarController: NSObject {
    private var statusItem: NSStatusItem
    private var menu = NSMenu()
    private let manager = DolibarrServiceManager.shared

    // Items mis à jour dynamiquement
    private var statusMenuItem: NSMenuItem!
    private var startItem: NSMenuItem!
    private var stopItem: NSMenuItem!
    private var restartItem: NSMenuItem!
    private var openItem: NSMenuItem!

    // Fenêtre de progression (backup, restore, update)
    private var progressWindowController: NSWindowController?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        configureButton()
        buildMenu()
        statusItem.menu = menu

        manager.refreshStatus()
        Timer.scheduledTimer(withTimeInterval: 6.0, repeats: true) { [weak self] _ in
            self?.manager.refreshStatus()
            self?.updateMenuState()
        }

        // Observer les changements de statut
        NotificationCenter.default.addObserver(
            self, selector: #selector(updateMenuState),
            name: NSNotification.Name("DolibarrStatusChanged"), object: nil
        )
    }

    // MARK: - Bouton status bar

    private func configureButton() {
        guard let btn = statusItem.button else { return }
        btn.image = NSImage(systemSymbolName: "shippingbox", accessibilityDescription: "Dolibarr")
        btn.image?.isTemplate = true
        btn.toolTip = "Dolibarr Manager"
    }

    private func setIconRunning(_ running: Bool) {
        guard let btn = statusItem.button else { return }
        let name = running ? "shippingbox.fill" : "shippingbox"
        btn.image = NSImage(systemSymbolName: name, accessibilityDescription: "Dolibarr")
        btn.image?.isTemplate = true
    }

    // MARK: - Construction du menu

    private func buildMenu() {
        menu.removeAllItems()

        // En-tête — titre + statut
        let headerItem = NSMenuItem()
        headerItem.view = makeHeaderView()
        menu.addItem(headerItem)

        menu.addItem(.separator())

        // Statut texte (mis à jour dynamiquement)
        statusMenuItem = NSMenuItem(title: "Vérification…", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        menu.addItem(.separator())

        // --- Actions principales ---
        startItem = item("▶  Démarrer",    action: #selector(startServices),   key: "")
        stopItem  = item("■  Arrêter",     action: #selector(stopServices),    key: "")
        restartItem = item("↺  Redémarrer", action: #selector(restartServices), key: "")
        menu.addItem(startItem)
        menu.addItem(stopItem)
        menu.addItem(restartItem)

        menu.addItem(.separator())

        openItem = item("🌐  Ouvrir Dolibarr dans Safari", action: #selector(openInBrowser), key: "o")
        menu.addItem(openItem)

        menu.addItem(.separator())

        // --- Sous-menu Maintenance ---
        let maintMenu = NSMenu()
        maintMenu.addItem(item("⬆  Mettre à jour Dolibarr",          action: #selector(updateDolibarr),  key: ""))
        maintMenu.addItem(.separator())
        maintMenu.addItem(item("💾  Sauvegarder la base de données",   action: #selector(backupDB),        key: ""))
        maintMenu.addItem(item("📂  Restaurer une sauvegarde…",        action: #selector(restoreDB),       key: ""))
        maintMenu.addItem(.separator())
        maintMenu.addItem(item("🗑  Désinstaller Dolibarr…",           action: #selector(uninstall),       key: ""))

        let maintParent = NSMenuItem(title: "🔧  Maintenance", action: nil, keyEquivalent: "")
        maintParent.submenu = maintMenu
        menu.addItem(maintParent)

        // --- Sous-menu Journaux ---
        let logsMenu = NSMenu()
        logsMenu.addItem(item("Journaux PHP",       action: #selector(logPhp),      key: ""))
        logsMenu.addItem(item("Journaux MariaDB",   action: #selector(logMariaDB),  key: ""))
        logsMenu.addItem(item("Journaux Dolibarr",  action: #selector(logDolibarr), key: ""))

        let logsParent = NSMenuItem(title: "📄  Journaux", action: nil, keyEquivalent: "")
        logsParent.submenu = logsMenu
        menu.addItem(logsParent)

        menu.addItem(.separator())
        menu.addItem(item("Préférences…",  action: #selector(openPreferences), key: ","))
        menu.addItem(.separator())
        menu.addItem(item("Quitter",       action: #selector(quit),            key: "q"))

        updateMenuState()
    }

    private func item(_ title: String, action: Selector, key: String) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: action, keyEquivalent: key)
        it.target = self
        return it
    }

    // MARK: - Mise à jour dynamique du menu

    @objc func updateMenuState() {
        let st = manager.status
        let running = st.allRunning

        setIconRunning(running)

        if running {
            statusMenuItem.title = "● En cours d'exécution"
            statusMenuItem.attributedTitle = coloredStatus("● En cours d'exécution", color: .systemGreen)
        } else if st.allStopped {
            statusMenuItem.title = "● Arrêté"
            statusMenuItem.attributedTitle = coloredStatus("● Arrêté", color: .systemRed)
        } else {
            statusMenuItem.title = "● Partiellement actif"
            statusMenuItem.attributedTitle = coloredStatus("● Partiellement actif", color: .systemOrange)
        }

        startItem.isEnabled   = !running
        stopItem.isEnabled    = !st.allStopped
        restartItem.isEnabled = running
        openItem.isEnabled    = running
    }

    private func coloredStatus(_ text: String, color: NSColor) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .foregroundColor: color,
            .font: NSFont.systemFont(ofSize: 13)
        ])
    }

    private func makeHeaderView() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 36))

        let icon = NSImageView(frame: NSRect(x: 14, y: 8, width: 20, height: 20))
        icon.image = NSImage(systemSymbolName: "shippingbox.fill", accessibilityDescription: nil)
        icon.image?.isTemplate = false
        icon.contentTintColor = NSColor.controlAccentColor

        let label = NSTextField(labelWithString: "Dolibarr")
        label.font      = NSFont.boldSystemFont(ofSize: 13)
        label.textColor = .labelColor
        label.frame     = NSRect(x: 42, y: 10, width: 120, height: 16)

        view.addSubview(icon)
        view.addSubview(label)
        return view
    }

    // MARK: - Actions services

    @objc private func startServices() {
        showProgressSheet(title: "Démarrage de Dolibarr…") { onLine, onDone in
            self.manager.startServices(onLine: onLine) { ok in
                onDone(ok, ok ? "Dolibarr démarré avec succès" : "Échec du démarrage")
                self.updateMenuState()
            }
        }
    }

    @objc private func stopServices() {
        showProgressSheet(title: "Arrêt de Dolibarr…") { onLine, onDone in
            self.manager.stopServices(onLine: onLine) { ok in
                onDone(ok, ok ? "Dolibarr arrêté" : "Échec de l'arrêt")
                self.updateMenuState()
            }
        }
    }

    @objc private func restartServices() {
        showProgressSheet(title: "Redémarrage de Dolibarr…") { onLine, onDone in
            self.manager.restartServices(onLine: onLine) { ok in
                onDone(ok, ok ? "Dolibarr redémarré" : "Échec du redémarrage")
                self.updateMenuState()
            }
        }
    }

    @objc private func openInBrowser() {
        NSWorkspace.shared.open(AppState.shared.dolibarrURL)
    }

    // MARK: - Maintenance

    @objc private func updateDolibarr() {
        let alert = NSAlert()
        alert.messageText     = "Mettre à jour Dolibarr ?"
        alert.informativeText = "Les services seront redémarrés. Vos données sont conservées."
        alert.addButton(withTitle: "Mettre à jour")
        alert.addButton(withTitle: "Annuler")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        showProgressSheet(title: "Mise à jour de Dolibarr…") { onLine, onDone in
            self.manager.updateDolibarr(onLine: onLine) { ok in
                onDone(ok, ok ? "Mise à jour terminée" : "Échec de la mise à jour")
            }
        }
    }

    @objc private func backupDB() {
        let panel = NSSavePanel()
        panel.title             = "Choisir le dossier de sauvegarde"
        panel.nameFieldLabel    = "Nom du dossier :"
        panel.canCreateDirectories = true
        panel.directoryURL      = URL(fileURLWithPath: AppState.shared.backupDir)

        guard panel.runModal() == .OK, let url = panel.url else { return }
        AppState.shared.backupDir = url.deletingLastPathComponent().path

        showProgressSheet(title: "Sauvegarde de la base de données…") { onLine, onDone in
            self.manager.backupDatabase(to: url.deletingLastPathComponent().path, onLine: onLine) { ok, path in
                onDone(ok, ok ? "Sauvegarde créée : \(url.lastPathComponent)" : "Échec de la sauvegarde")
            }
        }
    }

    @objc private func restoreDB() {
        // 1. Choix du fichier
        let panel = NSOpenPanel()
        panel.title               = "Choisir la sauvegarde à restaurer"
        panel.allowedContentTypes = [.init(filenameExtension: "gz")!]
        panel.directoryURL        = URL(fileURLWithPath: AppState.shared.backupDir)
        panel.message             = "Sélectionnez un fichier .sql.gz produit par DoliMac"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        // 2. Pré-analyse de compatibilité (lecture du fichier uniquement, pas de restauration)
        var force = false
        let analysisResult = manager.analyzeBackup(at: url.path)

        switch analysisResult {
        case .failure(let reason):
            let err = NSAlert()
            err.alertStyle      = .critical
            err.messageText     = "Fichier de sauvegarde invalide"
            err.informativeText = reason
            err.runModal()
            return

        case .success(let analysis):
            // 3. Dialog de compatibilité adapté au résultat
            let proceed = showCompatibilityAlert(analysis: analysis, forceOut: &force)
            guard proceed else { return }
        }

        // 4. Restauration avec le flag force éventuel
        showProgressSheet(title: "Restauration de la sauvegarde…") { onLine, onDone in
            self.manager.restoreDatabase(from: url.path, force: force, onLine: onLine) { ok in
                onDone(ok, ok ? "Restauration réussie" : "Échec de la restauration")
            }
        }
    }

    /// Affiche un dialog de confirmation adapté au résultat de la vérification de compatibilité.
    /// Retourne `true` si la restauration doit continuer, `false` si annulée.
    /// `forceOut` est mis à `true` si l'utilisateur choisit de forcer malgré une incompatibilité.
    private func showCompatibilityAlert(
        analysis: DolibarrServiceManager.RestoreAnalysis,
        forceOut: inout Bool
    ) -> Bool {
        let alert = NSAlert()

        switch analysis.compatibility {
        case .compatible(let bv, let iv):
            // Versions identiques ou non détectées → confirmation simple
            alert.alertStyle = .warning
            if let bv, let iv {
                alert.messageText     = "Restaurer la sauvegarde Dolibarr v\(bv) ?"
                alert.informativeText = """
                Version installée : \(iv)
                Taille : \(formatKB(analysis.sizeKB))

                ⚠️ La base de données actuelle sera écrasée par cette sauvegarde.
                Cette action est irréversible.
                """
            } else {
                alert.messageText     = "Restaurer la sauvegarde ?"
                alert.informativeText = """
                Version de Dolibarr non détectée dans la sauvegarde.
                Taille : \(formatKB(analysis.sizeKB))

                ⚠️ La base de données actuelle sera écrasée.
                Cette action est irréversible.
                """
            }
            alert.addButton(withTitle: "Restaurer")
            alert.addButton(withTitle: "Annuler")
            return alert.runModal() == .alertFirstButtonReturn

        case .mismatch(let bv, let iv):
            // Même version majeure mais différente → avertissement + confirmation
            alert.alertStyle = .warning
            alert.messageText     = "Versions légèrement différentes"
            alert.informativeText = """
            Version dans la sauvegarde : \(bv)
            Version installée          : \(iv)
            Taille : \(formatKB(analysis.sizeKB))

            Les versions mineures diffèrent. La restauration devrait fonctionner,
            mais des champs de base de données peuvent manquer ou être incompatibles.

            Il est recommandé d'utiliser une sauvegarde de la même version.
            """
            alert.addButton(withTitle: "Restaurer quand même")
            alert.addButton(withTitle: "Annuler")
            return alert.runModal() == .alertFirstButtonReturn

        case .majorMismatch(let bv, let iv):
            // Versions majeures différentes → blocage + option force
            alert.alertStyle = .critical
            alert.messageText     = "Incompatibilité majeure de version"
            alert.informativeText = """
            Version dans la sauvegarde : \(bv)
            Version installée          : \(iv)

            Les versions majeures sont différentes. Restaurer cette sauvegarde
            risque fortement de corrompre la base de données ou de rendre
            Dolibarr inutilisable.

            Pour restaurer correctement, installez d'abord Dolibarr \(bv).
            """
            alert.addButton(withTitle: "Annuler")
            alert.addButton(withTitle: "Forcer la restauration (risqué)")
            let response = alert.runModal()
            if response == .alertSecondButtonReturn {
                // L'utilisateur a explicitement choisi de forcer
                let confirm = NSAlert()
                confirm.alertStyle      = .critical
                confirm.messageText     = "Confirmer la restauration forcée ?"
                confirm.informativeText = "Cette opération peut corrompre Dolibarr de manière irréversible."
                confirm.addButton(withTitle: "Confirmer")
                confirm.addButton(withTitle: "Annuler")
                if confirm.runModal() == .alertFirstButtonReturn {
                    forceOut = true
                    return true
                }
            }
            return false

        case .unreadable(let reason):
            alert.alertStyle      = .critical
            alert.messageText     = "Sauvegarde illisible"
            alert.informativeText = reason
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return false
        }
    }

    private func formatKB(_ kb: Int) -> String {
        kb >= 1024 ? String(format: "%.1f Mo", Double(kb) / 1024) : "\(kb) Ko"
    }

    @objc private func uninstall() {
        let alert = NSAlert()
        alert.messageText     = "Désinstaller Dolibarr ?"
        alert.informativeText = "Cela supprimera tous les fichiers Dolibarr. La base de données et les sauvegardes sont conservées."
        alert.alertStyle      = .critical
        alert.addButton(withTitle: "Désinstaller")
        alert.addButton(withTitle: "Annuler")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        // Arrêter les services puis supprimer
        manager.stopServices(onLine: { _ in }) { _ in
            try? FileManager.default.removeItem(atPath: AppState.shared.dolibarrPath)
            AppState.shared.reset()
            let info = NSAlert()
            info.messageText = "Dolibarr désinstallé"
            info.informativeText = "PHP et MariaDB sont conservés (gérés via Homebrew)."
            info.runModal()
        }
    }

    // MARK: - Logs

    @objc private func logPhp()      { openLog(for: "php") }
    @objc private func logMariaDB()  { openLog(for: "mariadb") }
    @objc private func logDolibarr() { openLog(for: "dolibarr") }

    private func openLog(for service: String) {
        let path = manager.logPath(for: service)
        guard !path.isEmpty else { return }
        // Ouvrir dans Console.app si disponible, sinon TextEdit
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    // MARK: - Préférences

    @objc private func openPreferences() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 280),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title    = "Préférences — Dolibarr"
        window.center()
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: PreferencesView())
        let wc = NSWindowController(window: window)
        wc.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        progressWindowController = wc // Garder une référence
    }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - Fenêtre de progression générique

    private func showProgressSheet(
        title: String,
        work: @escaping (@escaping (String) -> Void, @escaping (Bool, String) -> Void) -> Void
    ) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.center()
        window.isReleasedWhenClosed = false

        let view = ProgressSheetView(title: title) { onLine, onDone in
            work(onLine, { ok, msg in
                onDone(ok, msg)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    window.close()
                    self.progressWindowController = nil
                }
            })
        }
        window.contentView = NSHostingView(rootView: view)
        let wc = NSWindowController(window: window)
        wc.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        progressWindowController = wc
    }
}

// MARK: - Feuille de progression générique

struct ProgressSheetView: View {
    let title: String
    let work: (@escaping (String) -> Void, @escaping (Bool, String) -> Void) -> Void

    @State private var logs:    [String] = []
    @State private var result:  String   = ""
    @State private var success: Bool     = false
    @State private var done:    Bool     = false

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                if !done {
                    ProgressView().scaleEffect(0.7)
                } else {
                    Image(systemName: success ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(success ? .green : .red)
                }
                Text(done ? result : title)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(logs.enumerated()), id: \.offset) { i, line in
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(line.hasPrefix("✓") ? .green :
                                                 line.contains("Erreur") ? .red : .primary)
                                .id(i)
                        }
                    }
                    .padding(8)
                }
                .background(Color(NSColor.textBackgroundColor).opacity(0.6))
                .cornerRadius(8)
                .onChange(of: logs.count) { _ in
                    if let last = logs.indices.last {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 480, height: 300)
        .onAppear {
            work({ line in
                DispatchQueue.main.async { logs.append(line) }
            }, { ok, msg in
                DispatchQueue.main.async {
                    success = ok
                    result  = msg
                    done    = true
                }
            })
        }
    }
}

// MARK: - Préférences

struct PreferencesView: View {
    @ObservedObject private var state = AppState.shared

    var body: some View {
        Form {
            Section(header: Text("Serveur").font(.headline)) {
                HStack {
                    Text("Port HTTP")
                    Spacer()
                    TextField("8080", value: $state.dolibarrPort, format: .number)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                }
            }
            Section(header: Text("Sauvegardes").font(.headline).padding(.top, 8)) {
                HStack {
                    Text("Dossier")
                    Spacer()
                    Text(state.backupDir)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .truncationMode(.middle)
                        .lineLimit(1)
                    Button("…") { chooseBackupDir() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
        .padding(24)
        .frame(width: 400)
    }

    private func chooseBackupDir() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            state.backupDir = url.path
        }
    }
}
