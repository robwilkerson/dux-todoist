// A Process running `secret-tool` that reports when the binary is missing.
//
// A missing binary emits neither `started` nor `exited`, only `runningChanged`
// to false, so `launched` tells a failed launch from a normal exit. A missing
// binary is the likely cause, not the only one, so the hint hedges. Callers'
// own `onStarted` and `onExited` handlers run alongside these.

import Quickshell.Io

Process {
    signal notFound

    readonly property string installHint: "Couldn't run secret-tool. If it isn't installed, install libsecret-tools (Debian, Ubuntu) or libsecret (Fedora, Arch)."

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
