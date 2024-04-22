#!/usr/bin/env bash
set -o errexit -o pipefail -o noclobber -o nounset

function show_help() {
	cat <<EOH
Timer Daemon Script

This daemon interfaces with timer.sh, reading commands from stdin and outputting to stdout. It supports all commands of timer.sh, plus a daemon-stop command through stdin.

Usage:
timer-daemon.sh [tick]

Parameters:
- tick: Defines the update interval in seconds, controlling the frequency of output updates. Valid range: 0.01 to 10 seconds, with up to two decimal places of precision. Recommended 1 for updates every second. Note: Real-time updates are not guaranteed. Default is 1.
- daemon-start [tick]: Activates the daemon, processing commands from stdin and outputting to stdout continuously. If provided, time and action start the timer immediately.
- daemon-stop [wait]: Shuts down the daemon. A wait value of 1 delays stopping until the current timer ends. This command must be sent through stdin.

Output: Displays [time] [seconds] [state] with time in HH:MM:SS format.

States:
- running: Timer is active.
- paused: Timer is on hold.
- stopped: Timer is inactive, the default state.
- finished: Timer has concluded, and the specified action was performed. Use the "stop" command to terminate ongoing actions. Restarting the timer without stopping continues background action execution.

Return Error Codes:
1: General error. Attempt troubleshooting or consult documentation.

Note: Utilize distinct TIMER_CONFIG_DIR for each daemon instance to avoid concurrent execution issues.
EOH
}

while getopts ":h-" option; do
	case "${option}" in
	h)
		show_help
		exit 0
		;;
	-)
		case "${OPTARG}" in
		help)
			show_help
			exit 0
			;;
		*)
			echo "Unknown option --${OPTARG}" >&2
			echo "Use -h or --help for more information." >&2
			exit 1
			;;
		esac
		;;
	\?)
		echo "Invalid option: -${OPTARG}" >&2
		echo "Use -h or --help for more information." >&2
		exit 1
		;;
	:)
		echo "Option -${OPTARG} requires an argument." >&2
		exit 1
		;;
	esac
done
shift $((OPTIND - 1))

# Validates and sets tick.
function parse_tick() {
	#Number beween 0.01 and 10, with a maximal 2 digit persition
	if [[ "$1" =~ ^0\.[0-9]?[1-9]|[1-9](\.[0-9]{0,2})?|10$ ]]; then
		echo "$1"
	else
		echo "ignoring invalid tick $1, using 1" >/dev/stderr
		echo "tick has to be between 0.01 and 10" >/dev/stderr
		echo 1
	fi
}

# TODO measures execution time - which seems neglectable. Reduces sleep time while
# sleep itself does not garantee greater than second persition. May overkill?
function start_daemon() {
	declare -gi interrupt="0"
	declare -gi stop_after_finish="0"
	declare -r time_tmpfile=$(mktemp)

	declare -a command=()
	declare next_tick

	while ((interrupt != 1)); do
		if [ "$stop_after_finish" == 1 ] && [ "$state" == "finished" ]; then
			break
		fi

		exec 3<>"$time_tmpfile"
		{ { time {
			timer
			TIMEFORMAT='%R'
		} 2>&4; } 2>&3; } 4>&2
		time_passed=$(cat "$time_tmpfile")
		exec 3>&-
		echo "" >|"$time_tmpfile"

		next_tick=$(bc -q <(echo -e "$tick-$time_passed \n quit"))
		sleep "$next_tick"
	done
}

function stop_daemon() {
	local -ri wait=${1:-0}

	if ((wait)); then
		stop_after_finish=1
	else
		interrupt=1
	fi
}

function timer() {
	IFS=$' ' read -r -t 0.001 -s -a command && true # ignore errors with && true

	if [ "daemon-stop" == "${command[0]:-}" ]; then
		stop_daemon "${command[1]:-0}"
	fi

	if [ -n "${command[0]:-}" ]; then
		for ((i = 0; i < ${#command[@]}; i++)); do
			echo "index: $i value: ${command[i]}"
		done

		timer.sh "${command[@]}"
	else
		timer.sh
	fi
}

tick=$(parse_tick "${1:-1}")
start_daemon
