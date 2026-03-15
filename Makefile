APP_NAME        := DoliMac
UNINSTALLER     := DoliMacUninstaller
BUNDLE_NAME     := $(APP_NAME).app
UNI_BUNDLE      := $(UNINSTALLER).app
BUILD_DIR       := .build/release
APP_BUNDLE      := $(BUILD_DIR)/$(BUNDLE_NAME)
UNI_BUNDLE_PATH := $(BUILD_DIR)/$(UNI_BUNDLE)
DMG_NAME        := DoliMac-macOS.dmg
CHECKSUM_FILE   := DoliMac-macOS.dmg.sha256
DMG_DIR         := dist

.PHONY: all build app dmg checksum verify run clean help

# ─────────────────────────────────────────────────────────────
# Par défaut : tout builder
# ─────────────────────────────────────────────────────────────

all: dmg

# ─────────────────────────────────────────────────────────────
# Compilation Swift (release, arm64)
# ─────────────────────────────────────────────────────────────

build:
	@echo "→ Compilation Swift (release, arm64)…"
	swift build -c release --arch arm64
	@echo "  ✓ Binaires compilés"

# ─────────────────────────────────────────────────────────────
# Création des .app bundles
# ─────────────────────────────────────────────────────────────

app: build icns
	@echo "→ Création du bundle $(BUNDLE_NAME)…"
	@mkdir -p $(APP_BUNDLE)/Contents/{MacOS,Resources}
	cp $(BUILD_DIR)/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
	chmod +x $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
	cp Resources/Info.plist $(APP_BUNDLE)/Contents/Info.plist
	@if [ -f Resources/AppIcon.icns ]; then \
		cp Resources/AppIcon.icns $(APP_BUNDLE)/Contents/Resources/; \
		echo "  ✓ Icône incluse"; \
	else \
		echo "  ⚠ Pas d'icône (Resources/AppIcon.icns manquant — voir README)"; \
	fi
	@echo "  ✓ $(BUNDLE_NAME) prêt"

	@echo "→ Création du bundle $(UNI_BUNDLE)…"
	@mkdir -p $(UNI_BUNDLE_PATH)/Contents/{MacOS,Resources}
	cp $(BUILD_DIR)/$(UNINSTALLER) $(UNI_BUNDLE_PATH)/Contents/MacOS/$(UNINSTALLER)
	chmod +x $(UNI_BUNDLE_PATH)/Contents/MacOS/$(UNINSTALLER)
	@printf '<?xml version="1.0" encoding="UTF-8"?>\n\
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"\n\
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n\
<plist version="1.0"><dict>\n\
  <key>CFBundleIdentifier</key><string>com.dolibarr.DoliMacUninstaller</string>\n\
  <key>CFBundleName</key><string>DoliMac Uninstaller</string>\n\
  <key>CFBundleDisplayName</key><string>DoliMac Uninstaller</string>\n\
  <key>CFBundleExecutable</key><string>$(UNINSTALLER)</string>\n\
  <key>CFBundleShortVersionString</key><string>1.0.0</string>\n\
  <key>CFBundleVersion</key><string>1</string>\n\
  <key>CFBundlePackageType</key><string>APPL</string>\n\
  <key>NSPrincipalClass</key><string>NSApplication</string>\n\
  <key>LSMinimumSystemVersion</key><string>13.0</string>\n\
</dict></plist>\n' > $(UNI_BUNDLE_PATH)/Contents/Info.plist
	@echo "  ✓ $(UNI_BUNDLE) prêt"

# ─────────────────────────────────────────────────────────────
# Création du .dmg + checksum
# ─────────────────────────────────────────────────────────────

