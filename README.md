furrpc
shows what you are playing on your mac in discord. only apps you pick are shown. it shows the game name, how long you have been playing, your mac temperature (when the mac allows reading it) and your mac model and chip.

## install

the best way is to build the app yourself with github actions. it takes about 2 minutes, you do not need xcode or a mac terminal, and you can be sure the app comes from the code you see here.

### option 1: build it yourself with github actions (recommended)

1. press fork at the top of this page to get your own copy of the repo
2. open the actions tab in your fork. if github asks, press "i understand my workflows, go ahead and enable them"
3. click build on the left, press run workflow, then run workflow again
4. wait for the green check mark, click the run, and download furrpc from the artifacts section at the bottom
5. unzip it and drag furrpc.app into your applications folder
6. open it (see the note below if macos complains)

want a proper release page with a download link? push a tag like v1.0 in your fork and github actions will build the app and attach furrpc.zip to a release for you.

### option 2: download a ready made build

1. download furrpc.zip from the releases page and unzip it
2. drag furrpc.app into your applications folder
3. open it (see the note below if macos complains)

### if macos says the app is from an unidentified developer, or that it is damaged

this is because the app is not signed with a paid apple account. it is safe to open, here is the fix:

* right click furrpc.app, choose open, then open again
* if it still says damaged, open terminal and paste this, then press enter: xattr -cr /Applications/furrpc.app

## use

1. open furrpc. a small window appears
2. open a game, come back to furrpc, pick the game in the list and press add
3. press save

the time played is how long the game itself has been open, not how long furrpc has been running.

furrpc starts by itself when you log in. after that it lives in the menu bar as :3 (click it and choose open furrpc to change things). you can turn the menu bar item and start at login off in the window.

## configure

everything here is optional. change what you like.

### settings in the window

* temperature: show or hide your mac temperature. while it is on, the temperature updates every 5 seconds
* menu bar item: show or hide the :3 in the menu bar
* start at login: turn autostart on or off
* show even when the app is in the background: keep the presence up while the app is running, even if you are looking at another window
* discord application id: use your own discord application instead of the default one

### change the name and icon of an app

1. in the window, open the customize an app list and pick one of your added apps
2. type the name you want discord to show, and/or paste an icon url (or an asset name if you use your own discord application)
3. press save

leave a field blank to go back to the default. what you type here wins over games.json, so you can change any game without touching the repo. the boxes show the current default in grey.

from terminal: furrpc set name <bundle id> <name> and furrpc set image <bundle id> <url>. leave the name or url off to reset it.

### show even when the app is in the background

by default furrpc only shows a game while it is the app in front. turn on show even when the app is in the background and the presence stays up for as long as the app is running. if more than one of your apps is running, the one in front wins, otherwise the first one in your list is shown.

### your own discord application

1. make an application at discord.com/developers/applications
2. copy its application id
3. paste it into furrpc (or run furrpc set id)
4. upload your pictures under rich presence, art assets, and use the asset names as image in games.json

### game graphics

games.json in this repo maps an app id to a name and a picture:

    { "com.example.game": { "name": "example game", "image": "https://files.catbox.moe/xxxxxx.png" } }

* the key is the bundle id of the game (run furrpc running to find it)
* name is what discord shows
* image is a link to the picture, or an asset name if you use your own discord application. pictures are hosted on files.catbox.moe
* games with no entry use https://files.catbox.moe/95gjsg.png
* keys starting with _ are ignored

to add a game for everyone, add one block like the one above and open a pull request.

to use your own pictures without changing the repo, put your own games.json here: ~/Library/Application Support/furrpc/games.json
it is read on top of the built in one.

### menu bar look

put a 100x100 menubar.png next to build.sh in your fork and build again. without it the menu bar shows :3

### command line

run this once to get a furrpc command in terminal: ln -s /Applications/furrpc.app/Contents/MacOS/furrpc /usr/local/bin/furrpc

then:

    furrpc running            lists open apps and their ids
    furrpc add                add an app
    furrpc remove             remove an app
    furrpc list               shows added apps
    furrpc set temp on|off
    furrpc set menubar on|off
    furrpc set login on|off
    furrpc set id             use your own discord application
    furrpc set background on|off
    furrpc set name <bundle id> [name]
    furrpc set image <bundle id> [url]
    furrpc status
    furrpc log [lines]        shows the log file path and its last lines

## logging

furrpc writes a log so you can see what it is doing and why a presence is not showing up.

* file: ~/Library/Application Support/furrpc/furrpc.log
* view it in terminal with furrpc log (add a number for more lines, like furrpc log 200)
* it records start up, config changes, when discord connects or disconnects, when a presence is set or cleared, and any errors
* when the file passes 512 kb it is moved to furrpc.log.old and a new one starts, so it never grows forever
* nothing is sent anywhere, the log only stays on your mac

if something is not working, the most common line to look for is "discord ipc socket not found", which means discord is not open.

## build locally (optional)

needs xcode command line tools (xcode-select --install).

    sh build.sh

the app appears in build/furrpc.app.

## how the github actions build works

the workflow lives in .github/workflows/build.yml and runs on a macos machine. it runs when you:

* push to main
* open a pull request
* press run workflow by hand in the actions tab
* push a tag starting with v (this also makes a release with furrpc.zip attached)

it runs build.sh, zips the app, and uploads it as an artifact called furrpc.

license: mit
