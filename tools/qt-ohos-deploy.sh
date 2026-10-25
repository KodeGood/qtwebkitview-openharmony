#!/usr/bin/env bash
# Build, package, sign, install and launch a Qt application on an OpenHarmony device.
#
# Usage:
#   qt-ohos-deploy.sh <app-build-dir> <target> [--no-install] [--no-launch]
#
# <app-build-dir> is the application's CMake build directory configured with the qt-cmake of
# the Qt for OpenHarmony build, <target> its qt_add_executable() target.
#
# Qt's HAP template targets HarmonyOS. This script patches the generated project for
# OpenHarmony (runtimeOS, deviceTypes, HarmonyOS-only kits), builds the HAP with the
# npm-based hvigorw, and signs it with the OpenHarmony SDK debug CA.
#
# Required environment:
#   QT_HOST_PATH   host Qt build, providing harmonydeployqt
#   OHOS_SDK_ROOT  OpenHarmony SDK root
#
# hvigorw and its npm packages come from hvigor/ next to this script, the signing material from
# gen-signing-config.sh.
#
# Optional:
#   AUTOSIGN_DIR   signing material          (default: <app-build-dir>/.autosign)
#   PROFILE_KIND   debug | release, for newly generated signing material (default: debug).
#                  Use release on devices without /dev/code_sign (e.g. Volla X23 + Oniro),
#                  where debug profiles fail with "delivery sign profile failed".
#   HDC_TARGET     device connect key from `hdc list targets`, if several are connected
#   HAP_LIBS_EXTRA_DIR
#                  directory tree copied into the HAP's native libs dir (entry/libs/<arch>),
#                  for libraries harmonydeployqt does not deploy, e.g. dlopen'd plugins in
#                  subdirectories
#   HAP_PROJECT_HOOK
#                  executable run with the generated HAP project dir as its argument after
#                  the OpenHarmony patches and before the HAP is built, e.g. to adjust Qt's
#                  generated ArkTS ability

set -Eeuo pipefail

die(){ echo "ERROR: $*" >&2; exit 2; }
say(){ printf "\n==> %s\n" "$*"; }
need(){ command -v "$1" >/dev/null 2>&1 || die "Missing '$1' in PATH"; }

[[ $# -ge 2 ]] || die "Usage: $0 <app-build-dir> <target> [--no-install] [--no-launch]"
BUILD_DIR="$(cd "$1" && pwd)"
TARGET="$2"
shift 2
DO_INSTALL=1
DO_LAUNCH=1
for arg in "$@"; do
  case "$arg" in
    --no-install) DO_INSTALL=0; DO_LAUNCH=0 ;;
    --no-launch)  DO_LAUNCH=0 ;;
    *) die "Unknown option: $arg" ;;
  esac
done

for var in QT_HOST_PATH OHOS_SDK_ROOT; do
  [[ -n "${!var:-}" ]] || die "$var is not set"
done
AUTOSIGN_DIR="${AUTOSIGN_DIR:-$BUILD_DIR/.autosign}"
TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TOOLCHAINS="$OHOS_SDK_ROOT/toolchains"
SETTINGS="$BUILD_DIR/${TARGET}-harmony-deployment-settings.json"
PROJECT="$BUILD_DIR/harmonyos-build"
HAP_DIR="$PROJECT/entry/build/default/outputs/default"
HAP_UNSIGNED="$HAP_DIR/entry-default-unsigned.hap"
HAP_SIGNED="$HAP_DIR/${TARGET}-signed.hap"
# Ability name declared by Qt's template in entry/src/main/module.json5
ABILITY_NAME="QAbility"

export PATH="$TOOLCHAINS:$PATH"
need cmake
need node
need npm
need java
need python3
need hdc

# ---------- 1. Build the application ----------
say "Building $TARGET"
cmake --build "$BUILD_DIR" --target "$TARGET"
[[ -f "$SETTINGS" ]] || die "Missing $SETTINGS (is $BUILD_DIR configured with the OpenHarmony qt-cmake?)"

BUNDLE_NAME="$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["harmonyos-app-bundle-name"])' "$SETTINGS")"
echo "  bundle name: $BUNDLE_NAME"

# ---------- 2. Generate the HAP project ----------
say "Generating HAP project in $PROJECT"
"$QT_HOST_PATH/bin/harmonydeployqt" --input "$SETTINGS" --output "$PROJECT" --no-build

