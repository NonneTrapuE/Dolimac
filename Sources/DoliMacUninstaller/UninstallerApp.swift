import SwiftUI
import AppKit

// ──────────────────────────────────────────────
// MARK: - Point d'entrée
// ──────────────────────────────────────────────

@main
struct DoliMacUninstallerApp: App {
    @NSApplicationDelegateAdaptor(UninstallerDelegate.self) var delegate
    var body: some Scene {
        WindowGroup("Désinstallation de DoliMac") {
            UninstallerView()
                .frame(width: 520, height: 480)
        }
        .windowResizability(.contentSize)
    }
}

class UninstallerDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

// ──────────────────────────────────────────────
// MARK: - Modèle de données
// ──────────────────────────────────────────────

struct UninstallTarget: Identifiable {
    let id = UUID()
    let icon:        String
    let title:       String
    let description: String
    let paths:       [String]
    var selected:    Bool
    var dangerous:   Bool = false

    /// Taille estimée sur disque (calculée à l'exécution)
    var estimatedSizeMB: Int = 0
}

// ──────────────────────────────────────────────
// MARK: - Vue principale
// ──────────────────────────────────────────────

struct UninstallerView: View {

    @State private var targets: [UninstallTarget] = Self.defaultTargets()
    @State private var phase: Phase = .selection
    @State private var logs: [LogLine] = []
    @State private var progress: Double = 0

    enum Phase { case selection, confirm, running, done, failed }

    struct LogLine: Identifiable {
        let id   = UUID()
        let text: String
        let type: LineType
        enum LineType { case info, success, warning, error }
    }

