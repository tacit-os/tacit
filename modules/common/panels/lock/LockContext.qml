import qs
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam

Scope {
    id: root

    enum ActionEnum { Unlock, Poweroff, Reboot }

    signal shouldReFocus()
    signal unlocked(targetAction: var)
    signal failed()

    // These properties are in the context and not individual lock surfaces
    // so all surfaces can share the same state.
    property string currentText: ""
    property bool unlockInProgress: false
    property bool showFailure: false
    // PAM could not even be asked (no /etc/pam.d entry, a module that will not load, a
    // context still busy). "Incorrect password" would be a lie, and a disc spinning with no
    // message is a machine nobody can get back into: the surface names this one.
    property bool authUnavailable: false
    // A Shut down, Restart or Sleep the system refused while locked (Session.actionFailed): its label, for the
    // field to say so, since the notification saying it is not drawn under the lock.
    property string refusedAction: ""
    property bool fingerprintsConfigured: false
    // fingerPam erroring completes at once (reader busy, fprintd down), so retrying from its
    // completion handler is a tight loop. Back off, and stop asking after a few.
    property int fingerErrors: 0
    readonly property int fingerErrorLimit: 3
    property real fingerStartedAt: 0
    property var targetAction: LockContext.ActionEnum.Unlock
    property bool alsoInhibitIdle: false

    function resetTargetAction() {
        root.targetAction = LockContext.ActionEnum.Unlock;
    }

    function clearText() {
        root.currentText = "";
    }

    // The typed text and the failure it caused go stale together. An armed power action and a
    // live fingerprint reader do not: a pause must not turn Shut down back into Unlock.
    function forgetAttempt() {
        root.clearText();
        root.showFailure = false;
        root.authUnavailable = false;
        root.refusedAction = "";
        GlobalStates.screenUnlockFailed = false;
    }

    function resetClearTimer() {
        passwordClearTimer.restart();
    }

    function reset() {
        root.resetTargetAction();
        root.unlockInProgress = false;
        // An attempt still in flight would make the next start() fail and hang the field.
        if (pam.active) {
            pam.abort();
        }
        root.fingerErrors = 0;
        stopFingerPam();
        // Last: whatever aborting reported is stale the moment it arrives.
        root.forgetAttempt();
    }

    Timer {
        id: passwordClearTimer
        interval: 10000
        onTriggered: {
            root.forgetAttempt();
        }
    }

    onCurrentTextChanged: {
        if (currentText.length > 0) {
            showFailure = false;
            GlobalStates.screenUnlockFailed = false;
        }
        GlobalStates.screenLockContainsCharacters = currentText.length > 0;
        if (currentText.length > 0) {
            passwordClearTimer.restart();
        } else {
            passwordClearTimer.stop();
        }
    }

    // Nothing typed is not an attempt: PAM counts an empty password as a wrong one toward faillock's lockout (three in a
    // row lock the account for 10 minutes), and an Enter or the disc sent one once the field had emptied itself after 10 s
    function tryUnlock(alsoInhibitIdle = false) {
        if (root.currentText.length === 0) {
            root.shouldReFocus();
            return;
        }
        root.alsoInhibitIdle = alsoInhibitIdle;
        root.authUnavailable = false;
        root.refusedAction = "";
        root.unlockInProgress = true;
        if (!pam.start()) {
            root.unlockInProgress = false;
            root.authUnavailable = true;
        }
    }

    function tryFingerUnlock() {
        if (!root.fingerprintsConfigured)
            return;
        root.fingerStartedAt = Date.now();
        if (!fingerPam.start()) {
            root.noteFingerError();
        }
    }

    // A round someone swiped in (no match, out of tries) or that waited out pam_fprintd's own 30 s
    // for a finger says the reader works: arm it again without counting, or an idle lock loses the
    // reader after a few minutes. Only a round that failed at once counts toward the limit.
    function fingerRoundEnded(result) {
        if (result == PamResult.Failed || result == PamResult.MaxTries || Date.now() - root.fingerStartedAt > 5000) {
            root.fingerErrors = 0;
            fingerRetryTimer.restart();
        } else {
            root.noteFingerError();
        }
    }

    function noteFingerError() {
        if (root.fingerErrors >= root.fingerErrorLimit) {
            // the reader does not answer: no fingerprint icon on the field until the next lock asks fprintd again
            root.fingerprintsConfigured = false;
            return;
        }
        root.fingerErrors++;
        fingerRetryTimer.restart();
    }

    function stopFingerPam() {
        fingerRetryTimer.stop();
        if (fingerPam.active) {
            fingerPam.abort();
        }
    }

    Timer {
        id: fingerRetryTimer
        interval: 2000
        onTriggered: root.tryFingerUnlock()
    }

    // fprintd-list ran once at start: a finger enrolled since, or fprintd that was not up yet, was never seen.
    // Asked again at every lock.
    function checkFingerprints() {
        fingerprintCheckProc.running = true;
    }

    Process {
        id: fingerprintCheckProc
        running: true
        command: ["bash", "-c", "fprintd-list $(whoami)"]
        stdout: StdioCollector {
            id: fingerprintOutputCollector
            onStreamFinished: {
                root.fingerprintsConfigured = fingerprintOutputCollector.text.includes("Fingerprints for user");
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                // console.warn("[LockContext] fprintd-list command exited with error:", exitCode, exitStatus);
                root.fingerprintsConfigured = false;
            }
        }
    }
    
    // fprintd-list answers long after startup, so a lock soon after the shell starts calls
    // tryFingerUnlock() while this is still false and never arms the reader: start from the
    // value instead, but only while the screen is locked.
    onFingerprintsConfiguredChanged: {
        if (root.fingerprintsConfigured && GlobalStates.screenLocked) {
            root.tryFingerUnlock();
        }
    }

    PamContext {
        id: pam

        // pam_unix will ask for a response for the password prompt
        onPamMessage: {
            if (this.responseRequired) {
                this.respond(root.currentText);
            }
        }

        // A PAM error never reaches completed: without this the field stays disabled for good.
        onError: err => {
            root.unlockInProgress = false;
            root.authUnavailable = true;
        }

        // pam_unix won't send any important messages so all we need is the completion status.
        onCompleted: result => {
            if (result == PamResult.Success) {
                root.unlocked(root.targetAction);
                stopFingerPam();
            } else {
                root.clearText();
                root.unlockInProgress = false;
                GlobalStates.screenUnlockFailed = true;
                root.showFailure = true;
            }
        }
    }

    PamContext {
        id: fingerPam

        configDirectory: "pam"
        config: "fprintd.conf"

        // An error also completes (with PamResult.Error), so it is handled here alone: counting it in
        // onError too spent two of the few tries on each one.
        onCompleted: result => {
            if (result == PamResult.Success) {
                root.unlocked(root.targetAction);
                stopFingerPam();
            } else { // error, failed or out of tries: arm the reader again
                root.fingerRoundEnded(result);
            }
        }
    }
}
