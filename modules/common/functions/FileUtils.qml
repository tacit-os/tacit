pragma Singleton
import Quickshell

Singleton {
    id: root

    /**
     * A file: url for a path, each segment encoded so '#', '?' and '%' in a name survive. A string that
     * already has a scheme is returned as it is.
     * @param {string} path
     * @returns {string}
     */
    function fileUrl(path) {
        const s = String(path ?? "");
        if (s === "" || /^[a-z][a-z0-9+.-]*:/i.test(s)) return s;
        return "file://" + s.split("/").map(encodeURIComponent).join("/");
    }

    /**
     * The url Qt's folder model (FolderListModel, 6.12) lists a folder from, or "" where it can't. The model turns
     * the url into a path, then reads that path as a url again, so a #, ? or %XX in a name cuts or changes it: "C#"
     * listed nothing (or "C"), "#2024" the folder above, "My%20Files" "My Files". Given as //<path>, the path is kept
     * as it is (Qt takes "//first" for a host, and stat reads "//tmp" as "/tmp"); its rows' paths then start with
     * "//" too (listedPath). The first name must read as a host for that: under a folder in / named otherwise, "".
     * @param {string} path
     * @returns {string}
     */
    function folderUrl(path) {
        const s = String(path ?? "");
        if (!/[#?]|%[0-9A-Fa-f]{2}/.test(s)) return root.fileUrl(s);
        return /^\/[A-Za-z0-9._-]+\//.test(s) ? "file:///" + root.fileUrl(s).slice("file://".length) : "";
    }

    /**
     * A path from a folder model's row as a plain path: folderUrl's form gives "//tmp/C#/x" for /tmp/C#/x.
     * @param {string} path
     * @returns {string}
     */
    function listedPath(path) {
        const s = String(path ?? "");
        return s.startsWith("//") ? s.slice(1) : s;
    }

    /**
     * Trims the File protocol off the input string
     * @param {string} str
     * @returns {string}
     */
    function trimFileProtocol(str) {
        let s = str;
        if (typeof s !== "string") s = str.toString(); // Convert to string if it's an url or whatever
        return s.startsWith("file://") ? s.slice(7) : s;
    }

    /**
     * Extracts the file name from a file path
     * @param {string} str
     * @returns {string}
     */
    function fileNameForPath(str) {
        if (typeof str !== "string") return "";
        const trimmed = trimFileProtocol(str);
        return trimmed.split(/[\\/]/).pop();
    }

    /**
     * Extracts the folder name from a directory path
     * @param {string} str
     * @returns {string}
     */
    function folderNameForPath(str) {
        if (typeof str !== "string") return "";
        const trimmed = trimFileProtocol(str);
        // Remove trailing slash if present
        const noTrailing = trimmed.endsWith("/") ? trimmed.slice(0, -1) : trimmed;
        if (!noTrailing) return "";
        return noTrailing.split(/[\\/]/).pop();
    }

    /**
     * Removes the file extension from a file path or name
     * @param {string} str
     * @returns {string}
     */
    function trimFileExt(str) {
        if (typeof str !== "string") return "";
        const trimmed = trimFileProtocol(str);
        const lastDot = trimmed.lastIndexOf(".");
        if (lastDot > -1 && lastDot > trimmed.lastIndexOf("/")) {
            return trimmed.slice(0, lastDot);
        }
        return trimmed;
    }

    /**
     * Returns the parent directory of a given file path
     * @param {string} str
     * @returns {string}
     */
    function parentDirectory(str) {
        if (typeof str !== "string") return "";
        const trimmed = trimFileProtocol(str);
        const parts = trimmed.split(/[\\/]/);
        if (parts.length <= 1) return "";
        parts.pop();
        return parts.join("/");
    }
}
