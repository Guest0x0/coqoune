
# How Coqoune works

## Overall architecture
Coqoune does not really execute your Coq commands.
Coqoune is based on the `coqidetop` executable and the
[coq xml protocol](https://github.com/coq/coq/blob/master/dev/doc/xml-protocol.md).
All Coqoune commands are no more than simple wrappers for the
commands provided by Coq's xml protocol.

`coqidetop` is stateful.
So for every Coq file, a `coqidetop` instance must persist.
To communicate with `coqidetop`,
Coqoune maintains a persistent daemon too.
This is the `_build/coqoune` (`coqoune.ml`) executable.
`_build/coqoune` will launch a `coqidetop` instance internally,
and communicate with it through two pipes.
You can find this part of source at the end of `coqoune.ml`.

For Kakoune and the user to communicate with the Coqoune daemon,
a FIFO pipe `input`, located in `%opt{coqoune_working_dir}`,
is used.
The kakscript part of the plugin sends XML commands to the daemon
through this FIFO pipe.
You can find the list of user commands in `usercmd.ml`.

## Individual modules

- `xml.ml`: XML parsing and printing
- `data.ml`: data types used to communicate with `coqidetop`
- `usercmd.ml`: user commands, for communication between kakscript and the daemon
- `interface.ml`: utilities for rendering pretty-printed document
and communicating with kakoune from the daemon side
- `coqoune.ml`: daemon entry point,
maintains a state machine.
- `parse_expr.ml`: individual helper executable (`_build/parse_expr`).
Read from stdin a stream of Coq source,
and split it into individual commands to be added one by one.
- `rc/coqoune.kak`: main kakscript file of the plugin.
Defines commands for user action and callbacks for the daemon.
- `rc/syntax.kak`: a Coq source highlighting file.
Basically the one in the kak repo,
but will receive more frequent update.

# Contribution
Contributions of all kinds are welcomed.
Straight PR is adequate.
Also feel free to give suggestions/ask for features & bug fixes & clarification
through issues.

# License
Coqoune (OCaml version) is released under the 0-BSD license.
