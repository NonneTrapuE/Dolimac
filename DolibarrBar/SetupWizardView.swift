import SwiftUI

// MARK: - Étapes de l'assistant

enum SetupStep: Int, CaseIterable {
    case welcome    = 0
    case configure  = 1
    case install    = 2
    case done       = 3

    var title: String {
        switch self {
        case .welcome:   return "Bienvenue"
        case .configure: return "Configuration"
        case .install:   return "Installation"
        case .done:      return "Terminé"
        }
    }
}

// MARK: - Vue principale de l'assistant

struct SetupWizardView: View {
    @StateObject private var state = AppState.shared
    @State private var currentStep: SetupStep = .welcome
    var onComplete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Barre de progression des étapes
            StepIndicatorView(current: currentStep)
                .padding(.horizontal, 32)
                .padding(.top, 24)
                .padding(.bottom, 20)

            Divider()

            // Contenu de l'étape courante
            Group {
                switch currentStep {
                case .welcome:
                    WelcomeStepView { currentStep = .configure }

                case .configure:
                    ConfigureStepView(
                        onBack: { currentStep = .welcome },
                        onNext: { currentStep = .install }
                    )

                case .install:
                    InstallStepView(
                        onBack: { currentStep = .configure },
                        onComplete: { currentStep = .done }
                    )

                case .done:
                    DoneStepView(onLaunch: onComplete)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 540, height: 440)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Indicateur d'étapes

struct StepIndicatorView: View {
    let current: SetupStep

    var body: some View {
        HStack(spacing: 0) {
            ForEach(SetupStep.allCases, id: \.self) { step in
                HStack(spacing: 6) {
                    // Cercle numéroté
                    ZStack {
                        Circle()
                            .fill(step.rawValue <= current.rawValue ? Color.accentColor : Color(NSColor.separatorColor))
                            .frame(width: 24, height: 24)
                        Text("\(step.rawValue + 1)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(step.rawValue <= current.rawValue ? .white : Color(NSColor.secondaryLabelColor))
                    }
                    Text(step.title)
                        .font(.system(size: 12))
                        .foregroundColor(step == current ? .primary : Color(NSColor.secondaryLabelColor))
                }

                // Ligne de connexion
                if step != SetupStep.allCases.last {
                    Rectangle()
                        .fill(step.rawValue < current.rawValue ? Color.accentColor : Color(NSColor.separatorColor))
                        .frame(height: 1)
                        .padding(.horizontal, 6)
                }
            }
        }
    }
}

// MARK: - Étape 1 : Accueil

struct WelcomeStepView: View {
    var onNext: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 52))
                .foregroundColor(.accentColor)

            Text("Dolibarr pour macOS")
                .font(.system(size: 22, weight: .semibold))

            Text("Cet assistant va installer PHP, MariaDB et Dolibarr sur votre Mac en quelques minutes.\nAucune commande à taper.")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            VStack(alignment: .leading, spacing: 8) {
                RequirementRow(icon: "checkmark.circle.fill", color: .green,
                               text: "macOS 13 Ventura ou supérieur")
                RequirementRow(icon: "checkmark.circle.fill", color: .green,
                               text: "Apple Silicon (M1/M2/M3)")
                RequirementRow(icon: "checkmark.circle.fill", color: .green,
                               text: "Connexion internet requise")
                RequirementRow(icon: "checkmark.circle.fill", color: .green,
                               text: "~1 Go d'espace disque libre")
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
            .frame(maxWidth: 340)

            Spacer()

            Button(action: onNext) {
                Text("Commencer")
                    .frame(width: 160)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 40)
    }
}

struct RequirementRow: View {
    let icon: String
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 16)
            Text(text)
                .font(.system(size: 12))
        }
    }
}

// MARK: - Étape 2 : Configuration

struct ConfigureStepView: View {
    @ObservedObject private var state = AppState.shared
    var onBack: () -> Void
    var onNext: () -> Void

    @State private var showPassword = false

