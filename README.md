# DoliMac

**Application macOS native pour installer et gérer Dolibarr ERP depuis la barre de menu.**

Conçu pour Apple Silicon (M1/M2/M3). Aucune commande à taper — tout se fait depuis une interface graphique.

---

## Fonctionnalités

| | Fonctionnalité | Description |
|---|---|---|
| 🔧 | **Installation guidée** | Assistant visuel : Homebrew → PHP 8.2 → MariaDB → Dolibarr |
| ▶ | **Démarrer / Arrêter** | Contrôle des services depuis l'icône de la barre de menu |
| ↺ | **Redémarrer** | Redémarrage en un clic |
| 🌐 | **Ouvrir Dolibarr** | Lance `http://localhost:8080` dans votre navigateur |
| ⬆ | **Mise à jour** | Télécharge et installe la dernière version automatiquement |
| 💾 | **Sauvegarde BDD** | Export `.sql.gz` horodaté vers le dossier de votre choix |
| 📂 | **Restauration BDD** | Restaure depuis n'importe quel fichier de sauvegarde |
| 📄 | **Journaux** | Accès rapide aux logs PHP, MariaDB et Dolibarr |
| 🗑 | **Désinstallateur** | App dédiée incluse dans le DMG, avec sélection des composants |

---

## Téléchargement (utilisateur final)

> Vous n'avez pas besoin de compiler l'application vous-même.

1. Aller dans [**Releases**](../../releases)
2. Télécharger `DoliMac-macOS.dmg` et `DoliMac-macOS.dmg.sha256`
3. **Vérifier l'intégrité** du fichier (recommandé) :
   ```bash
   shasum -a 256 -c DoliMac-macOS.dmg.sha256
   # Résultat attendu : DoliMac-macOS.dmg: OK
   ```
