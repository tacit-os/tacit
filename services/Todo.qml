pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import Quickshell;
import Quickshell.Io;
import QtQuick;

/**
 * Simple to-do list manager.
 * Each item is an object with "content" and "done" properties.
 */
Singleton {
    id: root
    property var filePath: Directories.todoPath
    property var list: []
    // A file that did not parse or could not be read still holds the items: it is never written
    // over, or the first task added after a crash mid-write would replace the whole list with itself.
    property bool broken: false

    function save() {
        if (root.broken) {
            console.log("[To Do] Not saving: " + root.filePath + " could not be read")
            return
        }
        todoFileView.setText(JSON.stringify(root.list))
    }
    
    // While the file cannot be read the list stays what it is (empty) and nothing is changed: a task added then showed
    // in the list and was never written. The tabs that edit it say so (Todo.broken).
    function addItem(item) {
        if (root.broken)
            return
        list.push(item)
        // Reassign to trigger onListChanged
        root.list = list.slice(0)
        save()
    }

    function addTask(desc) {
        const item = {
            "content": desc,
            "done": false,
        }
        addItem(item)
    }

    function markDone(index) {
        if (!root.broken && index >= 0 && index < list.length) {
            list[index].done = true
            // Reassign to trigger onListChanged
            root.list = list.slice(0)
            save()
        }
    }

    function markUnfinished(index) {
        if (!root.broken && index >= 0 && index < list.length) {
            list[index].done = false
            // Reassign to trigger onListChanged
            root.list = list.slice(0)
            save()
        }
    }

    function deleteItem(index) {
        if (!root.broken && index >= 0 && index < list.length) {
            list.splice(index, 1)
            // Reassign to trigger onListChanged
            root.list = list.slice(0)
            save()
        }
    }

    function refresh() {
        todoFileView.reload()
    }

    Component.onCompleted: {
        refresh()
    }

    FileView {
        id: todoFileView
        path: Qt.resolvedUrl(root.filePath)
        onLoaded: {
            const fileContents = todoFileView.text()
            try {
                // an empty file (cut short by a crash or a power cut) is an empty list, as Notes has it
                const parsed = fileContents.trim() === "" ? [] : JSON.parse(fileContents)
                if (Array.isArray(parsed)) {
                    root.list = parsed
                    root.broken = false
                    console.log("[To Do] File loaded")
                } else {
                    root.broken = true
                    console.log("[To Do] The file is not a list; keeping the items in memory")
                }
            } catch (e) {
                root.broken = true
                console.log("[To Do] Cannot read the file, keeping the items in memory: " + e)
            }
        }
        onLoadFailed: (error) => {
            if(error == FileViewError.FileNotFound) {
                console.log("[To Do] File not found, creating new file.")
                root.list = []
                todoFileView.setText(JSON.stringify(root.list))
            } else {
                root.broken = true
                console.log("[To Do] Error loading file, keeping the items in memory: " + error)
            }
        }
    }
}

