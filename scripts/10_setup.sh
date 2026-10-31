#!/bin/sh
# ---
# title: Setup
# ---
# <!-- hide the `ex` bits, they're only useful in this script
set -ex
# -->

# Downloads 1Password, builds the system extension, and installs it. Run it from a normal SteamOS Terminal inside this repo:

#     ./scripts/10_setup.sh

# Re-run it at any time to update to the latest version of 1Password, or after a SteamOS update.
# If everything is already up to date it does nothing, unless you pass `--force`:

#     ./scripts/10_setup.sh --force

# We provide a name for the `sysext` that we are going to build.

# ```shell
SYSEXT_PREFIX=1password
SYSTEXT_PATH="build/extensions/${SYSEXT_PREFIX}"
# ```

## Enable the Secret Service (KWallet)

# 1Password stores some secrets (e.g. the 2FA token remembered after signing in with a YubiKey) via the freedesktop Secret Service.
# SteamOS does not make KWallet available as the Secret Service, so 1Password fails with `org.freedesktop.DBus.Error.ServiceUnknown`.
# See <https://github.com/sebble/1password-sysext-steam-deck/issues/22>.

# These are user settings in the home directory, so they are applied even if 1Password is already up to date.
# An existing service file is left untouched.

# ```shell
if [ -x /usr/bin/kwalletd6 ]; then
  DBUS_SERVICES_DIR="${HOME}/.local/share/dbus-1/services"
  if [ ! -f "${DBUS_SERVICES_DIR}/org.freedesktop.secrets.service" ]; then
    mkdir -p "${DBUS_SERVICES_DIR}"
    printf '[D-BUS Service]\nName=org.freedesktop.secrets\nExec=/usr/bin/kwalletd6\n' > "${DBUS_SERVICES_DIR}/org.freedesktop.secrets.service"
  fi
  kwriteconfig6 --file kwalletrc --group Wallet --key Enabled true
  kwriteconfig6 --file kwalletrc --group Wallet --key "Use One Wallet" true
  kwriteconfig6 --file kwalletrc --group Wallet --key "Default Wallet" kdewallet
  kwriteconfig6 --file kwalletrc --group Wallet --key "Use KWallet for Secret Service" true
  # Let the session bus pick up the new service file now, rather than after a restart.
  dbus-send --session --dest=org.freedesktop.DBus --type=method_call /org/freedesktop/DBus org.freedesktop.DBus.ReloadConfig || true
else
  echo "kwalletd6 not found, skipping Secret Service setup."
fi
# ```

## Check for updates

# The 1Password Debian repository index lists the latest stable version of both the desktop app and the CLI.
# We download exactly these versions below, so the check and the build always agree.

# ```shell
PACKAGES_URL=https://downloads.1password.com/linux/debian/amd64
PACKAGES="$(curl -fsS "${PACKAGES_URL}/dists/stable/main/binary-amd64/Packages")"
package_field() {
  printf '%s\n' "${PACKAGES}" | awk -v pkg="$1" -v field="$2:" '$1 == "Package:" { p = ($2 == pkg) } p && $1 == field { print $2; exit }'
}
DESKTOP_VERSION="$(package_field 1password Version)"
DESKTOP_DEB="$(package_field 1password Filename)"
CLI_VERSION="$(package_field 1password-cli Version | sed 's/-.*//')"
test -n "${DESKTOP_VERSION}" && test -n "${DESKTOP_DEB}" && test -n "${CLI_VERSION}"
# ```

# If the installed versions already match there is nothing to do.
# After a SteamOS update the extension is not loaded, so `/usr/bin/1password` is missing and we rebuild.

# ```shell
INSTALLED_DESKTOP="$(/usr/bin/1password --version 2>/dev/null || true)"
INSTALLED_CLI="$(/usr/bin/op --version 2>/dev/null || true)"
if [ "${1:-}" != "--force" ] && [ "${INSTALLED_DESKTOP}" = "${DESKTOP_VERSION}" ] && [ "${INSTALLED_CLI}" = "${CLI_VERSION}" ]; then
  echo "1Password ${DESKTOP_VERSION} and CLI ${CLI_VERSION} are already up to date."
  exit 0
fi
# ```

## Start from a clean slate

# Any leftovers from a previous run are removed first.

# ```shell
sudo rm -rf ./tmp ./build
mkdir -p tmp
# ```

## Download 1Password desktop

# Start by downloading the offical 1Password release archive. We will install this into our sysext.

# ```shell
curl -fL "https://downloads.1password.com/linux/tar/stable/x86_64/1password-${DESKTOP_VERSION}.x64.tar.gz" -o tmp/1password.tar.gz
# ```

# TODO: verify the GPG signature of this download.

