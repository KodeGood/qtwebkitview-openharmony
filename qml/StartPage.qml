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
import QtQuick.Layouts

Item {
    id: page

    property var shortcuts: []
    // Favicons by bookmark URL; the others get a letter tile.
    property var bookmarkIcons: ({})
    property string webkitVersion: ""
    property string qtVersion: ""
    property int pagesLoaded: 0

    signal shortcutActivated(url url)

    // Keeps touches on the page from reaching the web view underneath.
    MouseArea {
        anchors.fill: parent
    }

    Image {
        anchors.fill: parent
        source: "../images/background.png"
        fillMode: Image.PreserveAspectCrop
        verticalAlignment: Image.AlignBottom
        asynchronous: true
    }

    ColumnLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        spacing: 12

        Card {
            id: stats
            property bool hidden: false
            implicitHeight: statsColumn.implicitHeight + 28

            ColumnLayout {
                id: statsColumn
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Image {
                        source: "../images/compass.svg"
                        sourceSize: Qt.size(16 * Screen.devicePixelRatio, 16 * Screen.devicePixelRatio)
                        Layout.preferredWidth: 16
                        Layout.preferredHeight: 16
                        opacity: 0.85
                    }
                    Text {
                        text: "Browser Engine"
                        color: "#e8eaed"
                        font.pixelSize: 14
                        Layout.fillWidth: true
                    }
                    Image {
                        source: stats.hidden ? "../images/eye.svg" : "../images/eye-off.svg"
                        sourceSize: Qt.size(18 * Screen.devicePixelRatio, 18 * Screen.devicePixelRatio)
                        Layout.preferredWidth: 18
                        Layout.preferredHeight: 18
                        opacity: 0.7
                        TapHandler {
                            margin: 12
                            onTapped: stats.hidden = !stats.hidden
                        }
                    }
                }

                Row {
                    id: statsRow
                    Layout.fillWidth: true
                    visible: !stats.hidden
                    Stat { value: page.webkitVersion; label: "WPE WebKit"; color: "#ff7a5c" }
                    Stat { value: page.qtVersion; label: "Qt"; color: "#9b8cff" }
                    Stat { value: page.pagesLoaded; label: "Pages Loaded"; color: "#ffffff" }
                }
            }
        }

        Card {
            implicitHeight: shortcutsFlow.implicitHeight + 20

            Flow {
                id: shortcutsFlow
                anchors.fill: parent
                anchors.margins: 10

                Repeater {
                    model: page.shortcuts

                    Item {
                        required property var modelData
                        // One row, like the draft: narrow labels elide.
                        width: Math.min(76, Math.floor(shortcutsFlow.width / page.shortcuts.length))
                        height: 84

                        Rectangle {
                            id: circle
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 4
                            width: 52
                            height: 52
                            radius: 26
                            color: "#202327"
                            scale: tap.pressed ? 0.92 : 1
                            Behavior on scale { NumberAnimation { duration: 100 } }

                            Image {
                                id: favicon
                                anchors.centerIn: parent
                                width: 26
                                height: 26
                                source: page.bookmarkIcons[modelData.url] || ""
                                visible: status === Image.Ready
                                fillMode: Image.PreserveAspectFit
                                smooth: true
                                mipmap: true
                            }

                            Rectangle {
                                anchors.centerIn: parent
                                width: 26
                                height: 26
                                radius: 6
                                color: modelData.color
                                visible: !favicon.visible

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.badge
                                    color: "#ffffff"
                                    font.pixelSize: 13
                                    font.bold: true
                                }
                            }
                        }

                        Text {
                            anchors.top: circle.bottom
                            anchors.topMargin: 6
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: modelData.title
                            color: "#ffffff"
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }

                        TapHandler {
                            id: tap
                            onTapped: page.shortcutActivated(modelData.url)
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 10
        width: credit.implicitWidth + 24
        height: credit.implicitHeight + 14
        // The look of the cards.
        radius: 12
        color: "#a6343a42"
        border.color: "#1fffffff"
        border.width: 1

        Text {
            id: credit
            anchors.centerIn: parent
            textFormat: Text.StyledText
            text: "Built with <b>Qt</b> and <b>WebKit</b>"
            color: "#ffffff"
            font.pixelSize: 13
        }
    }

    component Card: Rectangle {
        Layout.fillWidth: true
        radius: 12
        color: "#a6343a42"
        border.color: "#1fffffff"
        border.width: 1
    }

    component Stat: Column {
        property alias value: valueText.text
        property alias label: labelText.text
        property alias color: valueText.color

        width: statsRow.width / 3
        spacing: 2

        Text {
            id: valueText
            anchors.horizontalCenter: parent.horizontalCenter
            font.pixelSize: 28
            font.weight: Font.Light
        }
        Text {
            id: labelText
            anchors.horizontalCenter: parent.horizontalCenter
            color: "#e8eaed"
            font.pixelSize: 13
        }
    }
}
