import QtQuick
import qs.Commons

// Rounded surface used for every grouped block in the panel.
Rectangle {
    radius: Math.max(8, Style.cornerRadius)
    color: Util.alpha(Color.popups.text, 0.06)
    border.width: 1
    border.color: Util.alpha(Color.popups.text, 0.08)
}
