# Qt WebKitView for OpenHarmony

A Qt Quick (QML) browser that shows WPE WebKit running inside a Qt application on OpenHarmony.
The web content is the `WPEView` item of WebKit's `org.wpewebkit.qtwpe` QML module. The app
starts on its own start page without loading anything.

```qml
import org.wpewebkit.qtwpe

WPEView {
    anchors.fill: parent
    url: "https://wpewebkit.org"
}
```

## Requirements

* The OpenHarmony SDK (API 23).
* Qt 6.12 built for OpenHarmony, with its host Qt, as in
  [Building Qt for HarmonyOS](https://doc.qt.io/qt-6/harmonyos-building.html), which mostly
  applies to OpenHarmony. The differences:
  * Configure needs `-DFEATURE_qdbus=OFF` (after `--`): in a cross build the host Qt provides
    `Qt::DBus` even with `-no-dbus`, and qttools' qdbus then fails configure.
  * Qt's HarmonyOS platform plugin needs a few fixes for OpenHarmony devices (device type
    `default`, window APIs that report error 801 or 2000, vsync, buffer format); without them
    applications abort at startup or show a black window.
  * Qt's packaging targets HarmonyOS and DevEco's hvigor. `tools/qt-ohos-deploy.sh` builds the
    HAP for OpenHarmony instead: it sets `runtimeOS` and `deviceTypes`, removes the
    HarmonyOS-only kits, builds with the npm-based hvigor and signs with the OpenHarmony SDK.
* WPE WebKit for OpenHarmony, built with the Qt/QML plugin. In the WebKit tree:

  ```bash
  export OHOS_SDK_ROOT=<ohos-sdk-root>
  Tools/Scripts/build-webkit-ohos --release --qt <qt-ohos-build-dir>
  ```

  The plugin ends up in `WebKitBuild/OHOS/Release/dist/lib/qt6/qml/org/wpewebkit/qtwpe`.
* `cmake`, `node` and `npm` (for hvigor), a JDK (`java`, `keytool`) and `python3`.

Tell `deploy-qtwebkitview` where these are, in the environment or in a `deploy.env` next to it,
which git ignores:

```bash
cp deploy.env.example deploy.env   # then fill in the paths
```

## Board setup

WebKit runs its Web and Network processes as native child processes, which OpenHarmony only
allows for whitelisted apps. Qt WebKitView is signed with app-identifier `12341235`. Add it to
the whitelist on the device, which keeps the apps already there (this reboots the device):

```bash
tools/prepare-board.sh
```

The identifier goes into the signing profile when the signing material is generated (on the
first deploy into an empty `AUTOSIGN_DIR`); override it with `APP_IDENTIFIER`.

## Build, install and launch

```bash
./deploy-qtwebkitview                                  # HiHope board (debug profile)
PROFILE_KIND=release AUTOSIGN_DIR=$PWD/build/.autosign-release \
  HDC_TARGET=<volla-connect-key> ./deploy-qtwebkitview  # Volla X23 + Oniro (release profile)
```

`deploy-qtwebkitview` configures `build/` with Qt's `qt-cmake` (`-DWEBKIT_DIST=<dist>`) and then
runs `tools/qt-ohos-deploy.sh`, which packages, signs, installs and launches the HAP
(bundle `com.kodegood.qtwebkitview`, ability `QAbility`). `--no-install` and `--no-launch` are
passed through. See the script header for the environment overrides.

The HAP holds:

* the Qt libraries, plugins and QML modules (harmonydeployqt),
* `libWPEWebKit-2.0.so` and the libraries next to it in `dist/lib` (`QT_HARMONYOS_EXTRA_LIBS`),
* `libqtwpe.so` and its `qmldir` (`QT_QML_IMPORT_PATH`),
* WebKit's GIO modules, GStreamer plugins and injected bundle in `libs/arm64/<subdir>`, which
  harmonydeployqt does not deploy (`HAP_LIBS_EXTRA_DIR`).

## How it works

* `main.cpp` sets the WebKit environment of the UI process from the application sandbox dirs,
  before Qt and WebKit start. WebKit's process launcher spawns the Web and
  Network processes, which load the same `libWPEWebKit-2.0.so` and set up their own environment.
* Qt runs `main()` on its own thread (`QtMainThread`), which becomes WebKit's main thread. Qt's
  OpenHarmony event dispatcher is not GLib based, so the QML plugin iterates WebKit's GLib main
  context from the Qt event loop (`WPEQtGLibEventLoop`).
* The window spans the screen under the status and navigation bars. They show the window
  background, which the Qt plugin takes from the application palette (`main.cpp`; this needs a
  plain `Window` root, `ApplicationWindow` reports its style's palette instead). Their light
  content is set in Qt's generated ArkTS ability by `harmonyos-project-hook`, which the deploy
  script passes to `qt-ohos-deploy.sh` as `HAP_PROJECT_HOOK`.
* WebKit renders into `OH_NativeBuffer`s that the plugin imports as EGL images into the Qt Quick
  scene graph, at the window's device pixel ratio.

## Logs

```bash
hdc shell hilog -x | grep -E 'WPEWebKit|qt|Qt'
```
