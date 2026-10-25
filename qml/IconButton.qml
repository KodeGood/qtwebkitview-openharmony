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

ToolButton {
    id: button

    property string iconName: ""
    // Drawn over the icon, e.g. the tab count.
    property string badge: ""
    property real iconSize: 24

    implicitWidth: 48
    implicitHeight: 48
    opacity: enabled ? 1 : 0.35

    // The control resizes its content item to the button: keep the icon at its size inside it.
    contentItem: Item {
        Image {
            anchors.centerIn: parent
            source: button.iconName ? "../images/" + button.iconName + ".svg" : ""
            // Rasterize the SVG at the device resolution.
            sourceSize: Qt.size(button.iconSize * Screen.devicePixelRatio, button.iconSize * Screen.devicePixelRatio)
            width: button.iconSize
            height: button.iconSize
            opacity: 0.9

            Text {
                anchors.centerIn: parent
                visible: button.badge !== ""
                text: button.badge
                color: "#ffffff"
                font.pixelSize: button.iconSize * 0.42
                font.bold: true
            }
        }
    }

    background: Rectangle {
        implicitWidth: 40
        implicitHeight: 40
        anchors.centerIn: parent
        width: 40
        height: 40
        radius: 20
        color: "#ffffff"
        opacity: button.down ? 0.12 : 0
        Behavior on opacity { NumberAnimation { duration: 120 } }
    }
}