    var isValid: Bool {
        !state.dbPassword.isEmpty && state.dbPassword.count >= 8
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Configuration de Dolibarr")
                        .font(.system(size: 16, weight: .semibold))

                    // Section Base de données
                    GroupBox(label: Label("Base de données", systemImage: "cylinder.fill")) {
                        VStack(spacing: 10) {
                            ConfigRow(label: "Nom BDD") {
                                TextField("dolibarr", text: $state.dbName)
                                    .textFieldStyle(.roundedBorder)
                            }
                            ConfigRow(label: "Utilisateur") {
                                TextField("dolibarr", text: $state.dbUser)
                                    .textFieldStyle(.roundedBorder)
                            }
                            ConfigRow(label: "Mot de passe") {
                                HStack {
                                    if showPassword {
                                        TextField("Min. 8 caractères", text: $state.dbPassword)
                                            .textFieldStyle(.roundedBorder)
                                    } else {
                                        SecureField("Min. 8 caractères", text: $state.dbPassword)
                                            .textFieldStyle(.roundedBorder)
                                    }
                                    Button(action: { showPassword.toggle() }) {
                                        Image(systemName: showPassword ? "eye.slash" : "eye")
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            if !state.dbPassword.isEmpty && state.dbPassword.count < 8 {
                                Text("Le mot de passe doit contenir au moins 8 caractères")
                                    .font(.system(size: 11))
                                    .foregroundColor(.red)
                            }
                        }
                        .padding(.top, 6)
                    }

                    // Section Serveur
                    GroupBox(label: Label("Serveur web", systemImage: "network")) {
                        VStack(spacing: 10) {
                            ConfigRow(label: "Port HTTP") {
                                HStack {
                                    TextField("8080", value: $state.dolibarrPort, format: .number)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 80)
                                    Text("→ http://localhost:\(state.dolibarrPort)")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                            }
                            ConfigRow(label: "Répertoire") {
                                HStack {
                                    Text(state.dolibarrPath)
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                        .truncationMode(.middle)
                                        .lineLimit(1)
                                    Spacer()
                                    Button("Choisir…") {
                                        chooseDirectory()
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                        }
                        .padding(.top, 6)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 20)
            }

            Divider()

            // Navigation
            HStack {
                Button("Retour", action: onBack)
                    .buttonStyle(.bordered)
                Spacer()
                Button(action: onNext) {
                    Text("Installer")
                        .frame(width: 120)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 14)
        }
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles       = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt               = "Choisir"
        panel.message              = "Choisissez le dossier d'installation de Dolibarr"
        if panel.runModal() == .OK, let url = panel.url {
            state.dolibarrPath = url.path
        }
    }
}

struct ConfigRow<Content: View>: View {
    let label: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(alignment: .center) {
            Text(label)
                .font(.system(size: 12))
                .frame(width: 90, alignment: .trailing)
                .foregroundColor(.secondary)
            content()
        }
    }
}

// MARK: - Étape 3 : Installation

struct InstallStepView: View {
    @ObservedObject private var state = AppState.shared
    var onBack: () -> Void
    var onComplete: () -> Void

    @State private var isRunning    = false
    @State private var currentTask  = ""
    @State private var logs: [String] = []
    @State private var progress: Double = 0
    @State private var failed = false

    private let manager = DolibarrServiceManager.shared

    private let tasks: [(label: String, weight: Double)] = [
        ("Homebrew",  0.15),
        ("PHP 8.2",   0.25),
        ("MariaDB",   0.30),
        ("Dolibarr",  0.30),
    ]

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                // Titre + statut
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(isRunning ? "Installation en cours…" : (failed ? "Échec de l'installation" : "Prêt à installer"))
                            .font(.system(size: 15, weight: .semibold))
                        Text(currentTask)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if isRunning {
                        ProgressView().scaleEffect(0.7)
                    } else if failed {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                            .font(.title2)
                    }
                }

                // Barre de progression
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(failed ? .red : .accentColor)
                    HStack {
                        Text(failed ? "Une erreur est survenue — consultez les logs ci-dessous" :
                             "\(Int(progress * 100))%")
                            .font(.system(size: 11))
                            .foregroundColor(failed ? .red : .secondary)
                        Spacer()
                    }
                }

                // Fenêtre de logs
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(logs.enumerated()), id: \.offset) { i, line in
                                Text(line)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(line.contains("Erreur") ? .red :
                                                     line.hasPrefix("✓") ? .green : .primary)
                                    .id(i)
                            }
                        }
                        .padding(8)
                    }
                    .frame(maxHeight: .infinity)
                    .background(Color(NSColor.textBackgroundColor).opacity(0.5))
                    .cornerRadius(8)
                    .onChange(of: logs.count) { _ in
                        if let last = logs.indices.last {
                            withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                        }
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 20)

            Divider()

            HStack {
                if !isRunning {
                    Button("Retour", action: onBack)
                        .buttonStyle(.bordered)
                        .disabled(isRunning)
                }
                Spacer()
                if failed {
                    Button("Réessayer") { startInstallation() }
                        .buttonStyle(.bordered)
                }
                if !isRunning {
                    Button(action: isRunning ? {} : startInstallation) {
                        Text(failed ? "Recommencer" : "Lancer l'installation")
                            .frame(minWidth: 160)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRunning)
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 14)
        }
    }

    private func log(_ msg: String) {
        DispatchQueue.main.async { logs.append(msg) }
    }

    private func startInstallation() {
        isRunning = true
        failed    = false
        logs      = []
        progress  = 0

        installStep_Homebrew()
    }

    private func advance(by weight: Double, label: String) {
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.4)) {
                progress   = min(progress + weight, 1.0)
                currentTask = label
            }
        }
    }

    private func installStep_Homebrew() {
        currentTask = "Vérification de Homebrew…"
        if manager.isBrewInstalled() {
            log("✓ Homebrew déjà installé")
            advance(by: 0.15, label: "Homebrew OK")
            installStep_PHP()
        } else {
            log("Installation de Homebrew…")
            manager.installHomebrew(onLine: log) { ok in
                if ok {
                    self.advance(by: 0.15, label: "Homebrew installé")
                    self.installStep_PHP()
                } else { self.fail() }
            }
        }
    }

    private func installStep_PHP() {
        currentTask = "Vérification de PHP…"
        if manager.isPhpInstalled() {
            log("✓ PHP \(state.phpVersion) déjà installé")
            advance(by: 0.25, label: "PHP OK")
            installStep_MariaDB()
        } else {
            log("Installation de PHP \(state.phpVersion)…")
            manager.installPhp(onLine: log) { ok in
                if ok {
                    self.advance(by: 0.25, label: "PHP installé")
                    self.installStep_MariaDB()
                } else { self.fail() }
            }
        }
    }

    private func installStep_MariaDB() {
        currentTask = "Vérification de MariaDB…"
        if manager.isMariaDBInstalled() {
            log("✓ MariaDB déjà installé")
            advance(by: 0.30, label: "MariaDB OK")
            installStep_Dolibarr()
        } else {
            log("Installation de MariaDB…")
            manager.installMariaDB(onLine: log) { ok in
                if ok {
                    self.advance(by: 0.30, label: "MariaDB installé")
                    self.installStep_Dolibarr()
                } else { self.fail() }
            }
        }
    }

    private func installStep_Dolibarr() {
        if manager.isDolibarrInstalled() {
            log("✓ Dolibarr déjà présent, mise à jour…")
        }
        manager.installDolibarr(onLine: log) { ok in
            if ok {
                self.advance(by: 0.30, label: "Dolibarr installé")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    AppState.shared.isInstalled = true
                    self.isRunning = false
                    self.onComplete()
                }
            } else { self.fail() }
        }
    }

    private func fail() {
        DispatchQueue.main.async {
            failed    = true
            isRunning = false
            currentTask = "Échec — consultez les logs"
        }
    }
}

