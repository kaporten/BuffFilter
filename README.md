BuffFilter
==========

WildStar addon for selectively hiding buffs and debuffs.

Source code can be found on [GitHub](https://github.com/kaporten/BuffFilter).

Released versions are published on [Curse](http://www.curse.com/ws-addons/wildstar/221865-bufffilter). Full addon description can be found on Curse as well.

Double addon registration issue?
----------
Due to addon folder renames, you may see BuffFilter registered twice on the Addons list in-game. The addon should still work fine, you just see two entries instead of one. You can fix the double-entry issue this way:

1. Shut down WildStar completely.
1. Uninstall BuffFilter (delete directory "%APPDATA%\NCSOFT\WildStar\addons\BuffFilter", or remove it via Curse Client - you can keep the settings).
1. Start WildStar and log in on any character.
1. Shut down WildStar again, and re-install the addon.

Alternative fix:

1. Shut down WildStar completely.
1. Open file "%APPDATA%\NCSOFT\WildStar\Addons.xml" in a text editor.
1. Search for lines containing "BuffFilter" or "bufffilter". You'll find 2 lines. 
1. Delete the all-lowercase line and save the file.
1. Start WildStar again.
