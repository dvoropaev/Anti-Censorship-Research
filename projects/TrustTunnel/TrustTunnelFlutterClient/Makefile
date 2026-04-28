.PHONY: gen init release-android ln ci-set-version-suffix aux-setup-android-signing

gen:
	@echo "* Starting code generation... *"
	@dart run build_runner build --delete-conflicting-outputs
	@$(MAKE) -C plugins/vpn_plugin gen
	@echo "* Code generation successful *"

ln:
	@echo "* Generating localizations *"
	@dart run intl_utils:generate

init:
	@echo "* Running flutter clean *"
	@flutter clean
	@echo "* Getting latest dependencies *"
	@flutter pub get
	@echo "* Running build runner *"
	@dart run build_runner build --delete-conflicting-outputs
	@dart pub run intl_utils:generate
	@$(MAKE) -C plugins/vpn_plugin init

.dart_tool/package_config.json: pubspec.yaml pubspec.lock
	@echo "* Resolving dependencies... *"
	@flutter pub get 2>&1 | \
		grep -v 'untranslated message' | \
		grep -v 'To see a detailed report' | \
		grep -v 'untranslated-messages-file' | \
		grep -v 'This will generate' | cat
	@echo "* Dependencies resolved. *"

lib/common/localization/generated/l10n.dart: .dart_tool/package_config.json lib/common/localization/arb/*.arb
	@echo "* Generating localization... *"
	@dart run intl_utils:generate 2>&1 | \
		grep -v 'untranslated message' | \
		grep -v 'untranslated-messages-file' | \
		grep -v 'This will generate' | cat
	@flutter gen-l10n 2>&1 | \
		grep -v 'untranslated message' | \
		grep -v 'untranslated-messages-file' | \
		grep -v 'This will generate' | cat
	@echo "* Localization generated. *"

.dart_tool/build/entrypoint/build.dart: lib/common/localization/generated/l10n.dart
	@echo "* Starting code generation... *"
	@dart run build_runner build --delete-conflicting-outputs
	@$(MAKE) -C plugins/vpn_plugin gen
	@echo "* Code generation successful *"

# ----------------------------
# Android signing helpers
# ----------------------------

aux-setup-android-signing:
	@echo "Enter password for Android keystore (will be used for keystore AND written to android/local.properties):"
	@read -s PASSWORD; echo ""; \
	echo "* Generating android/trusttunnel.keystore (alias: trusttunnel) *"; \
	mkdir -p android; \
	rm -f android/trusttunnel.keystore; \
	keytool -genkeypair -v \
		-keystore android/trusttunnel.keystore \
		-alias trusttunnel \
		-keyalg RSA \
		-keysize 2048 \
		-validity 10500 \
		-sigalg SHA256withRSA \
		-storepass $$PASSWORD \
		-keypass $$PASSWORD; \
	echo "* Updating android/local.properties (preserve other keys; replace signingConfigKey* only) *"; \
	touch android/local.properties; \
	grep -vE '^[[:space:]]*signingConfigKey(Alias|Password|StorePath|StorePassword)[[:space:]]*=' android/local.properties > android/local.properties.tmp || true; \
	mv android/local.properties.tmp android/local.properties; \
	printf "%s\n" \
		"signingConfigKeyAlias=trusttunnel" \
		"signingConfigKeyPassword=$$PASSWORD" \
		"signingConfigKeyStorePath=./trusttunnel.keystore" \
		"signingConfigKeyStorePassword=$$PASSWORD" \
		>> android/local.properties; \
	echo "* Android signing setup done. *"

release-android:
	@echo "* Building Android release (AAB) *"
	@flutter build appbundle --release
	@echo "* Android release build done *"