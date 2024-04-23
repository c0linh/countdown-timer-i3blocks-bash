- [Countdown Timer for Bash and i3blocks](#countdown-timer-for-bash-and-i3blocks)
	- [Usage](#usage)
		- [timer.sh](#timersh)
			- [Features:](#features)
			- [Usage:](#usage-1)
		- [timer-functions.sh](#timer-functionssh)
		- [timerd.sh](#timerdsh)
			- [Features:](#features-1)
			- [Usage:](#usage-2)
		- [timer-i3block.sh](#timer-i3blocksh)
			- [Features:](#features-2)
			- [Configuration:](#configuration)
			- [Help and Documentation](#help-and-documentation)
	- [Attribution](#attribution)
	- [Contributing](#contributing)
	- [License](#license)

Countdown Timer for Bash and i3blocks
=====================================
This project provides a set of tools to manage countdown timers within a bash environment and integrates seamlessly with the i3 window manager through i3blocks. It consists of three main components and a function script:

- timer.sh: A countdown timer script written in pure bash.
- timerd.sh: A daemon script that complements timer.sh by adding daemon capabilities.
- timer-i3block.sh: Allows the timer to be controlled and displayed within [i3blocks](https://github.com/vivien/i3blocks?tab=readme-ov-file#example).
- timer-functions.sh: Contains functions and declares global parameters required by timer.sh

Installation
Clone this repository to your local machine using:
```
git clone https://github.com/<your-username>/<repository-name>.git
cp timer_block ~/.config/i3/i3blocks/config
```
Ensure you have bash and i3blocks installed on your system. For the icons to display correctly in the i3blocks integration, a Nerd Fonts-compatible font must be installed and used within your terminal or i3bar.

Usage
-----
### timer.sh
A simple, bash-based countdown timer that manages its state through files without requiring daemon capabilities.

#### Features
- Start, pause, stop, and set timer commands.
- Customizable action upon countdown completion.

#### Usage

```
timer.sh [-h, --help] { set [time] [action] | start [time] | pause | stop | get-state }
```
For detailed command descriptions and parameters, see Timer Script Help.

### timer-functions.sh
- config and runtime variable definition
- aquire and realease lockfile
- time related function using "date" (parse, convert, format)

Must be sourceable by timer.sh

### timerd.sh

A daemon that interfaces with timer.sh, allowing commands to be read from stdin and results outputted to stdout, enhancing usability in continuous operation contexts.

#### Features:
- All timer.sh commands plus daemon-stop command.
- Customizable tick rate for update frequency.

#### Usage

```
timerd.sh [-h, --help] [tick]
```
For detailed command descriptions and parameters, see .

### timer-i3block.sh

Integrates the timer with i3blocks, offering an interactive display and control mechanism directly within the i3bar.

#### Features
- Displays the timer state with Nerd Fonts icons.
- Controls the timer via mouse clicks and scroll actions.

#### Configuration
Ensure to set the necessary environment variables (BLOCK_NAME, interval=1, markup=pango) in your i3blocks configuration for the script to function properly.

For detailed information on setup and error handling, see i3blocks Integration Help.

#### Help and Documentation
For detailed help on each script, including parameters, commands, and error codes, refer to the following sections:

Attribution
-----------
Inspired by https://github.com/claudiodangelis/timer. This is a bash alternative without the need for a Go runtime.

Contributing
------------
Contributions are welcome! Please submit pull requests or open issues to propose changes or report bugs.

License
-------
This project is licensed under the MIT License - see the LICENSE file for details.
