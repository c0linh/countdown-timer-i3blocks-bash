#!/usr/bin/env bash
set -o errexit -o pipefail -o noclobber -o nounset

function show_help() {
	cat <<EOH
Countdown Timer (Bash Script)

A countdown timer script in pure bash, managing a state file without daemon capabilities. Users must invoke the script periodically.

Usage:
timer.sh [-h, --help] {set [time] [action] | start [time] | pause | stop | get-state} 

-h, --help Display this help message and exit.

A call without arguments returns the updated current status. Every invocation 
returns a status line.

Commands:
start [time] [action]: Initiates the timer. No effect if already running/ paused. Time and action are optional, resetting after completion. Example: timer.sh start 3:00 "notify-send 'Time's up!' 'chop chop...'"

- set [time] [action]: Sets default time and action. Only if the timer is not active. Resets the timer and action after completion.
- pause: Pauses an active timer.
- stop: Stops the timer, resetting to default values.
- get-state: Displays timer's state values.

Parameters:
- time: Format: HH:MM:SS or seconds. Must include at least one non-zero value.
  Examples: "60:00", "1:0:0", "3600", "59:60" (all equal 1 hour).
  
- action: Command executed at zero. Stored differently based on invocation:
  Via start: Escaped, stored in .timer.state (basic escaping).
  Via set: As bash script in .timer.action (full support, no escaping issues).
  
Output:
  [time] [seconds] [state]

States:
- running: Timer active.
- paused: Timer paused.
- stopped: Timer inactive (default).
- finished: Timer completed, action executed. For long actions, use "stop" to	terminate.

Concurrency & Instances:
Does not support concurrent calls. Utilizes .timer.lock for a simple lock mechanism. Different instances can run concurrently with separate TIMER_CONFIG_DIR configurations.

Configuration & Files:
TIMER_CONFIG_DIR: Storage for all files. Defaults to XDG_CONFIG_DIR or HOME. Created if non-existent.

.timer.state: Stores time left, end time, and action PID.
.timer.lock: Prevents concurrent script executions.
.timer.action: Contains the finish action as a bash script for extended functionality. Remove write permissions to prevent overwrite.

Return Codes:
1: Invalid input.
10: Cannot create TIMER_CONFIG_DIR.
11: Cannot load .timer.state.
15: Action execution failed (missing permissions on .timer.action).
99: Lock file .timer.lock acquisition failed.
101: Internal state unknown.

Inspired by https://github.com/claudiodangelis/timer. A simpler bash alternative without the need for a Go runtime.
EOH
}

# Parsing help options
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

# Contains basic funcions and declares global parameters shared with and
# REQUIRED by this script!
# shellcheck disable=SC1091
source timer-functions.sh

# Validates and sets time and action command line parameter.
#
# used for: timer start 01:13 "echo FINISHED!"
#	  and: timer set 01:13 "echo FINISHED!"
#
# $1 - set default variable?
# $2 - time to set
# $3 - action to set
function set_time_and_action_args() {
	declare -ri set_default="${1:0}"

	if ! is_state_in "finished stopped"; then
		echo "set can only be called in finished or stopped state" >/dev/stderr
	fi

	if is_time_valid "${2:-}"; then
		local -r tmp_time=$(to_seconds "${2}")

		time_left=$tmp_time
		((set_default)) && default_time="$tmp_time"
	fi

	if [ -n "${3:-}" ]; then
		action_tmp="${*:3:$#}"

		if ((set_default)); then
			save_action "$action_tmp"
		else
			current_action="$action_tmp"
		fi
	fi
}

function execute_finish_action() {
	if [ -n "$current_action" ]; then
		$current_action &
		[ -n "$!" ] && action_pid=$!
	elif [ -x "$ACTION_FILE" ]; then
		$ACTION_FILE &
		action_pid=$!
	else
		echo "$ACTION_FILE is not executable, can not execute action."
		exit 15
	fi

	sleep 0.01 # 10 milliseconds for the action to terminate
}

function kill_finish_action() {
	if is_action_running; then
		#kill attached subprocesses
		pkill -P "$action_pid"
		kill "$action_pid"

		sleep 0.01 # 10 milliseconds for the action to terminate gracefully
	fi

	if is_action_running; then
		kill -9 "$action_pid"
	fi

	if is_action_running; then
		echo "unable to terminate action (pid: $action_pid)" >/dev/stderr
	fi

	action_pid=0
}

function print_state() {
	echo "$(to_hhmmss "$time_left")" "$time_left" "$state"
}

# Updates timer releated variables based on the current time:
# - time_left - time left in seconds
# - mtime     - last updated time in unix epoc seconds
# - end_time	- endtime in unix epoc seconds
update_timer() {
	declare -ri now="$(date -u +%s)"

	case $state in
	running)
		#Timer started: calculate end time
		if ! ((end_time)); then
			end_time=$((now + time_left))
		fi

		time_left=$((end_time - now))
		mtime="$now"
		;;
	paused)
		end_time+=$((now - mtime))
		mtime="$now"
		;;
	finished | stopped)
		#reset values
		time_left=$default_time
		end_time="0"
		mtime="0"
		#only used when a action is specified via "start time action"
		current_action=""
		#action_pid - keep in case we need to kill it
		;;
	*)
		echo "unkonwn state: $state" >/dev/stderr
		echo "no actions specified" >/dev/stderr
		exit 101
		;;
	esac
}

#Take care of automated state changes:
# running -> finished
# finished -> stopped
timer_eval_state() {
	#Timer is running - update values before evaluating state
	if is_state_in "running paused"; then
		update_timer
	fi

	if [ "$state" == "running" ] && ((time_left <= 0)); then
		execute_finish_action
		state="finished"
		update_timer #reset timer variables
	fi

	if [ "$state" == "finished" ] && ! is_action_running; then
		action_pid=0
		state="stopped"
	fi
}

timer_start() {
	if [ "$state" != "running" ]; then
		state="running"
		update_timer
	fi
}

timer_pause() {
	if [ "$state" == "running" ]; then
		state="paused"
		update_timer
	fi
}

timer_stop() {
	if [ "$state" == "finished" ]; then
		kill_running_action
	fi
	if [ "$state" != "stopped" ]; then
		state="stopped"
		update_timer
	fi
}

timer_command() {
	aquire_lock
	load_state

	if [ "$state" != "stopped" ]; then
		# if in a "active" state update state: in case the running timer finished
		# or another state change occured since last call.
		timer_eval_state
	fi

	declare -r command=${1:-""}
	[ -n "$command" ] && shift

	case $command in
	start)
		set_time_and_action_args "0" "$@"
		timer_start
		;;
	pause)
		timer_pause
		;;
	stop)
		timer_stop
		;;
	set)
		set_time_and_action_args "1" "$@"
		;;
	get-state)
		get_state
		;;
	'')
		#noop - update takes place at beginning of function
		;;
	*)
		print_help
		echo
		echo "$command is not a valid command" >/dev/stderr
		exit 1
		;;
	esac

	save_state
	print_state
	release_lock
}

timer_command "${@}"