## Download the 1Password Debian package

# This has more resources than the tarball (e.g. icons), which we merge into `/usr`.
# TODO: Use only this package in the future?

# ```shell
curl -fL "${PACKAGES_URL}/${DESKTOP_DEB}" -o tmp/1password.deb
(cd tmp && ar x 1password.deb)
tar -C tmp -xf tmp/control.tar.xz ./postinst
mkdir -p tmp/deb-data
tar -C tmp/deb-data -xf tmp/data.tar.xz
# ```

## Download 1Password CLI

# ```shell
curl -fL "https://cache.agilebits.com/dist/1P/op2/pkg/v${CLI_VERSION}/op_linux_amd64_v${CLI_VERSION}.zip" -o tmp/op.zip
# ```

## Prepare the sysext file system

# We need to ensure everything in the sysext is owned by `root` (for the later `setuid` bits to work).

# The following is almost identical to `/opt/1Password/after-install.sh` in official desktop download archive.
# We have prefixed all absolute paths with `SYSEXT_PREFIX`, and added some `root` ownership checks.

# We also replace a nested `eval/cat/cat` with `envsubst`, using `tee` to allow us to write with `sudo`.
# This could also be achieved with a `sed`, especially as we know the username is always `deck`.

# Let's create a few directories ahead of time.

# ```shell
sudo mkdir -p "${SYSTEXT_PATH}/opt"
sudo mkdir -p "${SYSTEXT_PATH}/usr/bin"
sudo mkdir -p "${SYSTEXT_PATH}/usr/share/bin/"
sudo mkdir -p "${SYSTEXT_PATH}/usr/share/polkit-1/actions/"
sudo mkdir -p "${SYSTEXT_PATH}/usr/share/doc/1password/examples/"
sudo mkdir -p "${SYSTEXT_PATH}/usr/share/applications/"
sudo mkdir -p "${SYSTEXT_PATH}/usr/lib/extension-release.d/"
# ```

# Next we will copy the contents into a the location they would normally be extracted to, but inside our `sysext` file system.

# ```shell
tar -C tmp -xf tmp/1password.tar.gz # AUR
sudo mv "tmp/1password-${DESKTOP_VERSION}.x64" "${SYSTEXT_PATH}/opt/1Password" # AUR
sudo unzip -d "${SYSTEXT_PATH}/usr/bin" tmp/op.zip -x op.sig # CLI
sudo cp -r tmp/deb-data/usr "${SYSTEXT_PATH}/" # DEB
sudo chown -R root:root "${SYSTEXT_PATH}"
# ```

# The mostly original install script (compare to ./tmp/postinst):

# ```shell
installFiles() {
  CWD=$(pwd)
  cd ${SYSTEXT_PATH}/opt/1Password/

  # Fill in policy kit file with a list of (the first 10) human users of the system.
  export POLICY_OWNERS
  POLICY_OWNERS="$(cut -d: -f1,3 /etc/passwd | grep -E ':[0-9]{4}$' | cut -d: -f1 | head -n 10 | sed 's/^/unix-user:/' | tr '\n' ' ')"
  cat com.1password.1Password.policy.tpl | envsubst | sudo tee ./com.1password.1Password.policy

  # Install policy kit file for system unlock
  sudo install -Dm0644 ./com.1password.1Password.policy -t ../../usr/share/polkit-1/actions/

  # Install examples
  sudo install -Dm0644 ./resources/custom_allowed_browsers -t ../../usr/share/doc/1password/examples/

  # chrome-sandbox requires the setuid bit to be specifically set.
  # See https://github.com/electron/electron/issues/17972
  sudo chmod 4755 ./chrome-sandbox

  GROUP_NAME="onepassword"

  # Setup the Core App Integration helper binary with the correct permissions and group
  if [ ! "$(getent group "${GROUP_NAME}")" ]; then
    sudo groupadd "${GROUP_NAME}"
  fi

  # SJIM: removed temporarily because missing from latest postinst
  #HELPER_PATH="./1Password-KeyringHelper"
  BROWSER_SUPPORT_PATH="./1Password-BrowserSupport"

  #sudo chgrp "${GROUP_NAME}" $HELPER_PATH
  ## The binary requires setuid so it may interact with the Kernel keyring facilities
  #sudo chmod u+s $HELPER_PATH
  #sudo chmod g+s $HELPER_PATH

  # This gives no extra permissions to the binary. It only hardens it against environmental tampering.
  sudo chgrp "${GROUP_NAME}" $BROWSER_SUPPORT_PATH
  sudo chmod g+s $BROWSER_SUPPORT_PATH

  # Restore previous directory
  cd "$CWD"

  # Register path symlink
  sudo ln -sf ../../opt/1Password/1password ${SYSTEXT_PATH}/usr/bin/1password
}

