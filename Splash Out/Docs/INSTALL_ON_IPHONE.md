# Running the app on your iPhone (free Apple account)

You don't need the paid Apple Developer Program for this. You need the Mac, the iPhone, a cable and Xcode.

## First time

1. On the iPhone: Settings > Privacy & Security > Developer Mode > on. The phone restarts. (If you don't see Developer Mode, plug the phone into the Mac and open Xcode first; it appears after that.)
2. Plug the iPhone into the Mac with a cable. Unlock it and tap **Trust** if asked.
3. Open the project in Xcode (`Splash Out.xcodeproj`).
4. At the top of Xcode, next to the Run button, choose your iPhone instead of a Simulator.
5. Click the project (blue icon, top of the left list) > **Signing & Capabilities**. Check "Automatically manage signing" is ticked and the Team is your Personal Team (your Apple ID).
6. Press **Run** (the play button). Xcode builds the app, registers the phone and installs it.
7. The first time, the phone says "Untrusted Developer". Go to Settings > General > VPN & Device Management > your Apple ID > **Trust**. Then open Splash Out.

## Every 7 days

The free account's signing expires after 7 days. When it does, the app won't open (it shows a message that it can't be verified). Fix: plug in, press Run again. Your data stays, as long as you don't delete the app. Xcode installs over the top.

Xcode can't refresh this by itself. Two things help:
- Xcode > Window > Devices and Simulators > tick "Connect via network" for the phone, so you can press Run without the cable (Mac and phone on the same Wi-Fi).
- Third-party refreshers such as AltStore can re-sign automatically in the background. They need an Apple ID login and a helper app on the Mac, so only use one you're comfortable with.

The paid programme (a year at a time) removes the 7-day limit and is also what iCloud sync needs.

## Keep your data safe

- Never delete the app from the phone to "fix" something: deleting it deletes all its data.
- Without iCloud, the data lives only on that phone. Export a backup (More > Settings > Export backup) after each week of real use and save it to Files / OneDrive.
- The iPhone and iPad don't share data until iCloud sync is switched on.
