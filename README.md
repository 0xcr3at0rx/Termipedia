## Termipedia


Termipedia is basically wikipedia for the terminal
Termipedia is a POSIX shell script for searching Wikipedia without the hassle of opening a web browser because it lives in your terminal. It has fuzzy searching, disambiguation page handling, and is lightweight all out of the box

<details>
<summary><b>Dependencies</b></summary>

<details>
<summary>You almost certainly already have these</summary>

- `less` — pages the article so it doesn't vomit text all over your terminal
- `sed` — replaces spaces with underscores. Yes, that's genuinely all it does here

</details>

<details>
<summary>You'll actually need to go and install these</summary>

| Package | Arch | Debian/Ubuntu | Fedora | macOS (Homebrew) |
|---------|------|---------------|--------|-----------------|
| `curl`  | `curl` | `curl` | `curl` | `curl` |
| `jq`    | `jq` | `jq` | `jq` | `jq` |
| `fzf`   | `fzf` | `fzf` | `fzf` | `fzf` |

</details>
</details>

## Installation

```sh
git clone https://github.com/kantiankant/Termipedia
cd Termipedia
doas/sudo cp termipedia.sh /usr/local/bin/termipedia
```


## Usage

```sh
termipedia <search query>
```
## License

GPL-v3


