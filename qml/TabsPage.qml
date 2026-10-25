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

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

// The open tabs as cards with the snapshot taken when the tab was last left for this page.
Rectangle {
    id: page

    // The Repeater of the tabs: itemAt(index) has displayTitle, displayUrl and thumbnail.
    property Repeater tabs
    property int currentIndex: 0
    readonly property color accent: "#6f8dff"
    // The tab whose card hides its thumbnail while the snapshot flies to or from it.
    property int hiddenThumbnail: -1
    property bool shown: false

    signal tabSelected(int index)
    signal tabClosed(int index)
    signal newTabRequested()
    signal closeAllRequested()
    signal dismissed()

    color: "#000000"
    // Kept in the scene while closed, so the cards are laid out for the snapshot animation.
    opacity: 0
    enabled: shown

    Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

    // The indices of the tabs matching the search text. Recomputed only when the search or the
    // number of tabs changes: a new model array recreates every card, which a page loading in a
    // tab would otherwise do on each title change.
    property var shownTabs: []

    function updateShownTabs() {
        let filter = searchField.text.trim().toLowerCase()
        let result = []
        for (let i = 0; i < tabs.count; ++i) {
            let tab = tabs.itemAt(i)
            if (!tab)
                continue
            if (!filter || tab.displayTitle.toLowerCase().includes(filter) || tab.displayUrl.toLowerCase().includes(filter))
                result.push(i)
        }
        if (JSON.stringify(result) !== JSON.stringify(shownTabs))
            shownTabs = result
    }

    Connections {
        target: page.tabs
        function onCountChanged() { page.updateShownTabs() }
    }

    function open() {
        searchField.text = ""
        updateShownTabs()
        shown = true
        opacity = 1
    }

    function close() {
        shown = false
        opacity = 0
    }

    // The thumbnail of the tab's card in the coordinates of item, scrolled into view.
    function thumbnailRect(tabIndex, item) {
        let position = shownTabs.indexOf(tabIndex)
        if (position < 0)
            return null
        grid.positionViewAtIndex(position, GridView.Contain)
        grid.forceLayout()
        let cell = grid.itemAtIndex(position)
        if (!cell)
            return null
        return cell.thumbnailItem.mapToItem(item, 0, 0, cell.thumbnailItem.width, cell.thumbnailItem.height)
    }

    // Keeps touches on the page from reaching the tabs underneath.
    MouseArea {
        anchors.fill: parent
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 52

            IconButton {
                id: countButton
                anchors.centerIn: parent
                iconName: "tabs"
                badge: page.tabs.count
                onClicked: page.dismissed()
            }
            Rectangle {
                anchors.top: countButton.bottom
                anchors.horizontalCenter: countButton.horizontalCenter
                width: 40
                height: 2
                radius: 1
                color: page.accent
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.leftMargin: 12
            Layout.rightMargin: 12
            Layout.topMargin: 8
            Layout.preferredHeight: 44
            radius: 22
            color: "#1f2226"

            TextField {
                id: searchField
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                background: null
                color: "#e8eaed"
                placeholderText: "Search your tabs"
                placeholderTextColor: "#9aa0a6"
                font.pixelSize: 17
                leftPadding: 0
                inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                onTextChanged: page.updateShownTabs()
            }
        }

        GridView {
            id: grid
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: 12
            Layout.leftMargin: 6
            Layout.rightMargin: 6
            clip: true
            cellWidth: width / 2
            cellHeight: cellWidth * 1.3
            model: page.shownTabs

            delegate: Item {
                id: cell
                required property var modelData
                readonly property int tabIndex: modelData
                readonly property Item tab: page.tabs.itemAt(tabIndex)
                readonly property bool current: tabIndex === page.currentIndex
                readonly property Item thumbnailItem: thumbnailFrame

                width: grid.cellWidth
                height: grid.cellHeight

                Rectangle {
                    id: card
                    anchors.fill: parent
                    anchors.margins: 6
                    radius: 14
                    color: cell.current ? page.accent : "#2d3035"
                    scale: tap.pressed ? 0.97 : 1
                    Behavior on scale { NumberAnimation { duration: 100 } }

                    TapHandler {
                        id: tap
                        onTapped: page.tabSelected(cell.tabIndex)
                    }

                    RowLayout {
                        id: cardHeader
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.leftMargin: 12
                        height: 36
                        spacing: 8

                        Image {
                            Layout.preferredWidth: 18
                            Layout.preferredHeight: 18
                            source: cell.tab ? cell.tab.displayIcon : ""
                            sourceSize: Qt.size(18 * Screen.devicePixelRatio, 18 * Screen.devicePixelRatio)
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            mipmap: true
                            visible: status === Image.Ready
                        }

                        Text {
                            Layout.fillWidth: true
                            text: cell.tab ? cell.tab.displayTitle : ""
                            color: "#ffffff"
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        IconButton {
                            iconName: "stop"
                            iconSize: 18
                            implicitWidth: 36
                            implicitHeight: 36
                            onClicked: page.tabClosed(cell.tabIndex)
                        }
                    }

                    Rectangle {
                        id: thumbnailFrame
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: cardHeader.bottom
                        anchors.bottom: parent.bottom
                        anchors.margins: 4
                        anchors.topMargin: 0
                        radius: 10
                        color: "#16181b"
                        clip: true

                        Image {
                            anchors.fill: parent
                            source: cell.tab ? cell.tab.thumbnail : ""
                            visible: cell.tabIndex !== page.hiddenThumbnail
                            fillMode: Image.PreserveAspectCrop
                            verticalAlignment: Image.AlignTop
                        }
                    }
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 52

            IconButton {
                anchors.centerIn: parent
                iconName: "plus"
                onClicked: page.newTabRequested()
            }
            IconButton {
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                iconName: "menu"
                onClicked: menu.open()

                Menu {
                    id: menu
                    y: -height
                    x: parent.width - width

                    MenuItem {
                        text: "Close all tabs"
                        onTriggered: page.closeAllRequested()
                    }
                }
            }
        }
    }
}
