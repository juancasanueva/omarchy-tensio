import QtQuick
import qs.Commons
import qs.Ui

// 7 Days / 30 Days / All selector shared by the Analysis and Report pages.
ButtonGroup {
    id: selector

    property string rangeKey: '7d'
    signal rangeSelected(string key)

    options: [
        { value: '7d', label: '7 Days' },
        { value: '30d', label: '30 Days' },
        { value: 'all', label: 'All' }
    ]
    value: rangeKey
    foreground: Color.popups.text
    background: 'transparent'
    focusable: false
    onChanged: function (v) { selector.rangeSelected(v) }
}
