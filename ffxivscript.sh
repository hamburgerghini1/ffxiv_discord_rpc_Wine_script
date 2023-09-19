#!/bin/bash
# Final Fantasy XIV Online wrapper for Linux.
# THIS IS THE STANDALONE VERSION.
# A minimal wrapper for IPC-Bridge is shipped alongside this program
# for use with Steam.
#
# Automatically parses the program's environment to launch
# Discord IPC bridge within the same prefix, to obtain
# "Discord Rich Presence" functionality using the Dalamud Plugin.
#
# Can also be used in conjunction with LaunchFFXIV for IINACT support. (WIP)
#
# Original author: XenHat on GitLab (me@xenh.at) 
# This work is licensed under the terms of the MIT license.
# For a copy, see <https://opensource.org/licenses/MIT>.
#
#
# TODO: Parse --gamescope-parameters=
start_xlcore() {
	xlcore_pid=""
	ffxiv_start_timeout=120
	xlcore_start_timeout=120
	XLCoreLocation="$HOME/.xlcore"
	_wine_binary_path="${XLCoreLocation}/compatibilitytool/beta/wine-xiv-staging-fsync-git-7.10.r3.g560db77d/bin/wine"
	if [[ $(command -v xivlauncher) ]]; then
		launcher_bin=xivlauncher
	elif [[ $(command -v XIVLauncher.Core) ]]; then
		launcher_bin=XIVLauncher.Core
	elif [[ $(command -v xivlauncher.rpm) ]]; then
		launcher_bin=xivlauncher.rpm
	fi
	if [[ -n $launcher_bin ]]; then
		#shellcheck disable=SC2086
		#pfx=""
		# if [[ $kwallet_in_use == 0 ]];
		# then
		# pfx="
		LD_PRELOAD="" XL_SECRET_PROVIDER=FILE $launcher_bin run --parent-expose-pids --parent-share-pids --parent-pid=1 --branch=stable --arch=x86_64 --command=xivlauncher &
	else
		echo >&2 "XIVLauncher not found!"
		exit 1
	fi
	ffxiv_wait_counter=0
	abort=0
	xiv_start_counter=0
	until pgrep ffxiv_dx11; do
		# check if laucher was exited manually
		if [[ ! $(pgrep -f XIVLauncher.Core) ]]; then
			if [[ $xiv_start_counter -ge $xlcore_start_timeout ]]; then
				echo >&2 "XIVLauncher has exited!"
				abort=1
				break
			fi
			((xiv_start_counter++))
		elif [[ -z $xlcore_pid ]]; then
			xlcore_pid=$(pgrep -f XIVLauncher.Core)
		fi
		if [[ $ffxiv_wait_counter -ge $ffxiv_start_timeout ]]; then
			kill "$xlcore_pid"
			abort=1
			break
		fi
		((ffxiv_wait_counter++))
		sleep 1
	done
	if [[ $abort == 1 ]]; then
		exit 1
	fi
}

set_wine_env() {
	# Read the launcher configuration after the game has been launched
	# in case the user edited the configuration
	launcher_ini="$(<~/.xlcore/launcher.ini)"
	if grep -Fxq 'ESyncEnabled=true' <<<"$launcher_ini"; then
		WINEESYNC=1
	else
		WINEESYNC=0
	fi
	if grep -Fxq 'FSyncEnabled=true' <<<"$launcher_ini"; then
		WINEFSYNC=1
	else
		WINEFSYNC=0
	fi
	_xlcore_wine_binary_path_setting=$(grep -F WineBinaryPath <<<"$launcher_ini" | cut -d '=' -f 2)
	if [[ -n $_xlcore_wine_binary_path_setting ]]; then
		_wine_binary_path=$_xlcore_wine_binary_path_setting
	fi
	echo "Wine path: $_wine_binary_path"
	export WINEESYNC WINEFSYNC
	#shellcheck disable=SC1003
	# DOTNET_BUNDLE_EXTRACT_BASE_DIR='' WINEPREFIX="${XLCoreLocation}/wineprefix" \
	# "${_wine_binary_path}/wine64" \
	# "${XLCoreLocation}/wineprefix/drive_c/IINACT.exe" &
	export -n WINEESYNC WINEFSYNC
}

