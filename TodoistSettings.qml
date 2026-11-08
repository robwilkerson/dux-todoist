import QtQuick
import Quickshell.Io
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Plugins
import "./components"

PluginSettings {
    id: root

    // Required by PluginSettings and injected by nothing; must match plugin.json.
    pluginId: "todoist"

    SliderSetting {
        settingKey: "daysAhead"
        label: "Days to Show"
        description: "1 shows today only. Overdue tasks are always included."
        defaultValue: 1
        minimum: 1
        maximum: 14
        unit: " days"
    }

    // The token goes to the Secret Service via secret-tool, never into plugin
    // settings: ~/.config/dms is often tracked in a dotfiles repo.
    Column {
        id: tokenSection

        width: parent.width
        spacing: Theme.spacingS

        // "unknown" | "saved" | "missing" | "saving" | "error" | "noSecretTool"
        property string tokenState: "unknown"
        property string errorText: ""
        property string pending: ""

        Component.onCompleted: check.running = true

        function save() {
            const token = tokenField.text.trim();
            if (token === "" || store.running)
                return;
            pending = token;
            tokenField.text = "";
            tokenState = "saving";
            store.running = true;
        }

        StyledText {
            text: "API Token"
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Theme.fontWeightMedium
            color: Theme.surfaceText
        }

        StyledText {
            width: parent.width
            wrapMode: Text.WordWrap
            font.pixelSize: Theme.fontSizeSmall
            color: tokenSection.tokenState === "error" || tokenSection.tokenState === "noSecretTool" ? Theme.error : Theme.surfaceVariantText
            text: {
                switch (tokenSection.tokenState) {
                case "saved":
                    return "A token is saved in your keyring. Paste a new one to replace it.";
                case "missing":
                    return "From Todoist: Settings → Integrations → Developer. Stored in your keyring, not in plugin settings.";
                case "saving":
                    return "Saving…";
                case "error":
                    return "Couldn't reach your keyring: " + tokenSection.errorText;
                case "noSecretTool":
                    return check.installHint;
                default:
                    return "Checking your keyring…";
                }
            }
        }

        Row {
            width: parent.width
            spacing: Theme.spacingS

            DTextField {
                id: tokenField
                width: parent.width - saveButton.width - parent.spacing
                placeholderText: "Paste API token"
                echoMode: TextInput.Password
                showPasswordToggle: true
                onAccepted: tokenSection.save()
            }

            DButton {
                id: saveButton
                text: "Save"
                enabled: tokenField.text.trim() !== "" && tokenSection.tokenState !== "saving"
                anchors.verticalCenter: parent.verticalCenter
                onClicked: tokenSection.save()
            }
        }

        // Exit 0 with output means a token exists. The token itself is never
        // shown or kept; only whether one is there.
        SecretTool {
            id: check
            command: ["secret-tool", "lookup", "application", "dux-todoist"]
            stdout: StdioCollector {
                id: checkOut
            }
            stderr: StdioCollector {
                id: checkErr
            }
            onNotFound: tokenSection.tokenState = "noSecretTool"
            onExited: exitCode => {
                const err = checkErr.text.trim();
                if (exitCode === 0 && checkOut.text.trim() !== "") {
                    tokenSection.tokenState = "saved";
                } else if (err !== "") {
                    tokenSection.errorText = err;
                    tokenSection.tokenState = "error";
                } else {
                    tokenSection.tokenState = "missing";
                }
            }
        }

        // secret-tool reads the secret from stdin until EOF, so stdin is closed
        // right after writing rather than sending a trailing newline.
        SecretTool {
            id: store
            command: ["secret-tool", "store", "--label=Todoist API token (Dux)", "application", "dux-todoist"]
            stdinEnabled: true
            stderr: StdioCollector {
                id: storeErr
            }
            // Hand the paste back so a retry after installing doesn't need it again.
            onNotFound: {
                tokenField.text = tokenSection.pending;
                tokenSection.pending = "";
                tokenSection.tokenState = "noSecretTool";
            }
            onStarted: {
                store.write(tokenSection.pending);
                tokenSection.pending = "";
                store.stdinEnabled = false;
            }
            onExited: exitCode => {
                store.stdinEnabled = true;
                if (exitCode === 0) {
                    tokenSection.tokenState = "saved";
                    root.saveValue("tokenSavedAt", Date.now());
                } else {
                    tokenSection.errorText = storeErr.text.trim() || "secret-tool exited " + exitCode;
                    tokenSection.tokenState = "error";
                }
            }
        }
    }
}
