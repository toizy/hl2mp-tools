# hl2mp-tools

This is a set of BASH scripts for cleaning Valve Source servers, such as Half-Life 2: Deathmatch, Counter-Strike: Source and others. At the moment, the tools allows:

- Zip and delete .dem files
- Zip and delete log files
- Check free space on disks and notify the user if the space level is too low
- Notify the user about the execution status through the Telegram bot
- Run as a systemd timer hourly, daily, etc.

In the `servers` directory you can see the `template.config` file, which is a template for server settings. Copy it and delete the template, or rename it to `something.config` and fill down variables. After `run.sh` launched without parameters, you will see a menu to select a configuration that you can launch. You can also type `cfg` instead of selecting a menu item to run the systemd timer setup script (you will need to answer a few questions). Also here you can change the timer or disable it.

README and scripts in the process of modification and will be updated (I hope)...
