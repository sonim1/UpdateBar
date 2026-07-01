# Shell Completions

UpdateBar uses Swift Argument Parser's built-in completion generator.
Recipe-authoring support commands such as `guide`, `schema`, `template`,
`validate`, and `version` are direct commands but intentionally omitted from
default completions.

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
