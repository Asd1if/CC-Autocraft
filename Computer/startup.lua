-- Run from this folder so require("modules.x") works wherever the folder was copied.
shell.setDir(fs.getDir(shell.getRunningProgram()))
shell.run("main.lua")
