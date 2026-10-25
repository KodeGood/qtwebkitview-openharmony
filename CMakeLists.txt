# Copyright (C) 2026 Jani Hautakangas <jani@kodegood.com>
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) any later version.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA

cmake_minimum_required(VERSION 3.22)
project(qtwebkitview LANGUAGES CXX)

# WebKit for OpenHarmony built with `build-webkit-ohos --qt <qt-ohos-build-dir>`: its dist/
# tree has the WebKit libraries and the org.wpewebkit.qtwpe QML module.
set(WEBKIT_DIST "" CACHE PATH "WebKit for OpenHarmony dist dir (WebKitBuild/OHOS/Release/dist)")
if (NOT EXISTS "${WEBKIT_DIST}/lib/qt6/qml/org/wpewebkit/qtwpe/qmldir")
    message(FATAL_ERROR "WEBKIT_DIST must point at a WebKit for OpenHarmony dist dir built with "
        "`build-webkit-ohos --qt` (no lib/qt6/qml/org/wpewebkit/qtwpe in '${WEBKIT_DIST}').")
endif ()

# Svg: the deployment adds the SVG image plugin only for apps linking the module.
find_package(Qt6 REQUIRED COMPONENTS Quick Svg)
find_library(ABILITY_RUNTIME_LIB NAMES ability_runtime REQUIRED)
qt_standard_project_setup(REQUIRES 6.8)

qt_add_executable(qtwebkitview main.cpp)
# The QML files are in their own directory: it is the QML root path, which the deployment
# scans for imports and copies into the HAP.
qt_add_qml_module(qtwebkitview
    URI QtWebKitView
    QML_FILES
        qml/IconButton.qml
        qml/Main.qml
        qml/StartPage.qml
        qml/TabsPage.qml
    RESOURCES
        images/background.png
        images/bookmark.svg
        images/compass.svg
        images/eye-off.svg
        images/eye.svg
        images/home.svg
        images/menu.svg
        images/plus.svg
        images/reload.svg
        images/search.svg
        images/stop.svg
        images/tabs.svg
)
qt_add_resources(qtwebkitview "config"
    PREFIX /
    FILES fonts.conf
)
target_link_libraries(qtwebkitview PRIVATE Qt6::Quick Qt6::Svg ${ABILITY_RUNTIME_LIB})

# The start page shows the WebKit version. WebKitVersion.h is not self-contained (it needs
# glib), so read its version macros here.
file(STRINGS "${WEBKIT_DIST}/include/wpe-webkit-2.0/wpe/WebKitVersion.h" WEBKIT_VERSION_LINES
    REGEX "#define WEBKIT_(MAJOR|MINOR|MICRO)_VERSION")
foreach (part MAJOR MINOR MICRO)
    string(REGEX REPLACE ".*WEBKIT_${part}_VERSION \\(([0-9]+)\\).*" "\\1" WEBKIT_${part} "${WEBKIT_VERSION_LINES}")
endforeach ()
target_compile_definitions(qtwebkitview PRIVATE
    WEBKIT_VERSION_STRING="${WEBKIT_MAJOR}.${WEBKIT_MINOR}.${WEBKIT_MICRO}")

# The QML plugin links libWPEWebKit, which needs the libraries next to it in dist/lib (glib,
# GStreamer, libsoup). The plugin directories under dist/lib (GIO modules, GStreamer plugins,
# injected bundle) are not packaged by harmonydeployqt; the deploy script adds them.
file(GLOB WEBKIT_LIBS "${WEBKIT_DIST}/lib/*.so")
set_target_properties(qtwebkitview PROPERTIES
    QT_HARMONYOS_APP_BUNDLE_NAME "com.kodegood.qtwebkitview"
    QT_HARMONYOS_APP_NAME "WebKit"
    QT_HARMONYOS_EXTRA_LIBS "${WEBKIT_LIBS}"
    QT_QML_IMPORT_PATH "${WEBKIT_DIST}/lib/qt6/qml"
)
# Flat launcher and app icon; without it the HAP keeps the icon of Qt's package template.
if (EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/images/app-icon.png")
    set_target_properties(qtwebkitview PROPERTIES
        QT_HARMONYOS_APP_ICON "${CMAKE_CURRENT_SOURCE_DIR}/images/app-icon.png")
endif ()
