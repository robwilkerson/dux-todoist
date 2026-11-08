// A Process running `secret-tool` that reports when the binary is missing.
//
// A missing binary emits neither `started` nor `exited`, only `runningChanged`
// to false, so `launched` tells a failed launch from a normal exit. Callers'
// own `onStarted` and `onExited` handlers run alongside these.

import Quickshell.Io

Process {
    signal notFound

    readonly property string installHint: "secret-tool isn't installed. Install libsecret-tools (Debian, Ubuntu) or libsecret (Fedora, Arch)."

    property bool launched: false

    onStarted: launched = true
    onRunningChanged: {
        if (running)
            return;
        if (!launched)
            notFound();
        launched = false;
    }
}
