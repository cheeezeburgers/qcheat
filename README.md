# qcheat

![macOS](https://img.shields.io/badge/macOS-supported-brightgreen)
[![ShellCheck](https://github.com/cheeezeburgers/qcheat/actions/workflows/shellcheck.yml/badge.svg)](
  https://github.com/cheeezeburgers/qcheat/actions/workflows/shellcheck.yml
)
[![install test](https://github.com/cheeezeburgers/qcheat/actions/workflows/macos-testing.yml/badge.svg)](https://github.com/cheeezeburgers/qcheat/actions/workflows/macos-testing.yml)

A tiny, fast, local AI cheat sheet for your terminal.

`qcheat` uses Ollama and Qwen2.5-Coder to answer short command-line questions directly in your shell, with Markdown and syntax highlighting rendered by `mdcat`.

```text
qcheat → Ollama → qwen-cheat → mdcat → terminal
```

No API key is required.

After the model and dependencies have been downloaded, queries are processed locally.

## What it is for

`qcheat` is meant for small questions you repeatedly forget:

```bash
qcheat copy a directory
qcheat vim copy current word
qcheat vim delete to end of line
qcheat git create a new branch
qcheat vscode toggle terminal mac
```

It is deliberately optimized for quick answers rather than long conversations.

The assistant focuses on:

* macOS and Linux
* zsh and bash
* Git and GitHub CLI
* Vim
* VS Code

`qcheat` automatically includes the current operating system, shell and CPU architecture with each question.

## Example

```bash
qcheat vim copy current word
```

Output:

```text
yiw

Copies the word under the cursor.
```

## Requirements

Supported operating systems:

* macOS
* Linux

Dependencies:

* Ollama
* mdcat
* Qwen2.5-Coder 3B Instruct

The installer handles these dependencies where possible.

On macOS, Homebrew is required.

## Installation

Clone the repository:

```bash
git clone <your-qcheat-repository>
cd qcheat
```

Run:

```bash
chmod +x install.sh
./install.sh
```

The installer will:

1. detect macOS or Linux
2. check Homebrew on macOS
3. install Ollama if necessary
4. install mdcat if necessary
5. start Ollama if necessary
6. download `qwen2.5-coder:3b-instruct`
7. build the custom `qwen-cheat` model
8. install `qcheat` to `~/.local/bin/qcheat`
9. offer to add `~/.local/bin` to your PATH if necessary
10. optionally add a shorter shell alias

### Preview an installation

```bash
./install.sh --dry-run
```

Dry-run prints the commands and shell configuration blocks it would apply. It does not install dependencies, start services, download or build models, create directories, copy files, or edit shell configuration. Read-only checks still run, including OS detection, dependency versions, and `ollama list`. The PATH and alias prompts remain interactive; accepting them only previews the changes.

On Linux, dry-run skips package metadata queries and assumes the first available supported package manager provides `mdcat`. A real installation checks package availability and may choose a different fallback.

Installer options:

| Option | Description |
| --- | --- |
| `--dry-run` | Preview installation without making changes |
| `-h`, `--help` | Show installer help |
| `-V`, `--version` | Show the project version |

Unknown installer arguments are rejected with exit status 2 before installation begins.

## Usage

```bash
qcheat <question>
```

Examples:

```bash
qcheat copy a file
qcheat find files recursively
qcheat git show staged changes
qcheat vim replace current line
qcheat vscode switch terminal mac
```

You can also pipe a question into it:

```bash
echo "git create a new branch" | qcheat
```

Help:

```bash
qcheat --help
```

Version:

```bash
qcheat --version
```

## Optional short alias

The installer can create a shorter alias such as:

```bash
alias q='qcheat'
```

Then:

```bash
q vim copy word
q git create branch
```

If `q` already appears to be in use, the installer will warn you and ask for a different alias.

You can also add one manually.

For zsh:

```bash
echo "alias q='qcheat'" >> ~/.zshrc
source ~/.zshrc
```

For bash:

```bash
echo "alias q='qcheat'" >> ~/.bashrc
source ~/.bashrc
```

You can use any alias name you prefer:

```bash
alias qc='qcheat'
```

## The custom model

`qcheat` uses a custom Ollama model called:

```text
qwen-cheat
```

It is based on:

```text
qwen2.5-coder:3b-instruct
```

The custom model does not contain separately trained model weights. Its `Modelfile` defines a system prompt and generation parameters tailored for short shell, Git, Vim and VS Code answers.

The source `Modelfile` stays inside this repository. It does not need to be copied or symlinked into `~/.config/ollama`.

The installer builds the model with:

```bash
ollama create qwen-cheat -f Modelfile
```

## Why not AIChat + Qwen3?

The first prototype of qcheat used Qwen3 through AIChat.

Qwen3 normally supports disabling its visible reasoning, which is important for a small command-line utility where questions such as `vim copy word` should return immediately.

Ollama's OpenAI-compatible API documents `reasoning_effort: "none"` as the setting for disabling reasoning.

During development, however, Qwen3 still generated reasoning when accessed through the OpenAI-compatible `/v1/chat/completions` path, even when reasoning was disabled.

The Ollama project tracked this behavior in:

```text
ollama/ollama#17969
```

The native Ollama path correctly supported disabling thinking in the tested setup.

Because qcheat does not need an OpenAI-compatible API layer, the project was simplified to communicate with Ollama directly instead.

We subsequently switched the default model from Qwen3 1.7B to Qwen2.5-Coder 3B Instruct because the coding-oriented 3B model proved substantially more reliable for exact Vim and shell commands while remaining small and fast.

References:

```text
Ollama documentation:
docs/api/openai-compatibility.mdx

Ollama issue:
ollama/ollama#17969

Model:
qwen2.5-coder:3b-instruct
```

## Privacy and offline use

`qcheat` does not require an OpenAI account or API key.

Once Ollama, the model and mdcat have been installed, normal `qcheat` questions are handled locally.

The output is rendered with:

```bash
mdcat --local
```

which prevents mdcat from retrieving remote resources while rendering the answer.

An internet connection is still required for the initial installation and model download.

## Files installed

The qcheat executable:

```text
~/.local/bin/qcheat
```

Ollama stores the downloaded base model and the custom `qwen-cheat` model in its normal model storage.

The installer may optionally add lines to:

```text
~/.zshrc
```

or:

```text
~/.bashrc
```

for `~/.local/bin` and the optional short alias.

## Updating

Pull the latest repository changes:

```bash
git pull
```

Then run the installer again:

```bash
./install.sh
```

This replaces the installed `qcheat` executable and rebuilds the custom model from the current `Modelfile`.

## Uninstall

Remove the command:

```bash
rm ~/.local/bin/qcheat
```

Remove the custom model:

```bash
ollama rm qwen-cheat
```

If you do not use the base model for anything else, you can also remove it:

```bash
ollama rm qwen2.5-coder:3b-instruct
```

If you added an optional alias, remove the corresponding line from `~/.zshrc` or `~/.bashrc`:

```bash
alias q='qcheat'
```

You can also remove the qcheat PATH entry if `~/.local/bin` is not used by any of your other programs.

Ollama and mdcat are deliberately not automatically removed because other applications may depend on them.

## Troubleshooting

### `qcheat: command not found`

Check:

```bash
command -v qcheat
```

If `~/.local/bin` is not on your PATH, add:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

to your shell configuration and open a new shell.

### Ollama is not running

Try:

```bash
ollama serve
```

Then run qcheat again.

### mdcat takes a long time to install on Apple Silicon

Check:

```bash
arch
brew --prefix
```

A native Apple-Silicon setup normally reports:

```text
arm64
/opt/homebrew
```

An old Intel Homebrew installation under `/usr/local` may cause packages to compile from source instead of using Apple-Silicon binary packages.

## License

MIT

qcheat is an independent project and is not affiliated with Ollama, Qwen or mdcat.
