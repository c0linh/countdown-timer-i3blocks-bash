#!/usr/bin/env bash
set -ex

#Not used
function print_help() {
	cat <<EOH
i3blocks Timer Integration Script Help

This document serves as a help guide for a bash script designed to integrate a countdown timer (timer.sh) with i3blocks, providing visual feedback and control over the timer directly from the i3blocks bar.

Requirements
- timer.sh: A countdown timer script that manages its state through files and supports commands like start, pause, stop, and set.
- i3blocks: A flexible scheduler for your i3bar blocks, used to display and control the timer.
- Nerd Fonts: For icon display. Ensure your system has a compatible font installed.

Setup
Environment Variables:
- BLOCK_NAME: Identifies the block within i3blocks. Must be set for the script to function.
- interval: Should be set to 1 to ensure updates are received every second.
- markup: Should be set to pango for proper formatting of the output.

Configuration Directory:
- The script uses a configuration directory derived from the BLOCK_NAME and BLOCK_INSTANCE environment variables, defaulting to ~/.config if XDG_CONFIG_DIR is not set. This directory is also used for storing timer.sh configuration and state files.

Features
- Dynamic Icons: Displays icons based on the timer's current state (running, paused, stopped, finished), leveraging Nerd Fonts.

Mouse Interactions
Left Click (button=1): Starts the timer.
Middle Click (button=2): Pauses the timer.
Right Click (button=3): Stops the timer.
Scroll Up (button=4): Increases the timer by 1 minute.
Scroll Down (button=5): Decreases the timer by 1 minute.

Error Handling
If BLOCK_NAME is not set, indicating the script is not executed in an i3blocks context, an error message is displayed.
Advises on setting interval=1 and markup=pango for optimal performance and display if not already set.

Output Formatting
Utilizes Pango markup for styling. The timer's current value and icon are displayed, with color changes based on the remaining time.

Configuration Errors and Debugging
The script exits with an error message if critical environment variables (BLOCK_NAME, interval, markup) are not set appropriately.
Ensure Nerd Fonts are installed and configured in your terminal or i3bar for icons to display correctly.
EOH
}

if [ -z "$BLOCK_NAME" ]; then
	echo "<span>BLOCK_NAME not set, not running in i3-block context</span>"
	exit 1
fi

if [ "${interval:-0}" != 1 ]; then
	echo "<span>may set interval=1</span>"
	exit 1
fi

if [ "${markup:-}" != "pango" ]; then
	echo "<span>may set markup to pango</span>"
	exit 1
fi

declare -r BLOCK_CONFIG_DIR="${XDG_CONFIG_DIR:-$HOME/.config}/${BLOCK_NAME}${BLOCK_INSTANCE}"
export TIMER_CONFIG_DIR=$BLOCK_CONFIG_DIR

function get_icon() {
	#Icons from https://www.nerdfonts.com/cheat-sheet
	#prefix nf-md-timer_
	case ${state:-} in
	running) echo "󱫠" ;;  #play
	stopped) echo "󱫫" ;;  #outline stop
	paused) echo "󱫟" ;;   #outline pause
	finished) echo "󱫌" ;; #alert
	*) ;;
	esac
}
function click_to_command() {
	case "${1:-}" in
	"1") echo "start" ;;         #left
	"2") echo "pause" ;;         #middle
	"3") echo "stop" ;;          #right
	"4") to_time_command "1" ;;  #scroll up +1min
	"5") to_time_command "-1" ;; #scroll up -1min
	esac
}

function to_time_command() {
	read -r time seconds state < <(timer.sh)
	time=$((60 * ((seconds / 60) + $1)))
	echo "set $time"
}

declare icon
declare time

command=""
if [ -n "$button" ]; then
	command=$(click_to_command "$button" "$state" "$seconds")
fi

# shellcheck disable=SC2086
read -r time seconds state < <(timer.sh $command)
icon=$(get_icon "$state")

if [ "$seconds" -lt 120 ]; then
	value_color=${warn_color}
else
	value_color="${color}"
fi

echo "<span color=\"${label_color}\">${icon} </span><span color=\"${value_color}\">${time}</span>"
