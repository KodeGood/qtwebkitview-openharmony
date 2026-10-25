/*
 * Copyright (C) 2026 Jani Hautakangas <jani@kodegood.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 */

#include <AbilityKit/ability_runtime/application_context.h>

#include <QFile>
#include <QGuiApplication>
#include <QPalette>
#include <QQmlApplicationEngine>
#include <QStyleHints>

#include <cstdlib>
#include <string>
#include <vector>

namespace {

std::string applicationContextDir(AbilityRuntime_ErrorCode (*getDir)(char*, int32_t, int32_t*))
{
    std::vector<char> buffer(512);
    int32_t written = 0;
    while (true) {
        auto result = getDir(buffer.data(), buffer.size(), &written);
        if (result == ABILITY_RUNTIME_ERROR_CODE_NO_ERROR)
            return std::string(buffer.data());
        if (result != ABILITY_RUNTIME_ERROR_CODE_PARAM_INVALID || buffer.size() >= 64 * 1024)
            return { };
        buffer.resize(buffer.size() * 2);
    }
}

// The UI process environment WebKit expects in the application sandbox, as in webkitview. The
// Web and Network processes get theirs from WebKit's process launcher.
bool setUpWebKitEnvironment()
{
    auto cacheDir = applicationContextDir(OH_AbilityRuntime_ApplicationContextGetCacheDir);
    auto filesDir = applicationContextDir(OH_AbilityRuntime_ApplicationContextGetFilesDir);
    auto bundleCodeDir = applicationContextDir(OH_AbilityRuntime_ApplicationContextGetBundleCodeDir);
    if (cacheDir.empty() || filesDir.empty() || bundleCodeDir.empty())
        return false;

    for (auto* name : { "TMP", "TEMP", "TMPDIR", "XDG_CACHE_HOME", "XDG_RUNTIME_DIR" })
        setenv(name, cacheDir.c_str(), 1);
    for (auto* name : { "FONTCONFIG_PATH", "HOME", "XDG_DATA_HOME", "XDG_DATA_DIRS", "XDG_CONFIG_HOME", "XDG_CONFIG_DIRS" })
        setenv(name, filesDir.c_str(), 1);

    auto libsDir = bundleCodeDir + "/libs/arm64/";
    setenv("GIO_EXTRA_MODULES", (libsDir + "gio/modules/").c_str(), 1);
    setenv("WEBKIT_INJECTED_BUNDLE_PATH", (libsDir + "wpe-webkit-2.0/injected-bundle/").c_str(), 1);
    setenv("GST_PLUGIN_SYSTEM_PATH", (libsDir + "gstreamer-1.0/").c_str(), 1);
    setenv("GST_PLUGIN_PATH", (libsDir + "gstreamer-1.0/").c_str(), 1);
    setenv("GST_REGISTRY", (cacheDir + "/gstreamer-1.0-registry.bin").c_str(), 1);
    setenv("GST_REGISTRY_FORK", "no", 1);
    setenv("SSL_CERT_DIR", "/system/etc/security/certificates", 0);

    // The monitor's /proc/meminfo parser spins on the OHOS format (see OHOS_TODO.md in WebKit).
    setenv("WEBKIT_DISABLE_MEMORY_PRESSURE_MONITOR", "1", 1);

    auto fontsConf = QString::fromStdString(filesDir + "/fonts.conf");
    if (!QFile::exists(fontsConf))
        QFile::copy(QStringLiteral(":/fonts.conf"), fontsConf);
    return true;
}

} // namespace

int main(int argc, char* argv[])
{
    bool hasEnvironment = setUpWebKitEnvironment();

    QGuiApplication app(argc, argv);
    // Where the QML Settings (the bookmark icons) are stored.
    QGuiApplication::setOrganizationName(QStringLiteral("Kodegood"));
    if (!hasEnvironment)
        qWarning("Failed to read the application sandbox dirs, WebKit runs without its environment");

    // The window spans the whole screen under transparent status and navigation bars. The OHOS
    // platform plugin paints the system window background with the Window colour of the QWindow
    // palette, which for a QML Window (Main.qml) is the application palette. Dark mode gives the bars light
    // content on the dark colour of the app's toolbars.
    QGuiApplication::styleHints()->setColorScheme(Qt::ColorScheme::Dark);
    QPalette palette = QGuiApplication::palette();
    palette.setColor(QPalette::Window, QColor(Qt::black));
    QGuiApplication::setPalette(palette);

    QQmlApplicationEngine engine;
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed, &app, [] {
        QCoreApplication::exit(EXIT_FAILURE);
    }, Qt::QueuedConnection);
    engine.setInitialProperties({
        { "webkitVersion", QStringLiteral(WEBKIT_VERSION_STRING) },
        { "qtVersion", QString::fromLatin1(qVersion()) },
    });
    engine.loadFromModule("QtWebKitView", "Main");

    return app.exec();
}
