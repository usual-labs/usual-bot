# Usual Bot: cross-project architecture

## Implemented today

App -> UsualUI + HermesKit + Tailnet; UsualUI -> HermesKit. Xcode project/config own signing and application targets; Swift package manifests own shared module minimums and tests. The Hermes gateway itself isn't here; `Integrations/usual-bot` (a plugin run on the gateway) and `Services/` (Workers) are server-side code built and deployed separately from the app.



Source anchors: `App/UsualBotApp.swift`, `App/SignInPresenters.swift`.