# ---------- 3. Patch the project for OpenHarmony ----------
say "Patching project for OpenHarmony"
sed -i -E \
  -e 's|"compatibleSdkVersion": "[^"]*",|"targetSdkVersion": 23,\n        "compatibleSdkVersion": 23,\n        "compileSdkVersion": 23,|' \
  -e 's|"runtimeOS": "HarmonyOS",|"runtimeOS": "OpenHarmony",|' \
  -e '/%%INSERT_TARGET_SDK_VERSION%%/d' \
  -e '/%%INSERT_COMPILE_SDK_VERSION%%/d' \
  "$PROJECT/build-profile.json5"

# The OpenHarmony SDK has no device-define for "phone".
sed -i -E 's|"deviceTypes": \[[^]]*\],|"deviceTypes": ["default", "tablet"],|' \
  "$PROJECT/entry/src/main/module.json5"

# HarmonyOS-only kits (CoreSpeechKit, FileManagerServiceKit, Penkit, ShareKit,
# StatusBarExtensionKit) do not exist in the OpenHarmony SDK. Qt looks them up by name
# at runtime, so only the features using them (system tray, file icons, trash, pen
# picker, text-to-speech, share) are unavailable.
cat > "$PROJECT/entry/src/main/ets/qability/OhosExportModules.ts" <<'EOF'
// HarmonyOS-only kits are not available in the OpenHarmony SDK.
export function getOhosExportModulesFactories(): object {
  return {};
}
EOF

