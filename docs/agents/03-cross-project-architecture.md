# Usual Bot: cross-project architecture

## Implemented today

App -> UsualUI + HermesKit; UsualUI -> HermesKit. Xcode project/config own signing and application targets; Swift package manifests own shared module minimums and tests. No backend gateway implementation is present in this workspace.



Source anchors: `App/UsualBotApp.swift`, `App/SignInPresenters.swift`.