// MARK: - Étape 4 : Terminé

struct DoneStepView: View {
    @ObservedObject private var state = AppState.shared
    var onLaunch: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(.green)

            Text("Dolibarr est prêt !")
                .font(.system(size: 22, weight: .semibold))

            VStack(spacing: 6) {
                Text("L'icône Dolibarr apparaît dans votre barre de menu.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                Text("Accédez à Dolibarr via : http://localhost:\(state.dolibarrPort)")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.accentColor)
                    .onTapGesture { NSWorkspace.shared.open(state.dolibarrURL) }
            }
            .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 10) {
                InfoRow(icon: "person.fill",      text: "Identifiants par défaut : admin / admin")
                InfoRow(icon: "exclamationmark.triangle.fill", color: .orange,
                        text: "Changez le mot de passe dès la première connexion")
                InfoRow(icon: "menubar.rectangle", text: "Gérez Dolibarr depuis l'icône dans la barre de menu")
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
            .frame(maxWidth: 380)

            Spacer()

            Button(action: onLaunch) {
                Label("Démarrer Dolibarr", systemImage: "play.fill")
                    .frame(width: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 40)
    }
}

struct InfoRow: View {
    let icon: String
    var color: Color = .accentColor
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 16)
            Text(text)
                .font(.system(size: 12))
        }
    }
}