    var selectedTargets: [UninstallTarget] { targets.filter(\.selected) }
    var hasDangerousSelection: Bool { selectedTargets.contains(where: \.dangerous) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            switch phase {
            case .selection: selectionView
            case .confirm:   confirmView
            case .running:   progressView
            case .done:      doneView
            case .failed:    failedView
            }
        }
        .onAppear { estimateSizes() }
    }

    // ── En-tête ──────────────────────────────

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "trash.circle.fill")
                .font(.system(size: 32))
                .foregroundColor(phase == .done ? .green : .red)
            VStack(alignment: .leading, spacing: 2) {
                Text("Désinstallation de DoliMac")
                    .font(.system(size: 16, weight: .semibold))
                Text(headerSubtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private var headerSubtitle: String {
        switch phase {
        case .selection: return "Choisissez les composants à supprimer"
        case .confirm:   return "Confirmez la suppression"
        case .running:   return "Suppression en cours…"
        case .done:      return "DoliMac a été désinstallé"
        case .failed:    return "Une erreur est survenue"
        }
    }

    // ── Sélection ────────────────────────────

    private var selectionView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach($targets) { $target in
                        TargetRow(target: $target)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }

            Divider()

            HStack {
                // Total espace libéré
                let total = selectedTargets.reduce(0) { $0 + $1.estimatedSizeMB }
                if total > 0 {
                    Image(systemName: "externaldrive")
                        .foregroundColor(.secondary)
                    Text("~\(formatSize(total)) libérés")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Annuler") { NSApp.terminate(nil) }
                    .buttonStyle(.bordered)
                Button("Désinstaller…") { phase = .confirm }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(selectedTargets.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
    }

    // ── Confirmation ─────────────────────────

    private var confirmView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundColor(hasDangerousSelection ? .red : .orange)

            Text(hasDangerousSelection
                 ? "Cette action est irréversible"
                 : "Confirmer la désinstallation")
                .font(.system(size: 17, weight: .semibold))

            VStack(alignment: .leading, spacing: 6) {
                ForEach(selectedTargets) { t in
                    HStack(spacing: 8) {
                        Text(t.icon)
                        Text(t.title)
                            .font(.system(size: 13))
                        Spacer()
                        if t.estimatedSizeMB > 0 {
                            Text("~\(formatSize(t.estimatedSizeMB))")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
            .frame(maxWidth: 380)

            if hasDangerousSelection {
                Text("⚠️ La base de données et/ou les sauvegardes seront définitivement supprimées.")
                    .font(.system(size: 12))
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }

            Spacer()

            HStack {
                Button("Retour") { phase = .selection }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Confirmer la suppression") { runUninstall() }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .padding(.horizontal, 24)
    }

    // ── Progression ──────────────────────────

    private var progressView: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(.red)
                HStack {
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(logs) { line in
                            HStack(alignment: .top, spacing: 6) {
                                Text(line.type.icon)
                                    .font(.system(size: 11))
                                Text(line.text)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(line.type.color)
                            }
                            .id(line.id)
                        }
                    }
                    .padding(10)
                }
                .background(Color(NSColor.textBackgroundColor).opacity(0.5))
                .cornerRadius(8)
                .padding(.horizontal, 20)
                .onChange(of: logs.count) { _ in
                    if let last = logs.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }

            Spacer()
        }
    }

    // ── Terminé ──────────────────────────────

    private var doneView: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundColor(.green)
            Text("Désinstallation terminée")
                .font(.system(size: 20, weight: .semibold))
            Text("Tous les composants sélectionnés ont été supprimés.")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 8) {
                if targets.first(where: { $0.title == "Application DoliMac" && !$0.selected }) != nil {
                    InfoRow(icon: "info.circle", text: "L'app DoliMac est toujours dans /Applications")
                }
                InfoRow(icon: "arrow.counterclockwise", text: "Relancez l'assistant pour réinstaller Dolibarr")
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .frame(maxWidth: 360)

            Spacer()
            Button("Fermer") { NSApp.terminate(nil) }
                .buttonStyle(.borderedProminent)
                .frame(width: 160)
                .padding(.bottom, 20)
        }
        .padding(.horizontal, 40)
    }

    // ── Échec ────────────────────────────────

    private var failedView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 52))
                .foregroundColor(.red)
            Text("Erreur lors de la désinstallation")
                .font(.system(size: 17, weight: .semibold))
            Text("Consultez les journaux ci-dessous pour le détail.")
                .font(.system(size: 13))
                .foregroundColor(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(logs.filter { $0.type == .error }) { line in
                        Text(line.text)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.red)
                    }
                }
                .padding(10)
            }
            .background(Color(NSColor.textBackgroundColor).opacity(0.5))
            .cornerRadius(8)
            .frame(maxHeight: 140)
            .padding(.horizontal, 20)

            Spacer()
            HStack {
                Button("Retour") { phase = .selection }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Fermer") { NSApp.terminate(nil) }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .padding(.horizontal, 20)
    }

    // ──────────────────────────────────────────
    // MARK: - Logique de désinstallation
    // ──────────────────────────────────────────

    private func runUninstall() {
        phase    = .running
        logs     = []
        progress = 0

        DispatchQueue.global(qos: .userInitiated).async {
            let total  = Double(selectedTargets.count)
            var done   = 0.0

            for target in selectedTargets {
                addLog("Suppression : \(target.title)…", type: .info)

                // 1. Arrêter les services si nécessaire
                if target.title.contains("Services") || target.title.contains("Application") {
                    stopServices()
                }

                // 2. Supprimer les chemins
                var allOk = true
                for path in target.paths {
                    let expanded = (path as NSString).expandingTildeInPath
                    let fm = FileManager.default
                    if fm.fileExists(atPath: expanded) {
                        do {
                            try fm.removeItem(atPath: expanded)
                            addLog("  ✓ Supprimé : \(path)", type: .success)
                        } catch {
                            addLog("  ✗ Impossible de supprimer \(path) : \(error.localizedDescription)", type: .error)
                            allOk = false
                        }
                    } else {
                        addLog("  — Non trouvé (déjà supprimé) : \(path)", type: .warning)
                    }
                }

                if !allOk {
                    DispatchQueue.main.async { self.phase = .failed }
                    return
                }

                done += 1
                DispatchQueue.main.async {
                    withAnimation { self.progress = done / total }
                }
            }

            // 3. Nettoyer les préférences UserDefaults
            if selectedTargets.contains(where: { $0.title.contains("Préférences") || $0.title.contains("Application") }) {
                clearUserDefaults()
            }

            addLog("✓ Désinstallation terminée", type: .success)
            DispatchQueue.main.async {
                withAnimation { self.progress = 1.0 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    self.phase = .done
                }
            }
        }
    }

    private func stopServices() {
        let brew = "/opt/homebrew/bin/brew"
        if FileManager.default.fileExists(atPath: brew) {
            let _ = shell([brew, "services", "stop", "mariadb"])
            let _ = shell([brew, "services", "stop", "php@8.2"])
        }
        let label = "com.dolibarr.phpserver"
        let plist = "\(NSHomeDirectory())/Library/LaunchAgents/\(label).plist"
        if FileManager.default.fileExists(atPath: plist) {
            let _ = shell(["launchctl", "unload", plist])
        }
        addLog("  ↓ Services arrêtés", type: .info)
    }

    private func clearUserDefaults() {
        let domain = "com.dolibarr.DolibarrBar"
        UserDefaults.standard.removePersistentDomain(forName: domain)
        UserDefaults.standard.synchronize()
        addLog("  ✓ Préférences supprimées", type: .success)
    }

    @discardableResult
    private func shell(_ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments     = args
        try? p.run()
        p.waitUntilExit()
        return p.terminationStatus
    }

    private func addLog(_ text: String, type: LogLine.LineType) {
        DispatchQueue.main.async {
            self.logs.append(LogLine(text: text, type: type))
        }
    }

    // ──────────────────────────────────────────
    // MARK: - Estimation des tailles
    // ──────────────────────────────────────────

    private func estimateSizes() {
        DispatchQueue.global(qos: .background).async {
            for i in targets.indices {
                let size = targets[i].paths.reduce(0) { acc, path in
                    acc + diskUsageMB(at: (path as NSString).expandingTildeInPath)
                }
                DispatchQueue.main.async {
                    self.targets[i].estimatedSizeMB = size
                }
            }
        }
    }

    private func diskUsageMB(at path: String) -> Int {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path),
              let attrs = try? fm.attributesOfItem(atPath: path) else { return 0 }
        if let size = attrs[.size] as? Int { return size / 1_048_576 }
        // Dossier : somme récursive approximative
        guard let enumerator = fm.enumerator(atPath: path) else { return 0 }
        var total = 0
        for case let file as String in enumerator {
            if let a = try? fm.attributesOfItem(atPath: "\(path)/\(file)"),
               let s = a[.size] as? Int { total += s }
        }
        return total / 1_048_576
    }

    private func formatSize(_ mb: Int) -> String {
        mb >= 1024 ? String(format: "%.1f Go", Double(mb) / 1024) : "\(mb) Mo"
    }

    // ──────────────────────────────────────────
    // MARK: - Cibles par défaut
    // ──────────────────────────────────────────

    static func defaultTargets() -> [UninstallTarget] {
        let home  = NSHomeDirectory()
        let brew  = "/opt/homebrew"

        return [
            UninstallTarget(
                icon: "📦",
                title: "Application DoliMac",
                description: "L'app dans /Applications et ses LaunchAgents",
                paths: [
                    "/Applications/DoliMac.app",
                    "\(home)/Library/LaunchAgents/com.dolibarr.phpserver.plist"
                ],
                selected: true
            ),
            UninstallTarget(
                icon: "🗂",
                title: "Fichiers Dolibarr",
                description: "Code source, htdocs et documents Dolibarr",
                paths: ["\(home)/Dolibarr"],
                selected: true
            ),
            UninstallTarget(
                icon: "⚙️",
                title: "Préférences et configuration",
                description: "Réglages, port, mots de passe stockés",
                paths: [
                    "\(home)/Library/Preferences/com.dolibarr.DolibarrBar.plist"
                ],
                selected: true
            ),
            UninstallTarget(
                icon: "📄",
                title: "Journaux",
                description: "Fichiers de logs PHP et Dolibarr",
                paths: [
                    "\(home)/Library/Logs/dolibarr-php.log",
                    "\(home)/Library/Logs/dolibarr-php-error.log"
                ],
                selected: false
            ),
            UninstallTarget(
                icon: "🗄",
                title: "Base de données MariaDB",
                description: "Toutes les données Dolibarr en base",
                paths: ["\(brew)/var/mysql"],
                selected: false,
                dangerous: true
            ),
            UninstallTarget(
                icon: "💾",
                title: "Sauvegardes",
                description: "Fichiers .sql.gz de sauvegarde",
                paths: ["\(home)/Documents/DolibarrBackups"],
                selected: false,
                dangerous: true
            ),
            UninstallTarget(
                icon: "🍺",
                title: "PHP et MariaDB (Homebrew)",
                description: "Désinstalle PHP 8.2 et MariaDB via Homebrew",
                paths: [
                    "\(brew)/opt/php@8.2",
                    "\(brew)/opt/mariadb"
                ],
                selected: false,
                dangerous: true
            ),
        ]
    }
}

