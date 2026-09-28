<p align="center">
  <img src="https://files.catbox.moe/99cbih.png" width="100" alt="furrpc logo">
</p>

<h1 align="center">furrpc</h1>

<p align="center">finds the process, matches it to an image, and sends it to your discord</p>

<p align="center">simple macos discord rpc utility for apps. :3</p>

---

shows what you are playing on your mac in discord. only apps you pick are shown.

it shows:

* the game name
* how long the game has been open
* your mac temperature with one decimal (like `45.3°c`), updated every 5 seconds (when the mac allows reading it)
* your mac model and chip, like `macbook pro 14' - apple m5` (you can show the model id, like `mac17,2`, instead)

**jump to:** [install](#install) · [first launch](#first-launch-macos-blocks-the-app) · [setup](#setup) · [use](#use) · [updates](#updates) · [configure](#configure) · [games.json](#gamesjson) · [command line](#command-line) · [logging](#logging) · [uninstall](#uninstall) · [license](#license)

---

## install

furrpc is built with github actions, and that is the only way to build it. you do not need xcode or any developer tools, and it takes about 2 minutes. because you build it in your own fork, you know the app comes from the code in this repo.

1. press **fork** at the top of this page to get your own copy
2. open the **actions** tab in your fork. if github asks, press **i understand my workflows, go ahead and enable them**
3. click **build** on the left, press **run workflow**, then **run workflow** again
4. wait for the green check mark, click the run, and download **furrpc** from the **artifacts** section at the bottom (you need to be logged in to github)
5. unzip it. inside is `furrpc.zip`, unzip that too to get `furrpc.app`
6. drag `furrpc.app` into your **applications** folder

---

## first launch: macos blocks the app

macos may say the app is from an unidentified developer, or that it is damaged. this is because the app is not signed with a paid apple account. it is safe to open. pick one of these fixes:

### fix 1: privacy and security in settings (easiest, no terminal)

1. try to open furrpc once, then press **done** (or **cancel**) on the warning
2. open **system settings**, go to **privacy & security**
3. scroll down to the **security** section
4. next to "furrpc was blocked" press **open anyway**, then confirm with your password or touch id

### fix 2: right click

right click `furrpc.app`, choose **open**, then **open** again. (newer macos versions may not show this option, use fix 1 instead.)

### fix 3: terminal (if it still says damaged)

this removes the quarantine flag that macos puts on downloaded files. it may need admin rights, so it starts with `sudo`. it will ask for your password:

```sh
sudo xattr -cr /Applications/furrpc.app
```

---

## setup

on first launch furrpc opens its window on the **setup** tab, which has the same steps as below. you only do this once, and everything can be changed later.

### 1. create a discord application

1. keep the discord desktop app open. furrpc talks to it on your mac
2. open [discord.com/developers/applications](https://discord.com/developers/applications) and press **new application**
3. give it a name and create it. discord shows this name as what you are playing

### 2. get the client id

1. on the application page open **general information**
2. copy the **application id**. this long number is your client id
3. in furrpc open the **settings** tab and paste it into **default client id**. every app without its own client id uses it
4. an app can have its own client id (and so its own name in discord): press **edit** on its row in the **apps** tab

### 3. upload rich presence assets

1. in your discord application open **rich presence**, then **art assets**
2. upload your pictures. the name of each asset is what you use as the image in furrpc. new assets can take a few minutes to show up in discord

### 4. add an image url or asset name

for every app you can set an **image**. use one of these:

* an asset name from step 3, like `my_game`
* a full image url that starts with `https://`, like `https://files.catbox.moe/xxxxxx.png`

leave it blank to use the default image.

### 5. add your apps

1. open the app or game you want to show
2. in furrpc open the **apps** tab, pick it in the list and press **add running app**. or press **add by bundle id** and type the id yourself, like `com.example.game`
3. press **edit** on its row to set the name, client id and image. blank means default
4. use the checkbox on a row to turn an app off without removing it, and **remove** to delete it

### 6. save

press **save** at the bottom right. that is it.

---

## use

the window has three tabs: **setup** (the steps above), **apps** (a table where every app has its own on/off checkbox, edit and remove) and **settings**. changes apply when you press **save**.

the time played is how long the game itself has been open, not how long furrpc has been running.

furrpc starts by itself when you log in. after that it lives in the menu bar as `:3`. click it and choose **open furrpc** to change things. you can turn the menu bar item and start at login off in the settings tab.

---

## updates

to update, run the **build** workflow in your fork again (sync your fork first if the original repo has changes), download the new `furrpc.app` and replace the one in **applications**. your settings and your own `games.json` stay where they are, so nothing is lost.

* your own changes always win: what you set in the **apps** tab is read on top of your local `games.json` (see below)
* furrpc never downloads `games.json` or anything else by itself

---

## configure

everything here is optional. change what you like.

### settings in the window

| setting | what it does |
| --- | --- |
| apps table | the list of apps (bundle ids). each row has an on/off checkbox, **edit** (name, client id, image) and **remove** |
| default client id | the discord application id used by every app without its own client id |
| show temperature | show or hide your mac temperature, updated every 5 seconds while on |
| menu bar item | show or hide the `:3` in the menu bar |
| start at login | turn autostart on or off |
| show even when the app is in the background | keep the presence up while the app is running, even if you are looking at another window |
| show mac name instead of model id | on shows `macbook pro 14'`, off shows the model id like `mac17,2`. the chip is shown either way |

### show even when the app is in the background

by default furrpc only shows a game while it is the app in front. turn on **show even when the app is in the background** and the presence stays up for as long as the app is running. (for finder itll show your mac uptime, but why would you?)

if more than one of your apps is running, the one in front wins, otherwise the first one in your list is shown.

```sh
furrpc set background on
```

### your own discord application

follow [setup](#setup) to make an application, copy its client id and upload your assets. from the terminal:

```sh
furrpc set id your_id_here
furrpc set appid com.example.game another_id_here
```

if a picture does not show up, check the asset name or url, check your local `games.json` for a missing comma or quote, and look at the log:

```sh
furrpc log
```

---

## games.json

`games.json` is local only. the one inside the app (and in this repo) is just an example that shows the format. furrpc never downloads or syncs it. if you want to keep your app data in a file, make your own copy:

```sh
mkdir -p ~/Library/Application\ Support/furrpc
cp /Applications/furrpc.app/Contents/Resources/games.json ~/Library/Application\ Support/furrpc/games.json
```

then edit `~/Library/Application Support/furrpc/games.json`. every key is a bundle id and every field is optional:

```json
{
  "com.example.game": {
    "name": "my cool game",
    "image": "my_asset_name_or_https_url",
    "client_id": "123456789012345678"
  }
}
```

* keys that start with `_` are ignored (the example uses one)
* it only fills in blanks: it does not add apps, add them in the **apps** tab
* what you set in the **apps** tab wins over this file, and this file wins over the defaults
* press **save** (or run any `furrpc` change) to make furrpc read it again

---

## command line

optional. run this once to get a `furrpc` command in terminal. it writes to a system folder, so it starts with `sudo` and will ask for your password:

```sh
sudo mkdir -p /usr/local/bin
sudo ln -s /Applications/furrpc.app/Contents/MacOS/furrpc /usr/local/bin/furrpc
```

then use it:

```sh
furrpc running                       # lists open apps and their ids
furrpc add com.example.game          # add an app
furrpc remove com.example.game       # remove an app
furrpc list                          # shows added apps
furrpc set temp on                   # or off
furrpc set menubar on                # or off
furrpc set login on                  # or off
furrpc set background on             # or off
furrpc set macname on                # or off (off shows the model id like mac17,2)
furrpc set id 123456789012345678     # use your own discord application
furrpc enable com.example.game       # turn an app on
furrpc disable com.example.game      # turn an app off, keep it in the list
furrpc set name com.example.game "my cool game"
furrpc set image com.example.game https://files.catbox.moe/xxxxxx.png
furrpc set appid com.example.game 123456789012345678   # one app, its own client id
furrpc status                        # shows all settings
furrpc log 100                       # shows the log path and its last 100 lines
```

---

## logging

furrpc writes a log so you can see what it is doing and why a presence is not showing up.

```
~/Library/Application Support/furrpc/furrpc.log
```

view it in terminal (add a number for more lines):

```sh
furrpc log
furrpc log 200
```

* it records start up, config changes, which games.json files were read, when discord connects or disconnects, when a presence is set or cleared, and any errors
* when the file passes 512 kb it is moved to `furrpc.log.old` and a new one starts, so it never grows forever
* the log only stays on your mac. furrpc downloads nothing and sends nothing about you anywhere except the presence it hands to your own discord app

if something is not working, look for **discord ipc socket not found** in the log. it means discord is not open.

---

## uninstall

this removes everything furrpc puts on your mac. paste the commands into terminal. `-f` means it is fine if something is already gone.

### what furrpc creates

| what | where |
| --- | --- |
| the app | `/Applications/furrpc.app` |
| the command line symlink (only if you made it) | `/usr/local/bin/furrpc` |
| settings | `~/Library/Application Support/furrpc/config.json` |
| logs | `~/Library/Application Support/furrpc/furrpc.log` and `furrpc.log.old` |
| your own `games.json` (only if you made it) | `~/Library/Application Support/furrpc/games.json` |
| start at login item | a login item in system settings |
| macos leftovers (may exist) | `~/Library/Preferences/com.furrpc.app.plist`, `~/Library/Saved Application State/com.furrpc.app.savedState`, `~/Library/Caches/com.furrpc.app` |

### steps

1. turn off start at login. untick **start at login** in the settings tab and press **save**, or run `furrpc set login off`. you can also remove furrpc in **system settings**, **general**, **login items & extensions**
2. quit furrpc: click `:3` in the menu bar and choose **quit furrpc**, or run:

```sh
osascript -e 'quit app "furrpc"'
```

3. delete the app:

```sh
rm -rf /Applications/furrpc.app
```

4. delete the command line symlink (skip if you never made it):

```sh
sudo rm -f /usr/local/bin/furrpc
```

5. delete the settings, the logs and your local `games.json` (copy `games.json` somewhere first if you want to keep it):

```sh
rm -rf "$HOME/Library/Application Support/furrpc"
```

6. delete the macos leftovers:

```sh
rm -rf "$HOME/Library/Preferences/com.furrpc.app.plist" "$HOME/Library/Saved Application State/com.furrpc.app.savedState" "$HOME/Library/Caches/com.furrpc.app"
```

7. check that it is all gone. every line should say **no such file or directory**:

```sh
ls /Applications/furrpc.app /usr/local/bin/furrpc "$HOME/Library/Application Support/furrpc"
```

also delete the downloaded `furrpc.zip` and `furrpc.app` from your downloads folder. your discord application in the developer portal is yours, delete it there if you do not need it. once furrpc is quit, the presence disappears from discord by itself.

---

## license

mit