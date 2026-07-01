# Shell Completions

UpdateBar uses Swift Argument Parser's built-in completion generator.
Recipe-authoring support commands such as `guide`, `schema`, `template`,
`validate`, and `tui` are intentionally omitted from default completions
to keep the day-to-day command surface small.

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
