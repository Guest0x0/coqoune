
# How Coqoune works
Coqoune does not really execute your Coq commands.
Coqoune is based on the `coqidetop` executable and the
[coq xml protocol](https://github.com/coq/coq/blob/master/dev/doc/xml-protocol.md).
All Coqoune commands are no more that simple wrappers for the
commands provided by Coq's xml protocol.

`coqidetop` is stateful.
So for every Coq file, a `coqidetop` instance must persist.
Together with this instance is the `event_loop.sh` script,
which is the main daemon of Coqoune.
One can communicate with `event_loop.sh` through the directory
`/tmp/coqoune-$kak_session`.
Inside this directory, there would be four files:
`in`, `goal`, `res` and `log`.
The details of these files are documented in `event_loop.sh`.

The main loop of `event_loop.sh` receives commands from the fifo `in`.
It then process the command,
send xml input to the `coqidetop` instance if necessary.
There is another simple loop in `event_loop.sh`,
which is piped output from `coqidetop`.
Since `coqidetop`'s output is not separated by newline,
this loop breaks the output properly,
and send callback to `in` for further process.

`event_loop.sh` makes use of several utility scripts:

1. `location_list.sh`: maintanence of the `location_list` data.
Its use is documented in `event_loop.sh`.

2. `parsing.sh`: utilities for parsing pretty-printed output from Coq.

3. `kak_util.sh`: utilities functions for interaction with kak.

Above the daemon script is the user-interface `coqoune.sh`. 
`coqoune.sh` will send commands to `event_loop.sh` based on
its input. More details are documented in `coqoune.sh` and `event_loop.sh`.

Finally there is `parse_command.sh`.
This script is used by the kak side of Coqoune,
to parse the source file and determines where the next command starts and ends.
The details are documented in the script itself.

Besides the shell scripts part,
there is the kak part of Coqoune, inside `rc/coqoune.kak`.
`rc/coqoune.kak` maintains several information,
both documented in the script itself.
It also defines the user commands of Coqoune.

Last but not least, there is `rc/syntax.kak`,
which provides basic syntax highlighting and indention for Coq files.
The coq syntax file bundled by kak is (at the time of writing this doc)
written by the author of Coqoune (Guest0x0) too.
The Coqoune one may receive fix & improvement faster.

# Contribution
Contributions of all kinds are welcomed.
Straight PR is adequate.
Also feel free to give suggestions
/ask for features & bug fixes & clarification
through issues.

Coqoune is released under the zlib public license.
