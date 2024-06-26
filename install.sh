#!/bin/bash

function error {
  echo -e "\e[91m$1\e[39m"
  exit 1
}

cd "$HOME"

#ensure non-root
if [[ "$(id -u)" == 0 ]]; then
  error "PRoot-Apps is not designed to be installed as root! Please try again as a regular user."
fi

#Ensure running arm processor
if uname -m | grep -qi 'x86\|i686\|i386' ;then
  error "PRoot-Apps is not designed to be installed on non-ARM CPU architectures."
fi

#ensure proot
if [ -z $TERMUX_VERSION ]; then
  return 1
else
  echo -e "\e[91mPRoot-Apps is not designed to be run outside PRoot.\e[39m"
  echo -e "\e[91mThis website explains detailed differences between Termux and a regular Linux distro:\e[39m"
  error "https://wiki.termux.com/wiki/Differences_from_Linux"
fi

#ensure debian
command -v apt >/dev/null || error "apt: command not found. Most likely this is not running in a Debian or Ubuntu based PRoot environment."

sudo apt update || error "The command 'sudo apt update' failed. Before PRoot-Apps will work, you must fix your apt package-management system."

#install dependencies
dependencies='yad curl wget aria2 lsb-release software-properties-common apt-utils apt-transport-https gnupg imagemagick bc librsvg2-bin locales shellcheck git wmctrl xdotool x11-utils rsync unzip debsums libgtk3-perl'

if ! dpkg -s $dependencies &>/dev/null ;then
  sudo apt install $dependencies -y -f --no-install-recommends || error "PRoot-Apps dependencies failed to install and so the PRoot-Apps install has been aborted. Before PRoot-Apps can be installed you must solve any errors above."
fi

#remove annoying "YAD icon browser" launcher
sudo rm -f /usr/share/applications/yad-icon-browser.desktop

#download pi-apps if folder missing
DIRECTORY="$(readlink -f "$(dirname "$0")")"
if [ -z "$DIRECTORY" ] || [ "$DIRECTORY" == "$HOME" ] || [ "$DIRECTORY" == bash ] || [ ! -f "${DIRECTORY}/api" ] || [ ! -f "${DIRECTORY}/gui" ];then
  DIRECTORY="$HOME/pi-apps"
fi
downloaded=0 #track if pi-apps was downloaded this time

#Re-download pi-apps folder in all cases if pi-apps already exists
#users expect to use the install script to "restore" a working pi-apps install in incase their local version is somehow not working or corrupted
if [ -d "$DIRECTORY" ];then    
  rm -rf ~/pi-apps-forced-update
  
  echo "Reinstalling PRoot-Apps..."
  downloaded=1
  output="$(git clone --depth 1 https://github.com/twocomputed/proot-apps ~/pi-apps-forced-update 2>&1)"
  if [ $? != 0 ] || [ ! -d "$DIRECTORY" ];then
    error "PRoot-Apps download failed!\ngit clone output was: $output"
  fi
  cp -af "${DIRECTORY}/data" ~/pi-apps-forced-update
  cp -af "${DIRECTORY}/apps" ~/pi-apps-forced-update
  rm -rf "$DIRECTORY"
  mv -f ~/pi-apps-forced-update "$DIRECTORY"
  
#if pi-apps folder does not exist, download it
elif [ ! -d "$DIRECTORY" ];then
  echo "Downloading PRoot-Apps..."
  downloaded=1
  output="$(git clone --depth 1 https://github.com/twocomputed/proot-apps "$DIRECTORY" 2>&1)"
  if [ $? != 0 ] || [ ! -d "$DIRECTORY" ];then
    error "PRoot-Apps download failed!\ngit clone output was: $output"
  fi
fi

#Past this point, DIRECTORY variable populated with valid pi-apps directory

#if ChromeOS, install lxterminal
if command -v garcon-terminal-handler >/dev/null ;then
  echo "In order to install apps on ChromeOS, a working terminal emulator is required.
Installing lxterminal in 10 seconds... (press Ctrl+C to cancel)"
  sleep 10
  sudo apt install -yf lxterminal || error "Failed to install lxterminal on ChromeOS!"
fi

#menu button
if [ ! -f ~/.local/share/applications/pi-apps.desktop ];then
  echo "Creating menu button..."
