# Shell Completions

UpdateBar uses Swift Argument Parser's built-in completion generator.
Default root completions include only the primary workflow commands: `init`,
`scan`, `status`, `check`, `update`, `approvals`, and `help`.

Hidden-but-callable commands are intentionally omitted to keep the day-to-day
surface small. This includes import/export commands, advanced item-management
commands, background/configuration commands, and support commands such as
`guide`, `schema`, `template`, `validate`, and `tui`.

Bash:

```bash
updatebar --generate-completion-script bash > ~/.local/share/bash-completion/completions/updatebar
```

Zsh:

```bash
mkdir -p ~/.zfunc
updatebar --generate-completion-script zsh > ~/.zfunc/_updatebar
```

Then add this to `~/.zshrc` if `~/.zfunc` is not already in `fpath`:

```bash
fpath=(~/.zfunc $fpath)
autoload -Uz compinit
compinit
```

Fish:

```bash
updatebar --generate-completion-script fish > ~/.config/fish/completions/updatebar.fish
```
