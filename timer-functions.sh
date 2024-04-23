#!/usr/bin/env bash

set -o errexit -o pipefail -o noclobber -o nounset

# Contains basic funtions and declares global parameters shared with and
# REQUIRED by this timer.sh
# - config-file save and load
# - aquire and realease lockfile
# - time related function using "date" (parse, convert, format)
declare -r DEFAULT_CONFIG_DIR=${XDG_CONFIG_DIR:-$HOME}

if ! [ -d "${TIMER_CONFIG_DIR:=$DEFAULT_CONFIG_DIR}" ]; then
	mkdir "$TIMER_CONFIG_DIR" || (echo "can not creaet configuration directory $TIMER_CONFIG_DIR!" >&2 && exit 10)
fi

declare -r STATE_FILE="${TIMER_CONFIG_DIR}/.timer.state"
declare -r ACTION_FILE="${TIMER_CONFIG_DIR}/.timer.action"

declare time_left
declare state
declare -i mtime
declare -i end_time
declare -i action_pid
declare current_action

function set_default_state() {
	: "${default_time:="300"}"
	: "${current_action:=""}"
	: "${time_left:=$default_time}"
	: "${mtime:=0}"
	: "${end_time:=0}"
	: "${state:="stopped"}"
	: "${action_pid:=0}"
}

function save_action() {
	if [ -z "${1:-}" ]; then
		return 0
	fi

	if [ -f "$ACTION_FILE" ] && ! [ -w "$ACTION_FILE" ]; then
		echo "read-only $ACTION_FILE file. Keep current action." >&2
	else
		echo -e " #!/usr/bin/env bash\n${1%Q}" >|"$ACTION_FILE"
		chmod +x "$ACTION_FILE"
	fi
}

function load_state() {
	if [ ! -f "$STATE_FILE" ]; then
		set_default_state
		save_state
		if ! [ -f "$ACTION_FILE" ]; then
			save_action "echo \"DEAULT ACTION - TIMER FINISHED!\""
		fi
	else
		# shellcheck disable=SC1090
		source "$STATE_FILE" || (echo "can not load state file $STATE_FILE!" >&2 && exit 11)
		set_default_state
	fi
}

function save_state() {
	cat <<-EOF >|"$STATE_FILE"
		time_left=${time_left@Q}
		default_time=${default_time@Q}
		current_action=${current_action@Q}
		mtime=${mtime@Q}
		end_time=${end_time@Q}
		state=${state@Q}
		action_pid=${action_pid@Q}
	EOF
}

function get_state() {
	if ! [ -f "$STATE_FILE" ]; then
		save_state
		if ! [ -f "$ACTION_FILE" ]; then
			save_action "echo \"DEAULT ACTION - TIMER FINISHED!\""
		fi
	fi

	echo "$STATE_FILE:"
	cat "$STATE_FILE"
	echo "$ACTION_FILE:"
	cat "$ACTION_FILE"
}
declare -r seconds_out="+%s"
declare -r time_out="+%H:%M:%S"
declare -r time_input="%dhours%dmins%dseconds"

function to_seconds() {
	convert_time $seconds_out "$@"
}

function to_hhmmss() {
	local -ri time=${1:-0}

	if ((time < 0)); then
		time=$((time * -1))
		echo "-$(convert_time $time_out $time)"
	else
		convert_time $time_out "$@"
	fi
}

function convert_time() {
	local -r output_format="$1"
	shift
	local -r time="$(format_time "$@")"
	date -u -d "1970-01-01 ${time}" "${output_format}"
}

function format_time() {
	# shellcheck disable=SC2059
	# shellcheck disable=SC2046
	printf "$time_input" $(tokenize_time "$@")
}

function tokenize_time() {
	# shellcheck disable=SC2206
	(($# == 1)) && arg=(${1//\:/ }) || arg=($@)
	set -- 0 0 0 "${arg[@]}"
	echo "${@: -3}"
}

function is_time_valid() {
	#At least one non zero digit
	[[ ${1:-} =~ [1-9] ]] &&
		#only numbers, seperated by : or space exclusiv
		[[ ${1:-} =~ ^((:|^)[0-9]+){1,3}$|^(( |^)[0-9]+){1,3}$ ]]
}

function is_action_running() {
	[[ "$action_pid" =~ ^[1-9][0-9]+$ ]] && ps -o pid= -q "$action_pid"
}

function is_state_in() {
	[[ "${1:-}" =~ ( |^)${state}( |$) ]]
}

# Lock implementation is tested up to 100 parallel processes. Return Code 99
# indicates a timeout while waiting for a lock. Timeout time is dependant on
# Bashs loadable sleep, which garantees millis persicion. Return code "102"
# would indicate a error in the lock implementation, please don't hesitate to
# contact me if you are abe to provoke them. To install the "Bash Loadables":
#
#   apt install bash-builtins
#   enable -f sleep sleep # happens below
#
enable -f sleep sleep && true

declare LOCK_FILE
#using tmpfs to save lock to minimize IO and potential for rase-conditions
LOCK_FILE="/tmp/$(realpath "${TIMER_CONFIG_DIR}" | sed 's|/|_|g').timer.lock"

if ! [ -f "$LOCK_FILE" ]; then
	touch "$LOCK_FILE"
fi

function is_lock_owned() {
	[ -f "$LOCK_FILE" ] && [ "$(head -n 1 "$LOCK_FILE")" == "$$" ]
}

function current_lock() {
	return "$(head -n 1 "$LOCK_FILE")"
}

function queue_for_lock() {
	echo "$$" >>"$LOCK_FILE"
}

function release_lock() {
	if ! is_lock_aquiered; then
		echo "unable to release lock (Internal logic error lock is currenty hold by: " \
			"$LOCK_FILE contains wrong PID: '$pid' != '$$')" >&2
		exit 102
	fi

	sed -i '1d' "$LOCK_FILE" || echo "can not release lock (unable to remove pid from " \
		"$LOCK_FILE)" >&2 && exit 99
}

#Appends pid of processes requesting lock to LOCK_FILE
#waits until pid is first line in file or a timeout is reached
function aquire_lock() {
	declare -ri max_tries=200
	local -i count=0

	queue_for_lock

	while [ "$(current_lock)" != $$ ] && ((count++ < max_tries)); do
		sleep 0.005
	done

	if ((count >= max_tries)) && ! aquire_lock_fail_compensate; then
		echo "unable to aquire lock in 0.5 seconds. $LOCK_FILE was created by" \
			"another running timer instance." >&2
		exit 99
	fi

	#check if another pid managed to change the file content with
	#"noclobber" this shuld really never happen
	if ! is_lock_owned; then
		echo "unable to aquire lock (Internal logic error in aquire lock: " \
			"$LOCK_FILE contains wrong PID: '$pid' != '$$')" >&2
		exit 102
	fi
}
# Delete first pid lockfile, if process with pid is not running
function aquire_lock_fail_compensate() {
	# GEEK-Stuff - not relevant for a simple timer
	#
	# The following is dangerous in a multi-user-system, if both users  users
	# use the same timer config folder and kernel does  not propage processes
	# of other users. hidepid=noaccess:
	# https://www.kernel.org/doc/html/latest/filesystems/proc.html
	local -r other_pid="$(cat "$LOCK_FILE")"
	if [ -n "$other_pid" ] && ! ps -a -o pid= -q "$other_pid"; then
		echo "$LOCK_FILE: Lock is hold by a no long running process pid:" >&2
		echo "$other_pid. Removing $other_pid from lock file!" >&2
		sed -i '1d' "$LOCK_FILE"
		is_lock_owned
	fi

	return $?
}