// ──────────────────────────────────────────────
// MARK: - Composants UI
// ──────────────────────────────────────────────

struct TargetRow: View {
    @Binding var target: UninstallTarget

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Toggle("", isOn: $target.selected)
                .labelsHidden()

            Text(target.icon)
                .font(.system(size: 22))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(target.title)
                        .font(.system(size: 13, weight: .medium))
                    if target.dangerous {
                        Text("IRRÉVERSIBLE")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .cornerRadius(4)
                    }
                }
                Text(target.description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if target.estimatedSizeMB > 0 {
                Text(target.estimatedSizeMB >= 1024
                     ? String(format: "~%.1f Go", Double(target.estimatedSizeMB) / 1024)
                     : "~\(target.estimatedSizeMB) Mo")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(target.selected
                      ? (target.dangerous ? Color.red.opacity(0.07) : Color.accentColor.opacity(0.06))
                      : Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(target.selected && target.dangerous
                              ? Color.red.opacity(0.3)
                              : Color.clear, lineWidth: 1)
        )
    }
}

struct InfoRow: View {
    let icon: String; let text: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundColor(.accentColor).frame(width: 16)
            Text(text).font(.system(size: 12))
        }
    }
}

// ──────────────────────────────────────────────
// MARK: - Extensions
// ──────────────────────────────────────────────

extension UninstallerView.LogLine.LineType {
    var icon: String {
        switch self {
        case .info:    return "→"
        case .success: return "✓"
        case .warning: return "—"
        case .error:   return "✗"
        }
    }
    var color: Color {
        switch self {
        case .info:    return .primary
        case .success: return .green
        case .warning: return .secondary
        case .error:   return .red
        }
    }
}