dmg: app
	@echo "→ Création du DMG $(DMG_NAME)…"
	@mkdir -p $(DMG_DIR)
	@rm -f $(DMG_DIR)/$(DMG_NAME) $(DMG_DIR)/$(CHECKSUM_FILE)
	@rm -rf /tmp/dmg-staging && mkdir -p /tmp/dmg-staging

	cp -R $(APP_BUNDLE) "/tmp/dmg-staging/$(BUNDLE_NAME)"
	cp -R $(UNI_BUNDLE_PATH) "/tmp/dmg-staging/DoliMac Uninstaller.app"
	ln -s /Applications /tmp/dmg-staging/Applications

	hdiutil create \
		-volname "DoliMac" \
		-srcfolder /tmp/dmg-staging \
		-ov -format UDZO \
		-imagekey zlib-level=9 \
		$(DMG_DIR)/$(DMG_NAME)

	@rm -rf /tmp/dmg-staging
	@echo "  ✓ DMG : $(shell du -sh $(DMG_DIR)/$(DMG_NAME) | cut -f1)"
	@$(MAKE) --no-print-directory checksum

# ─────────────────────────────────────────────────────────────
# Checksum SHA-256
# ─────────────────────────────────────────────────────────────

checksum:
	@echo "→ Calcul du SHA-256…"
	@cd $(DMG_DIR) && shasum -a 256 $(DMG_NAME) > $(CHECKSUM_FILE)
	@echo "  ✓ $(shell cat $(DMG_DIR)/$(CHECKSUM_FILE) | awk '{print $$1}')"
	@echo "  ✓ Fichier : $(DMG_DIR)/$(CHECKSUM_FILE)"

# ─────────────────────────────────────────────────────────────
# Vérification de l'intégrité
# ─────────────────────────────────────────────────────────────

verify:
	@[ -f $(DMG_DIR)/$(DMG_NAME) ]      || (echo "✗ DMG introuvable"      && exit 1)
	@[ -f $(DMG_DIR)/$(CHECKSUM_FILE) ] || (echo "✗ Checksum introuvable" && exit 1)
	@echo "→ Vérification SHA-256…"
	@cd $(DMG_DIR) && shasum -a 256 -c $(CHECKSUM_FILE) \
		&& echo "  ✓ Intégrité OK" \
		|| (echo "  ✗ ÉCHEC — DMG altéré !" && exit 1)

# ─────────────────────────────────────────────────────────────
# Dev
# ─────────────────────────────────────────────────────────────

run: app
	@echo "→ Lancement de $(APP_NAME)…"
	open $(APP_BUNDLE)

# ─────────────────────────────────────────────────────────────
# Nettoyage
# ─────────────────────────────────────────────────────────────

clean:
	@echo "→ Nettoyage…"
	swift package clean
	rm -rf $(DMG_DIR)
	@echo "  ✓ Nettoyé"

# ─────────────────────────────────────────────────────────────
# Génération de l'icône .icns (Pillow uniquement, sans Xcode)
# ─────────────────────────────────────────────────────────────

icns:
	@echo "→ Génération de Resources/AppIcon.icns…"
	@python3 -c "import PIL" 2>/dev/null || (echo "  ✗ Pillow requis : pip3 install Pillow" && exit 1)
	python3 Scripts/make_icns.py


# ─────────────────────────────────────────────────────────────
# Aide
# ─────────────────────────────────────────────────────────────

help:
	@echo ""
	@echo "  DoliMac — Commandes disponibles"
	@echo "  ─────────────────────────────────────────────────────"
	@echo "  make / make dmg   Compile tout + crée DMG + SHA-256"
	@echo "  make build        Compile les binaires Swift seulement"
	@echo "  make app          Crée les .app bundles"
	@echo "  make checksum     Recalcule le SHA-256 du DMG existant"
	@echo "  make verify       Vérifie l'intégrité du DMG"
	@echo "  make run          Lance DoliMac (développement)"
	@echo "  make icns         Génère Resources/AppIcon.icns (via Scripts/make_icns.py)
  make clean        Supprime tous les artefacts"
	@echo ""
	@echo "  Distribution : $(DMG_DIR)/$(DMG_NAME)"
	@echo "  Checksum     : $(DMG_DIR)/$(CHECKSUM_FILE)"
	@echo ""
