#!/usr/bin/env bash

set -o errexit -o pipefail -o noclobber -o nounset

# Contains basic funtions and declares global parameters shared with and
# REQUIRED by this timer.sh 
# - config-file save and load
# - aquire and realease lockfile
# - time related function using "date" (parse, convert, format)
declare -r DEFAULT_CONFIG_DIR=${XDG_CONFIG_DIR:-$HOME}

if ! [ -d "${TIMER_CONFIG_DIR:=$DEFAULT_CONFIG_DIR}" ]; then
	mkdir "$TIMER_CONFIG_DIR" || (echo "can not creaet configuration directory $TIMER_CONFIG_DIR!" >/dev/stderr && exit 10)
fi

declare -r LOCK_FILE="${TIMER_CONFIG_DIR}/.timer.lock"
trap "{ rm -f $LOCK_FILE; }" INT TERM EXIT

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
		echo "read-only $ACTION_FILE file. Keep current action." >/dev/stderr
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
		source "$STATE_FILE" || (echo "can not load state file $STATE_FILE!" >/dev/stderr && exit 11)
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

function aquire_lock() {
	declare -i count=0

	while [ -f "$LOCK_FILE" ] && ((count++ < 10)); do
		sleep 0.05
	done

	if ((count >= 10)); then
		echo "unable to aquire lock ($LOCK_FILE already exists)" >/dev/stderr
		exit 99
	fi
	touch "$LOCK_FILE"
}

function release_lock() {
	if [ -f "$LOCK_FILE" ]; then
		rm "$LOCK_FILE" ||
			(echo "can not release lock (unable to delete" \
				"$LOCK_FILE)" >/dev/stderr && exit 99)
	fi
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