fi
mkdir -p ~/.local/share/applications
if [ -f /etc/xdg/menus/lxde-pi-applications.menu ];then #If on PiOS, place launcher in Accessories as it has always been there and is more intuitive there
echo "[Desktop Entry]
Name=PRoot-Apps
Comment=Debian-based Termux PRoot App Store for open source projects
Exec=${DIRECTORY}/gui
Icon=${DIRECTORY}/icons/logo.png
Terminal=false
StartupWMClass=PRoot-Apps
Type=Application
Categories=Utility
StartupNotify=true" > ~/.local/share/applications/pi-apps.desktop
else #if not on PiOS, place launcher in Preferences to match the wider decision of putting app installers there (see PR #2388)
echo "[Desktop Entry]
Name=PRoot-Apps
Comment=Debian-based Termux PRoot App Store for open source projects
Exec=${DIRECTORY}/gui
Icon=${DIRECTORY}/icons/logo.png
Terminal=false
StartupWMClass=PRoot-Apps
Type=Application
Categories=Utility;System;PackageManager;
StartupNotify=true" > ~/.local/share/applications/pi-apps.desktop
fi
chmod 755 ~/.local/share/applications/pi-apps.desktop
gio set ~/.local/share/applications/pi-apps.desktop "metadata::trusted" yes

#copy menu button to Desktop
mkdir -p ~/Desktop
cp -f ~/.local/share/applications/pi-apps.desktop ~/Desktop/

chmod 755 ~/Desktop/pi-apps.desktop
gio set ~/Desktop/pi-apps.desktop "metadata::trusted" yes

#copy icon to local icons directory (necessary on some wayland DEs like on PiOS Wayfire)
mkdir -p ~/.local/share/icons
cp -f ${DIRECTORY}/icons/logo.png ~/.local/share/icons/pi-apps.png
cp -f ${DIRECTORY}/icons/settings.png ~/.local/share/icons/pi-apps-settings.png

#settings menu button
if [ ! -f ~/.local/share/applications/pi-apps-settings.desktop ];then
  echo "Creating Settings menu button..."
fi
echo "[Desktop Entry]
Name=PRoot-Apps Settings
Comment=Configure PRoot-Apps or create an App
Exec=${DIRECTORY}/settings
Icon=${DIRECTORY}/icons/settings.png
Terminal=false
StartupWMClass=PRoot-Apps-Settings
Type=Application
Categories=Settings;
StartupNotify=true" > ~/.local/share/applications/pi-apps-settings.desktop

if [ ! -f ~/.config/autostart/pi-apps-updater.desktop ];then
  echo "Creating autostarted updater..."
fi
mkdir -p ~/.config/autostart
echo "[Desktop Entry]
Name=PRoot-Apps Updater
Exec=${DIRECTORY}/updater onboot
Icon=${DIRECTORY}/icons/logo.png
Terminal=false
StartupWMClass=PRoot-Apps
Type=Application
X-GNOME-Autostart-enabled=true
Hidden=false
NoDisplay=false" > ~/.config/autostart/pi-apps-updater.desktop

mkdir -p "${DIRECTORY}/data/status" "${DIRECTORY}/data/update-status" \
  "${DIRECTORY}/data/preload" "${DIRECTORY}/data/settings" \
  "${DIRECTORY}/data/status" "${DIRECTORY}/data/update-status" \
  "${DIRECTORY}/data/categories"

#pi-apps terminal command
if [ ! -f /usr/local/bin/pi-apps ] || ! cat /usr/local/bin/pi-apps | grep -q "${DIRECTORY}/gui" ;then
  echo "#!/bin/bash
${DIRECTORY}/gui"' "$@"' | sudo tee /usr/local/bin/pi-apps >/dev/null
  sudo chmod +x /usr/local/bin/pi-apps
fi

#preload app list
if [ ! -f "$DIRECTORY/data/preload/LIST-" ];then
  echo "Preloading app list..."
fi
"${DIRECTORY}/preload" yad &>/dev/null

#Run runonce entries
"${DIRECTORY}/etc/runonce-entries" &>/dev/null

#Determine message of the day. If announcements file missing or over a day old, download it.
if [ ! -f "${DIRECTORY}/data/announcements" ] || [ ! -z "$(find "${DIRECTORY}/data/announcements" -mtime +1 -print)" ]; then
  wget https://raw.githubusercontent.com/Botspot/pi-apps-announcements/main/message -qO "${DIRECTORY}/data/announcements"
fi

if [ $downloaded == 1 ];then
  echo "Installation complete. PRoot-Apps can be launched from the start menu or by running the command 'pi-apps'."
else
  echo -e "Please note that PRoot-Apps has NOT been freshly downloaded, because $DIRECTORY already exists."
fi
