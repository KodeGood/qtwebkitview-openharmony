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

import QtCore
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import org.wpewebkit.qtwpe

// A plain Window, not ApplicationWindow: the OHOS platform plugin paints the system window
// background behind the status and navigation bars with the Window colour of the QWindow
// palette, which ApplicationWindow takes from the Controls style instead of the application.
Window {
    id: window

    required property string webkitVersion
    required property string qtVersion

    visible: true
    color: "#000000"
    title: webView.title || "Qt WebKitView"
    palette {
        window: "#2d3035"
        base: "#2d3035"
        button: "#2d3035"
        light: "#3a3e44"
        midlight: "#3a3e44"
        mid: "#45494f"
        dark: "#1d1f23"
        text: "#e8eaed"
        windowText: "#e8eaed"
        buttonText: "#e8eaed"
        highlight: "#6f8dff"
        highlightedText: "#ffffff"
        disabled.text: "#6f747a"
        disabled.windowText: "#6f747a"
        disabled.buttonText: "#6f747a"
    }

    property int pagesLoaded: 0
    property int currentIndex: 0
    property int nextTabId: 1
    // The count keeps the binding live: itemAt() does not notify.
    readonly property Item currentTab: tabRepeater.count > 0 ? tabRepeater.itemAt(Math.min(currentIndex, tabRepeater.count - 1)) : null
    readonly property var webView: currentTab ? currentTab.view : noView
    readonly property bool startPageShown: currentTab ? currentTab.startPageShown : true
    readonly property bool hasPage: webView.url.toString() !== ""

    // The bookmarks, also the shortcuts of the start page.
    readonly property var shortcuts: [
        { title: "Aquarium", badge: "Aq", color: "#1e88e5", url: "https://webglsamples.org/aquarium/aquarium.html" },
        { title: "DuckDuckGo", badge: "D", color: "#de5833", url: "https://duckduckgo.com" },
        { title: "WPE WebKit", badge: "W", color: "#7b3fbf", url: "https://wpewebkit.org" },
        { title: "WebKit", badge: "Wk", color: "#2b8a3e", url: "https://webkit.org" },
        { title: "Big Buck Bunny", badge: "BB", color: "#ff0033", url: "https://www.youtube.com/watch?v=YE7VzlLtp-4" }
    ]

    // The favicons of the bookmarks, by bookmark URL, from visits to their sites.
    property var bookmarkIcons: JSON.parse(settings.bookmarkIcons)

    Settings {
        id: settings
        property string bookmarkIcons: "{}"
    }

    function hostOf(url) {
        let match = /^[a-z][a-z0-9+.-]*:\/\/([^\/:?#]+)/i.exec(url)
        return match ? match[1].toLowerCase().replace(/^www\./, "") : ""
    }

    // Stores the icon of a loaded page for the bookmarks of its site.
    function storeBookmarkIcon(pageUrl, icon) {
        let host = hostOf(pageUrl)
        if (!host || !icon)
            return
        let icons = Object.assign({}, bookmarkIcons)
        let changed = false
        for (let bookmark of shortcuts) {
            if (hostOf(bookmark.url) === host && icons[bookmark.url] !== icon) {
                icons[bookmark.url] = icon
                changed = true
            }
        }
        if (!changed)
            return
        bookmarkIcons = icons
        settings.bookmarkIcons = JSON.stringify(icons)
    }

    // Scrolled to the start, so the host stays visible.
    function showUrl(url) {
        urlField.text = url
        urlField.cursorPosition = 0
    }

    function newTab() {
        tabModel.append({ tabId: nextTabId++ })
        selectTab(tabModel.count - 1)
    }

    // From the tabs page: the new tab's start page fades in over the tabs page.
    function openNewTab() {
        tabModel.append({ tabId: nextTabId++ })
        currentIndex = tabModel.count - 1
        tabArea.raised = true
        newTabAnimation.start()
    }

    function selectTab(index) {
        currentIndex = index
        tabsPage.close()
        urlField.focus = false
        showUrl(startPageShown ? "" : webView.url)
    }

    function tabAreaRect() {
        return tabArea.mapToItem(window.contentItem, 0, 0, tabArea.width, tabArea.height)
    }

    // Grows the tab's card snapshot to the tab area, then shows the tab.
    function openTab(index) {
        let tab = tabRepeater.itemAt(index)
        let from = tabsPage.thumbnailRect(index, window.contentItem)
        if (!tab || !from || tab.thumbnail.toString() === "") {
            selectTab(index)
            return
        }
        tabsPage.hiddenThumbnail = index
        snapshotFlight.fly(tab.thumbnail, from, tabAreaRect(), function() {
            selectTab(index)
            tabsPage.hiddenThumbnail = -1
            // The snapshot covers the tab until the tabs page has faded out, which also gives
            // its view, mapped again, time to show a frame.
        })
    }

    function closeTab(index) {
        tabModel.remove(index)
        if (tabModel.count === 0) {
            newTab()
            return
        }
        if (index < currentIndex || currentIndex >= tabModel.count)
            currentIndex = currentIndex - 1
        showUrl(startPageShown ? "" : webView.url)
    }

    function closeAllTabs() {
        tabModel.clear()
        newTab()
    }

    // Snapshot the current tab for its card, then show the cards.
    function showTabs() {
        urlField.focus = false
        let tab = currentTab
        let shown = tab && tab.grabToImage(function(result) {
            tab.grabResult = result
            tab.thumbnail = result.url
            tabsPage.open()
            // Shrinks the snapshot into the tab's card.
            let to = tabsPage.thumbnailRect(currentIndex, window.contentItem)
            if (!to)
                return
            tabsPage.hiddenThumbnail = currentIndex
            snapshotFlight.fly(tab.thumbnail, tabAreaRect(), to, function() {
                tabsPage.hiddenThumbnail = -1
                snapshotFlight.visible = false
            })
        }, Qt.size(tab.width * Screen.devicePixelRatio / 2, tab.height * Screen.devicePixelRatio / 2))
        if (!shown)
            tabsPage.open()
    }

    function load(text) {
        let input = text.trim()
        if (input.length === 0)
            return
        let url
        if (/^[a-z][a-z0-9+.-]*:/i.test(input))
            url = input
        else if (/\s/.test(input) || !/\./.test(input))
            url = "https://duckduckgo.com/?q=" + encodeURIComponent(input)
        else
            url = "https://" + input
        currentTab.startPageShown = false
        urlField.focus = false
        webView.url = url
        showUrl(url)
        webView.forceActiveFocus()
    }

    Rectangle {
        id: header
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 56
        color: "#000000"

        Rectangle {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            anchors.topMargin: 8
            anchors.bottomMargin: 8
            radius: 10
            color: "#2d3035"
            border.width: urlField.activeFocus ? 1 : 0
            border.color: "#6f8dff"

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 2
                spacing: 4

                TextField {
                    id: urlField
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    background: null
                    color: "#e8eaed"
                    placeholderText: "Search or type URL"
                    placeholderTextColor: "#9aa0a6"
                    font.pixelSize: 17
                    leftPadding: 0
                    selectByMouse: true
                    inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                    onAccepted: window.load(text)
                    onActiveFocusChanged: {
                        if (activeFocus)
                            selectAll()
                        else
                            window.showUrl(window.startPageShown ? "" : webView.url)
                    }
                }
                IconButton {
                    visible: !window.startPageShown && window.hasPage
                    iconName: webView.loading ? "stop" : "reload"
                    iconSize: 20
                    implicitWidth: 40
                    implicitHeight: 40
                    onClicked: webView.loading ? webView.stop() : webView.reload()
                }
            }
        }

        Rectangle {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            height: 2
            width: parent.width * webView.loadProgress / 100
            color: "#6f8dff"
            visible: webView.loading && !window.startPageShown
        }
    }

    Item {
        id: tabArea
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.bottom: footer.top
        // Over the tabs page while a new tab fades in, until the tabs page has faded out.
        property bool raised: false
        z: raised ? 15 : 0

        NumberAnimation {
            id: newTabAnimation
            target: tabArea
            property: "opacity"
            from: 0
            to: 1
            duration: 260
            easing.type: Easing.OutCubic
            onFinished: window.selectTab(window.currentIndex)
        }

        ListModel {
            id: tabModel
            ListElement { tabId: 0 }
        }

        Repeater {
            id: tabRepeater
            model: tabModel

            delegate: Item {
                id: tab
                required property int index

                readonly property bool current: index === window.currentIndex
                property bool startPageShown: true
                readonly property alias view: tabView
                readonly property string displayUrl: tabView.url.toString()
                readonly property string displayTitle: startPageShown || !displayUrl ? "New tab" : (tabView.title || displayUrl)
                readonly property url displayIcon: startPageShown || !displayUrl ? "../images/compass.svg" : tabView.icon
                property url thumbnail
                // Keeps the thumbnail image alive.
                property var grabResult

                anchors.fill: parent
                // A hidden view makes its page hidden, so background tabs do not render.
                visible: current

                WPEView {
                    id: tabView
                    anchors.fill: parent

                    onUrlChanged: {
                        if (tab.current && !urlField.activeFocus && !tab.startPageShown)
                            window.showUrl(url)
                    }
                    onIconChanged: window.storeBookmarkIcon(url.toString(), icon.toString())
                    onLoadingChanged: function(loadRequest) {
                        if (loadRequest.status === WPEView.LoadSucceededStatus)
                            window.pagesLoaded++
                        else if (loadRequest.status === WPEView.LoadFailedStatus)
                            console.warn("Failed to load", loadRequest.url, loadRequest.errorString)
                    }
                }

                StartPage {
                    anchors.fill: parent
                    visible: tab.startPageShown
                    shortcuts: window.shortcuts
                    bookmarkIcons: window.bookmarkIcons
                    webkitVersion: window.webkitVersion
                    qtVersion: window.qtVersion
                    pagesLoaded: window.pagesLoaded
                    onShortcutActivated: function(url) { window.load(url.toString()) }
                }
            }
        }
    }

    Rectangle {
        id: footer
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 52
        color: "#000000"

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8

            IconButton {
                Layout.fillWidth: true
                iconName: "home"
                onClicked: {
                    window.currentTab.startPageShown = true
                    urlField.text = ""
                }
            }
            IconButton {
                Layout.fillWidth: true
                iconName: "bookmark"
                onClicked: bookmarksMenu.open()

                Menu {
                    id: bookmarksMenu
                    y: -height

                    Repeater {
                        model: window.shortcuts
                        MenuItem {
                            required property var modelData
                            text: modelData.title
                            icon.source: window.bookmarkIcons[modelData.url] || ""
                            // The favicon's own colours, not tinted.
                            icon.color: "transparent"
                            onTriggered: window.load(modelData.url)
                        }
                    }
                }
            }
            IconButton {
                Layout.fillWidth: true
                iconName: "search"
                onClicked: {
                    urlField.forceActiveFocus()
                    Qt.inputMethod.show()
                }
            }
            IconButton {
                Layout.fillWidth: true
                iconName: "tabs"
                badge: tabModel.count
                onClicked: window.showTabs()
            }
            IconButton {
                Layout.fillWidth: true
                iconName: "menu"
                onClicked: menu.open()

                Menu {
                    id: menu
                    y: -height
                    x: parent.width - width

                    MenuItem {
                        text: "Back"
                        // From the start page, back returns to the page underneath.
                        enabled: window.startPageShown ? window.hasPage : webView.canGoBack
                        onTriggered: {
                            if (window.startPageShown) {
                                window.currentTab.startPageShown = false
                                window.showUrl(webView.url)
                            } else
                                webView.goBack()
                        }
                    }
                    MenuItem {
                        text: "Forward"
                        enabled: !window.startPageShown && webView.canGoForward
                        onTriggered: webView.goForward()
                    }
                    MenuItem {
                        text: webView.loading ? "Stop" : "Reload"
                        enabled: window.hasPage && !window.startPageShown
                        onTriggered: webView.loading ? webView.stop() : webView.reload()
                    }
                    MenuSeparator { }
                    MenuItem {
                        text: "WPE WebKit " + window.webkitVersion + " · Qt " + window.qtVersion
                        enabled: false
                    }
                }
            }
        }
    }

    TabsPage {
        id: tabsPage
        anchors.fill: parent
        z: 10
        tabs: tabRepeater
        currentIndex: window.currentIndex
        onTabSelected: function(index) { window.openTab(index) }
        onTabClosed: function(index) { window.closeTab(index) }
        onNewTabRequested: window.openNewTab()
        onCloseAllRequested: window.closeAllTabs()
        onDismissed: window.openTab(window.currentIndex)
        onOpacityChanged: {
            if (opacity === 0) {
                tabArea.raised = false
                snapshotFlight.visible = false
            }
        }
    }

    // A tab snapshot flying between the tab area and the tab's card.
    Item {
        id: snapshotFlight
        z: 20
        visible: false
        clip: true

        property var finished

        function fly(source, from, to, finished) {
            animation.stop()
            image.source = source
            x = from.x
            y = from.y
            width = from.width
            height = from.height
            animation.to = to
            snapshotFlight.finished = finished
            visible = true
            animation.start()
        }

        Image {
            id: image
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            verticalAlignment: Image.AlignTop
        }

        ParallelAnimation {
            id: animation
            property rect to
            readonly property int duration: 260

            NumberAnimation { target: snapshotFlight; property: "x"; to: animation.to.x; duration: animation.duration; easing.type: Easing.OutCubic }
            NumberAnimation { target: snapshotFlight; property: "y"; to: animation.to.y; duration: animation.duration; easing.type: Easing.OutCubic }
            NumberAnimation { target: snapshotFlight; property: "width"; to: animation.to.width; duration: animation.duration; easing.type: Easing.OutCubic }
            NumberAnimation { target: snapshotFlight; property: "height"; to: animation.to.height; duration: animation.duration; easing.type: Easing.OutCubic }

            onFinished: {
                if (snapshotFlight.finished)
                    snapshotFlight.finished()
            }
        }
    }

    // Stands in for the web view before the first tab is created.
    QtObject {
        id: noView
        property url url
        property string title
        property bool loading: false
        property int loadProgress: 0
        property bool canGoBack: false
        property bool canGoForward: false
        function stop() { }
        function reload() { }
        function goBack() { }
        function goForward() { }
        function forceActiveFocus() { }
    }
}
