# Putting the app on your iPhone (free Apple account)

You need: the Mac, your iPhone, a charging cable, and Xcode. No paid Apple account.

## One-off setup

**A. Check Xcode knows your Apple ID**
1. Open Xcode. In the menu bar choose **Xcode > Settings...** (or press Command-comma).
2. Click **Accounts**. You should see your Apple ID listed. If not, click **+** at the bottom left, choose **Apple ID**, and sign in.
3. Close the window.

**B. Open the project**
1. In Finder open `Documents > Test iOS app > Splash Out`.
2. Double-click **Splash Out.xcodeproj**. Xcode opens it.

**C. Connect the phone**
1. Plug the iPhone into the Mac. Unlock it.
2. If the phone asks "Trust This Computer?", tap **Trust** and enter your passcode.
3. In Xcode, the phone appears in the device menu at the very top, in the middle of the toolbar (it says "iPhone 17 Pro" or similar, next to "Splash Out"). Click it and pick your iPhone from the list under "Devices". If it says it is preparing the device, wait a minute.

**D. Turn on Developer Mode (phone)**
1. On the iPhone: **Settings > Privacy & Security**, scroll to the bottom, tap **Developer Mode**, switch it on.
2. The phone restarts. Unlock it and tap **Turn On** when asked, then enter your passcode.
3. (Developer Mode only appears once the phone has been connected to Xcode, so do C first.)

**E. Check signing**
1. In Xcode, click the blue **Splash Out** icon at the top of the left-hand list.
2. In the middle, under TARGETS click **Splash Out**, then the **Signing & Capabilities** tab.
3. Make sure **Automatically manage signing** is ticked and **Team** shows your name followed by "(Personal Team)".
4. Don't change the Bundle Identifier (`com.splashout.Splash-Out`). It is what ties the app to its data. If Xcode says that identifier isn't available, tell Claude before changing anything.

**F. Install**
1. Press the **Run** button (the play triangle at the top left) or press Command-R.
2. Xcode builds the app (a minute or two the first time) and installs it on the phone.
3. On the phone you'll see "Untrusted Developer". Go to **Settings > General > VPN & Device Management**, tap your Apple ID under "Developer App", tap **Trust**, then **Trust** again.
4. Open **Splash Out** from the home screen. It starts empty: no customers.

**G. Load your customers**
1. Get the round file onto the phone: AirDrop it, or save it in Files / OneDrive.
2. In the app: **More > Settings > Import customers only...** (or **Import round data...** if the file has cleaning history too), pick the file and confirm.

## Every 7 days (free account)

The free account's signing runs out after 7 days. When it does, the app won't open ("no longer available" or it just bounces). To renew:
1. Plug the phone in, unlock it, open the project in Xcode.
2. Make sure your iPhone is selected at the top, and press **Run** (Command-R).

It installs over the top, so **your data stays**. Don't delete the app first.

### Renewing without a cable (wireless)

Set up once, with the cable:
1. Plug the iPhone into the Mac, unlock it, and trust the Mac if asked.
2. In Xcode choose **Window > Devices and Simulators** (Shift-Command-2) and click the **Devices** tab.
3. Click your iPhone in the left-hand list.
4. Tick **Connect via network**. A small globe icon appears next to the phone's name once it works.
5. Unplug the cable.

Every 7 days after that, with the Mac and the phone on the **same Wi-Fi** and the phone awake and unlocked:
1. Open the project in Xcode.
2. In the device menu at the top, pick your iPhone. A wireless phone shows a small network icon beside its name. If it's greyed out, unlock the phone and wait a moment.
3. Press **Run** (Command-R).

Or just ask Claude: if the phone is visible on the network, it can build and install the renewal itself, with no Xcode.

If the phone doesn't show up wirelessly, plug it in once, then try again. Wireless needs a recent iOS and a Mac that stays awake.

Nothing in Xcode renews it automatically. Third-party tools such as AltStore can re-sign in the background, but they need your Apple ID and a helper app on the Mac, so only use one you're happy with. The paid Apple Developer Program (a year at a time) removes the 7-day limit.

## What keeps and what loses your data

| What happens | Data |
|---|---|
| Press Run again in Xcode (re-sign, or a new build of the app) | Kept |
| An app update from the App Store or TestFlight later | Kept |
| Phone restart, iOS update | Kept |
| Delete the app, then install again | **Gone** (starts empty) |
| Install on a different phone or the iPad | Starts empty (no sync until iCloud is on) |
| Change the Bundle Identifier or Team | Counts as a different app: **starts empty** |

Safety nets built in:
- Before the database is opened, the app copies it into a "Store snapshots" folder whenever its version changes, and at least weekly. The newest four are kept. If an update ever changed the database in a way that couldn't be converted, the data from just before is still there.
- Importing or clearing history first saves a JSON backup of the current data.
- Both live in the Files app: **Files > On My iPhone > Splash Out > Backups**.
- Export a backup yourself (**More > Settings > Export backup**) after each week of real use and save it in OneDrive. That's the one that survives losing the phone.

Before ever changing Apple team (for example when you join the paid programme), export a backup first, and import it afterwards.
