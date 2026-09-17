# Application exclusions

[`ApplicationPolicy.defaults`](../Sources/AppConfiguration/ApplicationPolicy.swift)
is the only list to maintain. Entries use exact, case-sensitive bundle IDs:

- `.ignored`: no monitoring or consent prompt. Users cannot enable the app, even
  through saved preferences or a settings reset.
- `.pausedByDefault`: starts paused but can be enabled. Existing explicit choices
  are preserved.

Apps without an entry use their registered support profile or require safe-trial
consent. Settings shows only applications found on the current Mac.

## Change the defaults

Verify `CFBundleIdentifier` in the installed app’s `Contents/Info.plist`, then edit
`ApplicationPolicy.defaults`. Add a short comment explaining the app’s purpose.
Do not use application names, executable paths, vendor prefixes, or wildcards.

Credential dialogs and utility-only apps are exclusion candidates. Check for notes,
chat, or other writing features before excluding a whole app. Use a default pause
when users should still be able to opt in. Review helpers separately from their
parent apps; a helper may host an editor.

Keep policy checks ahead of text access. `AppRegistry` and `UserPreferences` enforce
exclusions before saved consent or Active settings. Focus changes into an excluded
app must still reach `AnalysisCoordinator` so it clears the previous editor and
its overlays.

Update the policy tests in `SafeTrialPromptControllerTests`. Check that exclusions
win over saved consent and Active settings, optional pauses can be resumed, and
switching back to a writing app restores checking.

## Pause or report an app

In Settings → Applications, choose Paused Until Resumed or Pause Another App….
Personal pauses can be undone; entries under Excluded by TextWarden cannot.

More → Suggest Default Exclusion… opens a GitHub draft with the app name and bundle
ID. Explain why it should be excluded and whether it has writing fields, then review
and submit the report. Nothing is submitted automatically. You can also use the
[exclusion report form](https://github.com/PhilipSchmid/textwarden/issues/new?template=application_exclusion.yml).