if [[ -n "${HAP_LIBS_EXTRA_DIR:-}" ]]; then
  [[ -d "$HAP_LIBS_EXTRA_DIR" ]] || die "HAP_LIBS_EXTRA_DIR $HAP_LIBS_EXTRA_DIR is not a directory"
  for LIBS_DIR in "$PROJECT"/entry/libs/*/; do
    echo "  adding $HAP_LIBS_EXTRA_DIR to ${LIBS_DIR#$PROJECT/}"
    cp -a "$HAP_LIBS_EXTRA_DIR"/. "$LIBS_DIR"
  done
fi

if [[ -n "${HAP_PROJECT_HOOK:-}" ]]; then
  [[ -x "$HAP_PROJECT_HOOK" ]] || die "HAP_PROJECT_HOOK $HAP_PROJECT_HOOK is not executable"
  echo "  running $HAP_PROJECT_HOOK"
  "$HAP_PROJECT_HOOK" "$PROJECT"
fi

# ---------- 4. Build the HAP ----------
say "Building HAP with hvigor"
cp -f "$TOOLS_DIR/hvigor/hvigorw" "$TOOLS_DIR/hvigor/package.json" "$TOOLS_DIR/hvigor/package-lock.json" "$PROJECT/"
grep -qs '^@ohos:registry=' "$PROJECT/.npmrc" \
  || echo "@ohos:registry=https://repo.harmonyos.com/npm/" >> "$PROJECT/.npmrc"
if [[ ! -f "$PROJECT/node_modules/@ohos/hvigor/bin/hvigor.js" ]]; then
  # --no-bin-links: rollup-lite (a hvigor dependency) declares a bin file it does not
  # ship, which makes npm fail while linking it.
  (cd "$PROJECT" && npm install --no-audit --no-fund --no-bin-links)
fi
(cd "$PROJECT" && OHOS_BASE_SDK_HOME="$(dirname "$OHOS_SDK_ROOT")" ./hvigorw assembleHap --no-daemon)
[[ -f "$HAP_UNSIGNED" ]] || die "hvigor did not produce $HAP_UNSIGNED"

# ---------- 5. Sign the HAP ----------
CONF_JSON="$AUTOSIGN_DIR/signing-configs.json"
if [[ ! -f "$CONF_JSON" ]]; then
  say "Generating signing material in $AUTOSIGN_DIR (needs the device connected for its UDID)"
  "$TOOLS_DIR/gen-signing-config.sh" "$BUNDLE_NAME" "$AUTOSIGN_DIR" "$TOOLCHAINS"
fi

# Permissions above APL "normal" (e.g. ohos.permission.READ_PASTEBOARD, requested by
# Qt for the clipboard) are rejected at install time unless the profile lists them
# in acls.allowed-acls. Add them and re-sign the profile with the SDK profile key.
PROFILE_JSON="$AUTOSIGN_DIR/profile_unsigned.json"
if python3 -I - "$SETTINGS" "$TOOLCHAINS/lib/PermissionDefinitions.json" "$PROFILE_JSON" <<'EOF'
import json, sys
settings, defs_file, profile_file = sys.argv[1:4]
wanted = {p["name"] for p in json.load(open(settings)).get("permissions", [])}
defs = json.load(open(defs_file))
defs = defs.get("definePermissions", defs)
needed = sorted(d["name"] for d in defs
                if d["name"] in wanted and d.get("availableLevel") != "normal"
                and d.get("provisionEnable"))
profile = json.load(open(profile_file))
acls = [a for a in profile.setdefault("acls", {}).get("allowed-acls", []) if a]
missing = [n for n in needed if n not in acls]
if not missing:
    sys.exit(1)
profile["acls"]["allowed-acls"] = acls + missing
json.dump(profile, open(profile_file, "w"), ensure_ascii=False, indent=2)
print("  adding ACLs: " + ", ".join(missing))
EOF
then
  # Sign with the SDK key matching the profile type (debug or release).
  PROFILE_TYPE="$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["type"])' "$PROFILE_JSON")"
  say "Re-signing $PROFILE_TYPE profile with ACLs"
  java -jar "$TOOLCHAINS/lib/hap-sign-tool.jar" sign-profile \
    -mode localSign -signAlg SHA256withECDSA \
    -keystoreFile "$TOOLCHAINS/lib/OpenHarmony.p12" -keystorePwd 123456 \
    -keyAlias "openharmony application profile $PROFILE_TYPE" -keyPwd 123456 \
    -profileCertFile "$TOOLCHAINS/lib/OpenHarmonyProfile${PROFILE_TYPE^}.pem" \
    -inFile "$PROFILE_JSON" -outFile "$AUTOSIGN_DIR/profile.p7b"
fi

readarray -t SIGN < <(python3 -I -c '
import json, sys
m = json.load(open(sys.argv[1]))[0]["material"]
for k in ("storeFile", "storePassword", "keyAlias", "keyPassword", "certpath", "profile"):
    print(m[k])
' "$CONF_JSON")

say "Signing HAP -> $HAP_SIGNED"
java -jar "$TOOLCHAINS/lib/hap-sign-tool.jar" sign-app \
  -mode localSign -signAlg SHA256withECDSA \
  -keystoreFile "${SIGN[0]}" -keystorePwd "${SIGN[1]}" \
  -keyAlias "${SIGN[2]}" -keyPwd "${SIGN[3]}" \
  -appCertFile "${SIGN[4]}" -profileFile "${SIGN[5]}" \
  -inFile "$HAP_UNSIGNED" -outFile "$HAP_SIGNED"

[[ $DO_INSTALL -eq 1 ]] || { say "Done (not installed): $HAP_SIGNED"; exit 0; }

# ---------- 6. Install ----------
HDC=(hdc)
[[ -n "${HDC_TARGET:-}" ]] && HDC+=(-t "$HDC_TARGET")

install_once () {
  local out rc
  set +e
  out="$("${HDC[@]}" app install "$HAP_SIGNED" 2>&1)"
  rc=$?
  set -e
  echo "$out"
  # hdc can return 0 on install failure
  [[ $rc -eq 0 ]] && ! grep -qiE 'error:|failed to install bundle|install sign info inconsistent' <<<"$out"
}

say "Installing $BUNDLE_NAME"
"${HDC[@]}" shell aa force-stop "$BUNDLE_NAME" >/dev/null 2>&1 || true
if ! install_once; then
  say "Install failed, uninstalling previous $BUNDLE_NAME and retrying"
  "${HDC[@]}" uninstall "$BUNDLE_NAME" >/dev/null 2>&1 || true
  install_once || die "hdc app install failed"
fi

[[ $DO_LAUNCH -eq 1 ]] || { say "Done (installed, not launched)"; exit 0; }

# ---------- 7. Launch ----------
say "Launching $BUNDLE_NAME/$ABILITY_NAME"
"${HDC[@]}" shell aa start -a "$ABILITY_NAME" -b "$BUNDLE_NAME"
say "Done. Logs: hdc hilog | grep -i qt"