installFiles
#installAutoupdateChannel ## Not implemented
# ```

## Add application (enables browser integration and launcher menu item)

# Newer releases (e.g. 8.12.42) name the desktop entry `com.onepassword.OnePassword.desktop`.
# As in the official postinst, we also remove the legacy `1password.desktop` (shipped in the DEB) to avoid a duplicate entry.

# ```shell
sudo rm -f ${SYSTEXT_PATH}/usr/share/applications/1password.desktop
sudo install -m0644 ${SYSTEXT_PATH}/opt/1Password/resources/com.onepassword.OnePassword.desktop ${SYSTEXT_PATH}/usr/share/applications/
# ```

## Configure 1Password CLI

# The following is modified from `1password-cli.install` in <https://aur.archlinux.org/packages/1password-cli>.
# Alternatively, the instructions for official, manual installation also suggest these commands.

# We are:
# -   Creating the `onepassword-cli` group if it does not exist
# -   Ensuring that the `op` CLI binary is owned by the `onepassword-cli` group
# -   Enabling `setgid` bit on the binary, to ensure that it runs under the `onepassword-cli` group (this is important for biometrics)

# See a related issue <https://github.com/sebble/1password-sysext-steam-deck/issues/15>.

# ```shell
getent group onepassword-cli || sudo groupadd onepassword-cli
sudo chgrp onepassword-cli ${SYSTEXT_PATH}/usr/bin/op
sudo chmod g+s ${SYSTEXT_PATH}/usr/bin/op
# ```

#     gpg --receive-keys 3FEF9748469ADBE15DA7CA80AC2D62742012EA22
#     gpg --verify op.sig op

## Configure systemd-sysext

# The extension is only loaded if `ID` and `VERSION_ID` match `/etc/os-release`, so it must be rebuilt after a SteamOS update.

# ```shell
VERSION_ID="$(grep -E '^VERSION_ID=' /etc/os-release | cut -d= -f2)"
echo "ID=steamos" | sudo tee ${SYSTEXT_PATH}/usr/lib/extension-release.d/extension-release.${SYSEXT_PREFIX}
echo "VERSION_ID=${VERSION_ID}" | sudo tee -a ${SYSTEXT_PATH}/usr/lib/extension-release.d/extension-release.${SYSEXT_PREFIX}
# ```

## Create the filesystem layer

# ```shell
sudo mksquashfs ${SYSTEXT_PATH} ${SYSTEXT_PATH}.raw
# ```

## Quit 1Password

# Installing replaces the files of a running 1Password, so it needs to be quit first.
# There is no command line option to quit 1Password, so we ask the main (oldest) process to terminate and wait for it to exit.

# ```shell
if pgrep -x 1password > /dev/null; then
  printf '1Password is running and needs to quit to finish the install. Quit 1Password now? [Y/n] '
  read -r ANSWER
  case "${ANSWER}" in
    [nN]*)
      echo "Quit 1Password and re-run this script to finish the install."
      exit 1
      ;;
  esac
  pkill -o -x 1password
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -x 1password > /dev/null || break
    sleep 1
  done
  if pgrep -x 1password > /dev/null; then
    echo "1Password did not quit. Quit it manually and re-run this script."
    exit 1
  fi
fi
# ```

## Install and enable systemd-sysext

# We want the system extension to stay on a Steam Deck partition that will not be wiped.
# For this reason we are creating a folder for such extensions in our home directory (suggestion from <https://blogs.igalia.com/berto/2022/09/13/adding-software-to-the-steam-deck-with-systemd-sysext/>).
# With a suitable location for our system image layer, we move the built `.raw` file and create a symlink to our extension directory from the expected location on the real OS.

# ```shell
mkdir -p ~/extensions
test -L /var/lib/extensions || \
    sudo ln -sf "${HOME}/extensions" /var/lib/extensions
sudo mv ${SYSTEXT_PATH}.raw ~/extensions/${SYSEXT_PREFIX}.raw
sudo systemctl enable systemd-sysext
sudo systemctl start systemd-sysext
sudo systemd-sysext refresh
systemd-sysext status
# ```

# If the CLI was copied for use inside Flatpaks ([Install CLI](install_cli)), update that copy too.

# ```shell
if [ -f ~/.local/bin/op ]; then
  cp /usr/bin/op ~/.local/bin/op
fi
# ```

# **Note:** Ensure a full system restart after any updates, this resolves most errors with op CLI.

## Debugging:

#     systemd-sysext status
#     sudo systemd-sysext merge
#     sudo systemd-sysext refresh

# Optional: [Install CLI](install_cli) for use inside Flatpaks.
