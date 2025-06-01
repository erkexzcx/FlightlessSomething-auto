# FlightlessSomething-auto

FlightlessSomething solution for sched-ext/scx automated schedulers testing, using GitHub runner and GitHub actions.

In short: Turn on Steam Deck, go to desktop mode, start a game with MangoHud, enter a game, simply stay somewhere in-game and leave it. Go to GitHub Actions, press some button and benchmark automatically runs.

# How to setup

Dedicate device for this. Preferrably, install CachyOS (normal or handheld). This project uses handheld device (it's Steam Deck), and default user is `deck` and that's what I am using. Note that it involves using GitHub runner, which by default uses `github-actions` user (comes with the package). Make sure both users are part of `wheel` group and sudoers file (on CachyOS it's `/etc/sudoers.d/10-installer`) contains `%wheel ALL=(ALL:ALL) NOPASSWD: ALL` so it wouldn't ask for `sudo` password.

## Register device as GH runner to the repo

Go to https://github.com/erkexzcx/FlightlessSomething-auto/settings/actions/runners/new and register a new runner. On ArchLinux/CachyOS, you can use [github-actions-bin](https://aur.archlinux.org/packages/github-actions-bin) from the AUR with [these instructions](https://aur.archlinux.org/packages/github-actions-bin#comment-939859). Once registered, it will appear here: https://github.com/erkexzcx/FlightlessSomething-auto/settings/actions/runners

**TIP**: Give meaningful runner name when registering. Also add additional runner label, something like `steam-deck`, so you can later you will have an easy time to extend your setup with additional runner if you decide to add more devices.

## Install required tools

Install these:

* First of all - a game and a mangohud packages. Try to play some game to see if if both game and mangohud overlay is working...
* Install these packages (for Arch Linux and CachyOS): `paru -S yq git dotool cargo`

## Configure MangoHud

Edit `/home/deck/.config/MangoHud/MangoHud.conf` to these contents:

```
legacy_layout=false

background_alpha=0.6
round_corners=0
background_alpha=0.6
background_color=000000

font_size=24
text_color=FFFFFF
position=top-left
toggle_hud=Shift_R+F12
table_columns=3
gpu_text=GPU
gpu_stats
gpu_temp
cpu_text=CPU
cpu_stats
core_load
core_bars
cpu_temp
io_stats
io_read
io_write
vram
vram_color=AD64C1
ram
ram_color=C26693
fps
gpu_name
frame_timing
frametime_color=00FF00
fps_limit_method=late
toggle_fps_limit=Shift_L+F1
fps_limit=0

# Only below should be configured as shown. Above config can be customized as you wish.
output_folder=/tmp/mangohud_logs
log_duration=9999
autostart_log=0
log_interval=0
toggle_logging=Shift_L+F2
```

Now do `mkdir -p /tmp/mangohud_logs` and try to launch your game manually with MangoHud. Do a short recording and find recorded logs in `/tmp/mangohud_logs`. Inspect their name. In my case, Baldurs Gate 3 executable is `FactoryGameSteam-Win64-Shipping.exe`, logs start with `Satisfactory_` so they keyword here is `Satisfactory`. Do "Search in Files" and replace this occurance everywhere in this project's files (as it is hardcoded in multiple places, at least for now).

## Before a test run...

Well, AUR package does not provide an ability to enable `dotool` daemon on boot, so after each boot, you have to issue this: `systemctl --user start dotoold.service` or it wouldn't work.

Additionally, edit `/etc/hosts` and append below line, because duckdns.org playing tricks with DNS and sometimes leads to "host not found" DNS issue...
```
139.162.162.246 flightlesssomething-auto.duckdns.org
```

Lastly, login to flightlesssomething-auto.duckdns.org, extract cookies from your browser's requests (or use cookie editor) and get `mysession` value. Save it to *repository secrets* (https://github.com/erkexzcx/FlightlessSomething-auto/settings/secrets/actions) with a secret named `MYSESSION`.

## Do a test run

When everything is setup, simply start the game with MangoHud and in-game, stay somewhere in an open area, preferrably crowded, so it gives lower FPS and needs more computational power.

Go to https://github.com/erkexzcx/FlightlessSomething-auto/actions, on the left side there would be action named `Benchmark Satisfactory`, click on it and then `Run workflow` button. For the most part it should work.

Now the conditions:
1. Game can be frozen or unfrozen for a startup
2. Game must not be in recording state. If it's in recording state - manually stop with command `echo keydown shift+f2 | dotoolc && sleep 0.2 && echo keyup shift+f2 | dotoolc`. If says permission not available for dotool, prior that issue `sudo chown $USER /tmp/dotool-pipe` and re-try. If game is frozen and in recording state, first you need to unfreze it with `sudo kill -CONT $(pgrep -f 'FactoryGameSteam-Win64-Shipping.exe')`.

## Troubleshooting commands cheat-sheet

```bash
# All commands as regular user...

export GAME_EXEC="FactoryGameSteam-Win64-Shipping.exe"
systemctl --user start dotoold.service
sudo chown $USER /tmp/dotool-pipe

# Resume game
sudo kill -CONT $(pgrep -f "$GAME_EXEC")

# Start/Stop MangoHud recording
echo keydown shift+f2 | dotoolc && sleep 0.3 && echo keyup shift+f2 | dotoolc

# Freeze game
sudo kill -STOP $(pgrep -f "$GAME_EXEC")
```

Also, on each boot, from `deck` user:
```bash
systemctl --user start dotoold.service
```
