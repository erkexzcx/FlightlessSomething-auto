# FlightlessSomething-auto

FlightlessSomething solution for sched-ext/scx automated schedulers testing, using GitHub runner and GitHub actions.

README.md todo:
* MangoHud config
* Dotool
* GH runner
* Game always on
* Unattended
* Modify workflow if other game or other setup (e.g. not cachyos)
* Required tools to install
* Requires tools to setup

for my own convenience (copy/paste), this is how I fix game that is frozen or recording due to failed job:
```bash
# as regular user

sudo chown $USER /tmp/dotool-pipe

sudo kill -CONT $(pgrep -f 'Cyberpunk2077.exe') # Resume the game

echo keydown shift+f2 | dotoolc && sleep 0.2 && echo keyup shift+f2 | dotoolc # Start/Stop recording

sudo kill -STOP $(pgrep -f 'Cyberpunk2077.exe') # Pause the game
```