4. Ouvrir le DMG, glisser **DoliMac** dans `/Applications`
5. Au premier lancement, voir la section [Débloquer l'app](#-débloquer-lapp-non-signée) ci-dessous

---

## ⚠ Débloquer l'app (non signée)

L'app n'est pas signée Apple Developer ID. macOS affichera :

> *"DoliMac" ne peut pas être ouvert car il provient d'un développeur non identifié.*

**Option A — Interface graphique** (recommandée) :

1. **Réglages Système** → **Confidentialité et sécurité**
2. Section **Sécurité** → cliquer **"Ouvrir quand même"**
3. Confirmer dans la boîte de dialogue

**Option B — Terminal** (une seule fois) :

```bash
xattr -cr /Applications/DoliMac.app
```

---

## Accès à Dolibarr

| Paramètre | Valeur |
|---|---|
| URL | `http://localhost:8080` (configurable) |
| Login initial | `admin` |
| Mot de passe | `admin` |

> ⚠️ **Changez le mot de passe administrateur dès la première connexion.**

---

## Prérequis pour compiler

| Prérequis | Version minimale | Vérification |
|---|---|---|
| macOS | 13 Ventura | `sw_vers` |
| Architecture | Apple Silicon (M1/M2/M3) | `uname -m` → `arm64` |
| Xcode Command Line Tools | 15+ | `xcode-select --version` |
| Swift | 5.9+ | `swift --version` |

### Installer les outils

```bash
# Xcode Command Line Tools (si absent)
xcode-select --install

# Vérifier Swift
swift --version
# Attendu : swift-driver version: ... Swift version 5.9.x
```

> Vous n'avez **pas** besoin d'installer Xcode.app complet ni Homebrew pour compiler — le Makefile s'en charge.

---

## Build local (développeur)

### 1. Cloner le projet

```bash
git clone https://github.com/votre-compte/dolimac.git
cd dolimac
```

### 2. (Optionnel) Créer une icône

Placez un PNG 1024×1024 nommé `icon.png` à la racine, puis :

```bash
# Générer le .iconset
mkdir AppIcon.iconset
sips -z 16 16     icon.png --out AppIcon.iconset/icon_16x16.png
sips -z 32 32     icon.png --out AppIcon.iconset/icon_16x16@2x.png
sips -z 32 32     icon.png --out AppIcon.iconset/icon_32x32.png
sips -z 64 64     icon.png --out AppIcon.iconset/icon_32x32@2x.png
sips -z 128 128   icon.png --out AppIcon.iconset/icon_128x128.png
sips -z 256 256   icon.png --out AppIcon.iconset/icon_128x128@2x.png
sips -z 256 256   icon.png --out AppIcon.iconset/icon_256x256.png
sips -z 512 512   icon.png --out AppIcon.iconset/icon_256x256@2x.png
sips -z 512 512   icon.png --out AppIcon.iconset/icon_512x512.png
cp   icon.png     AppIcon.iconset/icon_512x512@2x.png

# Convertir en .icns
iconutil -c icns AppIcon.iconset -o Resources/AppIcon.icns
rm -rf AppIcon.iconset
```

### 3. Compiler le binaire

```bash
make build
# → .build/release/DoliMac
```

### 4. Créer le .app bundle

```bash
make app
# → .build/release/DoliMac.app
```

### 5. Créer le .dmg distribuable

```bash
make dmg
# → dist/DoliMac-macOS.dmg
# → dist/DoliMac-macOS.dmg.sha256
```

Le DMG contient :
- `DoliMac.app` — l'application principale
- `DoliMac Uninstaller.app` — le désinstallateur
- Un lien symbolique vers `/Applications`

### 6. Tester localement

```bash
make run
# Ouvre directement le .app depuis le dossier de build
```

### Toutes les commandes disponibles

```bash
make build   # Compile le binaire Swift (arm64, release)
make app     # Crée le .app bundle
make dmg     # Crée le .dmg + checksum SHA-256
make run     # Lance l'app (développement)
make clean   # Supprime tous les artefacts de build
make help    # Affiche l'aide
```

---

## Intégration continue (GitHub Actions)

La CI compile et distribue DoliMac automatiquement depuis un runner Apple Silicon.

### Déclenchement

| Événement | Comportement |
|---|---|
| Push d'un tag `v*.*.*` | Build → Release GitHub publiée |
| `workflow_dispatch` (manuel) | Build → Release brouillon |

### Publier une nouvelle version

```bash
git tag v1.0.0
git push origin v1.0.0
```

La CI exécute alors les étapes suivantes :

1. Compilation Swift `release` sur `macos-14` (Apple Silicon)
2. Création du `.app` bundle (app + désinstallateur)
3. Création du `.dmg` compressé
4. Calcul du **checksum SHA-256**
5. Upload sur GitHub Releases avec :
   - `DoliMac-macOS.dmg`
   - `DoliMac-macOS.dmg.sha256`
   - Le hash SHA-256 dans les notes de version
6. Job `verify` — re-télécharge le DMG et vérifie son intégrité

### Convention de versionnage

```
v1.0.0       → Release stable
v1.1.0-beta  → Pré-release (marquée automatiquement)
v1.1.0-rc1   → Release candidate
```

### Vérifier l'intégrité d'un DMG téléchargé

```bash
# Méthode 1 : avec le fichier .sha256 (recommandée)
shasum -a 256 -c DoliMac-macOS.dmg.sha256
# Résultat attendu : DoliMac-macOS.dmg: OK

# Méthode 2 : manuellement
shasum -a 256 DoliMac-macOS.dmg
# Comparer avec le hash affiché dans les notes de la Release GitHub
```

---

## Structure du projet

```
dolimac/
├── .github/
│   └── workflows/
│       └── release.yml               # CI : build + release + vérification SHA-256
├── Sources/
│   ├── DoliMac/
│   │   ├── App.swift                 # Point d'entrée, AppDelegate
│   │   ├── AppState.swift            # État global persisté (UserDefaults)
│   │   ├── ServiceManager.swift      # Logique Homebrew / PHP / MariaDB / Dolibarr
│   │   ├── StatusBarController.swift # Icône + menu de la barre de menu
│   │   └── SetupWizardView.swift     # Assistant d'installation (4 étapes)
│   └── DoliMacUninstaller/
│       └── UninstallerApp.swift      # App de désinstallation autonome
├── Resources/
│   ├── Info.plist                    # Configuration du bundle .app
│   └── AppIcon.icns                  # (optionnel, voir Build local)
├── Package.swift                     # Manifest Swift Package Manager
├── Makefile                          # Build .app, .dmg et checksum
└── README.md
```

---

## Stack technique

| Composant | Technologie |
|---|---|
| Interface | SwiftUI + AppKit (`NSStatusItem`) |
| Build | Swift Package Manager |
| CI/CD | GitHub Actions (`macos-14`, Apple Silicon) |
| Distribution | DMG (`hdiutil`) |
| Intégrité | SHA-256 (`shasum`) |
| Gestionnaire de paquets | Homebrew |
| Serveur web | PHP built-in server + LaunchAgent |
| Base de données | MariaDB (Homebrew) |
| Persistance config | `UserDefaults` |

---

## Désinstallation

Utiliser **DoliMac Uninstaller.app** inclus dans le DMG :

1. Ouvrir `DoliMac Uninstaller.app`
2. Cocher les composants à supprimer
   - Les éléments dangereux (base de données, sauvegardes) sont **décochés par défaut**
   - L'espace disque récupéré est estimé pour chaque composant
3. Confirmer — un récapitulatif est affiché avant toute suppression

---

## Licence

MIT — Projet indépendant, non affilié à Dolibarr SAS.