# TODO: Clean up and deduplicate
start_ffxiv_rpc_bridge() {
	# Check if the program even exists...
	bridge_file=""
	possible_locations=('/opt/wine-discord-ipc-bridge' "$HOME/src/wine-discord-ipc-bridge")
	for bridge_path in "${possible_locations[@]}"; do
		if [[ -d $bridge_path ]]; then
			bridge_file="${bridge_path}/winediscordipcbridge.exe"
			break
		fi
	done
	if [[ -n $bridge_file ]]; then
		# Load the environment variables from the running process
		# FIXME: Check if wine runs with CAP_SYS_ADMIN or other, as it prevents reading the environ file
		# until pgrep ffxiv_dx11; do
		# sleep 1
		# done
		#
		process_file="/proc/$(pgrep ffxiv_dx11)/environ"
		if [[ -f ${process_file} ]]; then
			while IFS= read -r -d $'\0' file; do
				if
					[[ $file =~ XDG_ ]] ||
						[[ $file =~ DXVK ]] ||
						[[ $file =~ PROTON ]] ||
						[[ $file =~ WINEPREFIX ]] ||
						[[ $file =~ WINEESYNC ]] ||
						[[ $file =~ WINEFSYNC ]] ||
						[[ $file =~ DBUS ]] ||
						[[ $file =~ AT_SPI_BUS ]]
				then
					# handle semicolons and other weird characters in value by re-assigning
					(
						IFS='=' read -r left right <<<"$file"
						echo "export $left=\"$right\"" >>/tmp/ffxiv_env
					)
				fi
			done </proc/"$(pgrep ffxiv_dx11)"/environ
			source /tmp/ffxiv_env
			# Is wine version managed by xivlauncher?
			wine_type=$(echo "$launcher_ini" | grep WineStartupType | cut -d '=' -f 2)
			#FIXME: Need to test managed again for proper path
			if [[ $wine_type == "Managed" ]]; then
				# Find current wine binary. Crude but until XLCore exposes this, it will have to do...
				_wine_binary_path=$(dirname "$(pgrep -a wineserver | grep xlcore | cut -d ' ' -f 2)")
			else
				#custom wine path
				_wine_binary_path="$(grep WineBinaryPath ~/.xlcore/launcher.ini | cut -d '=' -f 2)"
			fi
			echo "=========== STARTING BRIDGE =============="
			# Note: DO NOT FORK otherwise it will result in an infinite loop; we rely on blocking behaviour.
			"${_wine_binary_path}/wine64" "$bridge_file"
		fi
	else
		echo >&2 "Bridge not found. Please acquire wine-discord-ipc-bridge"
		bridge_pid="$!"
	fi
}

start_autorun() {
	# ====== Extras ============
	# Launch more processes using the same environment here
	# sleep 10
	while pgrep -f ffxiv_dx11; do
		if pgrep --exact Discord >/dev/null && pgrep --full winediscordipcbridge.exe >/dev/null; then
			start_ffxiv_rpc_bridge
		fi
		sleep 1
	done
}

init() {
	if [[ $1 == '--startup' ]]; then
		until ping google.com -c 1; do
			sleep 3
		done
	fi
	if [[ $XDG_SESSION_DESKTOP == "KDE" ]]; then
		for time in {10..1}; do
			if pgrep kwalletmanager; then
				kwallet_in_use=1
				break
			fi
			echo "Waiting $time seconds for kwallet"
			sleep 1
		done
	fi
}

kwallet_in_use=0
init
start_xlcore
set_wine_env
start_autorun

# kill "$bridge_pid"
# killall -r xiv
# killall -r XIV
# echo "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
# Star FFlogs-uploader if not already running
#pgrep fflogs-uploader || command -v fflogs-uploader >/dev/null 2>&1 && fflogs-uploader &

