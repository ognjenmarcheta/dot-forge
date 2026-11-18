Output vhs/startup-intro.gif

Set Shell "zsh"
Set FontSize 18
Set Width 1280
Set Height 900
Set Padding 24
Set CursorBlink false
Set TypingSpeed 45 ms
Set Theme { "name": "Workspace Intro", "black": "#282c35", "red": "#e76f51", "green": "#7fb069", "yellow": "#e5c07b", "blue": "#61afef", "magenta": "#b7bdf8", "cyan": "#56b6c2", "white": "#cdd6f4", "brightBlack": "#5c6370", "brightRed": "#ff6b6b", "brightGreen": "#98c379", "brightYellow": "#f9e2af", "brightBlue": "#83c5ff", "brightMagenta": "#cba6f7", "brightCyan": "#94e2d5", "brightWhite": "#ffffff", "background": "#282c35", "foreground": "#cdd6f4", "selection": "#45475a", "cursor": "#cdd6f4" }

Require zsh
Require neofetch

Type "cd ~/.config"
Enter
Sleep 400 ms
Type "./scripts/terminal-intro --force"
Enter
Sleep 6 s
