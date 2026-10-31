# 1Password for Steam Deck

Run the 1Password desktop app and CLI on SteamOS as a [systemd system extension](https://blogs.igalia.com/berto/2022/09/13/adding-software-to-the-steam-deck-with-systemd-sysext/) (`systemd-sysext`).
A system extension adds software to `/usr` and `/opt` without unlocking the read-only file system or enabling developer mode.

> [!NOTE]
> This is a fork of [sebble/1password-sysext-steam-deck](https://github.com/sebble/1password-sysext-steam-deck), originally created by Sebastian Mellor ([sebble](https://github.com/sebble)).
> All credit for the original approach and documentation goes to them.

## Features

- 🖥️ Desktop app in the application launcher, with icons
- 📌 System tray with _Quick Access_ popup
- 🦊 1Password links from Firefox open in the desktop app, including registering accounts
- 🔑 SSH agent in the terminal, including commit signing
- 🔒 Unlock with system authentication
- ⌨️ 1Password CLI (`op`), also inside the VS Code Flatpak
- 🛡️ KWallet set up as the Secret Service, so 1Password can remember the 2FA token (e.g. after signing in with a YubiKey)
- 🔄 One script to install and update

**Last tested with:**

| Component                 | Version             |
| ------------------------- | ------------------- |
| SteamOS                   | 3.9.5               |
| 1Password for Linux       | 8.12.42             |
| 1Password CLI             | 2.41.1              |
| Mozilla Firefox (Flatpak) | 159.0               |

## Installation

**Requirements**

- Desktop Mode with a normal terminal (e.g. Konsole). **Not** a terminal inside a Flatpak such as VS Code.
- A password for the `deck` user, as the script uses `sudo`. Set one with `passwd` if you haven't yet.

**Install**

```shell
git clone https://github.com/cptn-cosmo/1password-sysext-steam-deck.git
cd 1password-sysext-steam-deck
./scripts/10_setup.sh
```

The script downloads the latest stable 1Password and 1Password CLI, builds the system extension, and installs it to `~/extensions`.
Restart the Steam Deck afterwards.

## Updating

Run the same script again:

```shell
cd 1password-sysext-steam-deck
git pull
./scripts/10_setup.sh
```

- If 1Password and the CLI are already up to date, nothing happens. Pass `--force` to rebuild anyway.
- If 1Password is running, the script offers to quit it before installing.
- **After a SteamOS update**, the extension is no longer loaded (it is tied to the SteamOS version). Re-run the script to rebuild it.

> [!TIP]
> Restart the Steam Deck after every update. This resolves most errors with the `op` CLI.

## Configuration

### SSH agent

To use 1Password for all SSH connections, add this to your `~/.bashrc`:

```shell
export SSH_AUTH_SOCK=~/.1password/agent.sock
```

### 1Password CLI inside Flatpaks

To use `op` inside Flatpaks that can access your home directory (e.g. VS Code), copy it into `~/.local/bin`:

```shell
./scripts/31_install_cli.sh
```

The setup script keeps this copy up to date.

### Remembering the 2FA token

The setup script registers KWallet as the freedesktop Secret Service, so 1Password can store the 2FA token after you sign in with, e.g., a YubiKey.
If you installed with an older version of this repository, re-run the script to apply this.
See [issue #22 on the original repository](https://github.com/sebble/1password-sysext-steam-deck/issues/22).

## Troubleshooting

| Problem | Solution |
| ------- | -------- |
| 1Password is missing after a SteamOS update | Re-run `./scripts/10_setup.sh`. |
| `op` CLI errors after an update | Restart the Steam Deck. |
| The extension has the wrong `os-release` (e.g. `22.08`) | You ran the script inside a Flatpak. Use a normal terminal. |
| The extension is not loaded | Check `systemd-sysext status`, then try `sudo systemd-sysext refresh`. |

Still stuck? [Open an issue](https://github.com/cptn-cosmo/1password-sysext-steam-deck/issues/new/choose), or check the [issues on the original repository](https://github.com/sebble/1password-sysext-steam-deck/issues).

## How it works

The [setup script](https://github.com/cptn-cosmo/1password-sysext-steam-deck/blob/main/scripts/10_setup.sh) is documented step by step with inline comments.
It combines the official 1Password tarball, Debian package and CLI into one extension image, and mirrors what the official post-install script does.

Every script is also valid Markdown once the leading `# ` is removed from each line, which is why they contain lines like `` # ```shell ``.
`make docs` converts them into the [`docs/` folder](https://github.com/cptn-cosmo/1password-sysext-steam-deck/tree/main/docs), e.g. the [rendered setup script](https://github.com/cptn-cosmo/1password-sysext-steam-deck/blob/main/docs/10_setup.md).
The [original documentation site](https://sebble.github.io/1password-sysext-steam-deck/) shows the upstream version.

The `Makefile` only calls the scripts. `make` is not installed on SteamOS by default, so run the scripts directly.

## FAQ

_Answers by the original author._

<details>
<summary><b>Why not use the official Arch installation instructions?</b></summary>

See <https://support.1password.com/install-linux/#arch-linux>.

This will fail at `makepkg`, installing the missing dependency will then fail at `fakeroot`.

</details>

<details>
<summary><b>Why not use the official Flatpak?</b></summary>

See <https://support.1password.com/install-linux/#flatpak>.

- You’ll need to lock and unlock 1Password in your browser separately from the app.
- You won’t be able to unlock 1Password or 1Password CLI with system authentication.
- You won’t be able to use the SSH agent.

</details>

<details>
<summary><b>Why not follow the instructions for other distributions?</b></summary>

See <https://support.1password.com/install-linux/#other-distributions-or-arm-targz>.

The installation script `sudo /opt/1Password/after-install.sh` will fail when trying to update _Polkit_ as the `/usr` partition is read-only (even as sudo).

You could use `sudo steamos-readonly disable` but I have chosen not to. See the next question.

</details>

<details>
<summary><b>Why not enable developer mode and/or make the <code>/usr</code> partition writable?</b></summary>

See <https://help.steampowered.com/en/faqs/view/671A-4453-E8D2-323C>.

I don't want to. System updates will probably revert any changes you have made in here.

</details>

<details>
<summary><b>Could this be achieved with more permissive Flatpak policies?</b></summary>

I don't know. I assume not, but when reading about Visual Studio Code Flatpak issues perhaps there are other approaches..? Please share if you have ideas. P.S. I do not know Flatpak either so I would not be able to implement this.

</details>

<details>
<summary><b>What are the downsides of this approach?</b></summary>

Firstly, I made this with very little initial knowledge of `systemd-sysext`, _Arch_, and a few other things. This is for personal use.

Secondly, see <https://blogs.igalia.com/berto/2022/09/13/adding-software-to-the-steam-deck-with-systemd-sysext/> (section "Limitations and caveats") for some very good reasons to be wary of using `systemd-sysext`.
A copy of that section, in case the blog is not available [2023-01-14]:

> Using extensions is easy (you put them in the directory and voilà!). However, creating extensions is not necessarily always easy. To begin with, any libraries, files, etc., that your extensions may need should be either present in the root filesystem or provided by the extension itself. You may need to combine files from different sources or packages into a single extension, or compile them yourself.
>
> In particular, if the extension contains binaries they should probably come from the Steam Deck repository or they should be built to work with those packages. If you need to build your own binaries then having a SteamOS virtual machine can be handy. There you can install all development files and also test that everything works as expected. One could also create a Steam Deck SDK extension with all the necessary files to develop directly on the Deck 🙂
>
> Extensions are not distribution packages, they don’t have dependency information and therefore they should be self-contained. They also lack triggers and other features available in packages. For desktop applications I still recommend using a system like Flatpak when possible.
>
> Extensions are tied to a particular version of the OS and, as explained above, the ID and VERSION_ID of each extension must match the values from /etc/os-release. If the fields don’t match then the extension will be ignored. This is to be expected because there’s no guarantee that a particular extension is going to work with a different version of the OS. This can happen after a system update. In the best case one simply needs to update the extension’s VERSION_ID, but in some cases it might be necessary to create the extension again with different/updated files.
>
> Extensions only install files in /usr and /opt. Any other file in the image will be ignored. This can be a problem if a particular piece of software needs files in other directories.
>
> When extensions are enabled the /usr and /opt directories become read-only because they are now part of an overlayfs. They will remain read-only even if you run steamos-readonly disable !!. If you really want to make the rootfs read-write you need to disable the extensions (systemd-sysext unmerge) first.
>
> Unlike Flatpak or Podman (including toolbox / distrobox), this is (by design) not meant to isolate the contents of the extension from the rest of the system, so you should be careful with what you’re installing. On the other hand, this lack of isolation makes systemd-sysext better suited to some use cases than those container-based systems.

</details>

## Credits

- [Sebastian Mellor (sebble)](https://github.com/sebble), author of the [original project](https://github.com/sebble/1password-sysext-steam-deck)
- [Adding software to the Steam Deck with systemd-sysext](https://blogs.igalia.com/berto/2022/09/13/adding-software-to-the-steam-deck-with-systemd-sysext/) on the Igalia blog
- [Reddit discussion: Possible to install on Steam Deck?](https://www.reddit.com/r/1Password/comments/vz5pqb/possible_to_install_on_steam_deck/)
