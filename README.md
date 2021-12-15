
# Coqoune - CoqIDE meets Kakoune

![](./screenshot.png)

Coqoune is a kakoune plugin for the Coq proof assistant,
featuring a CoqIDE-like experience with interactive goal & feedback display.

## 1. Installation

### Dependency
Coqoune is implemented using OCaml and the `Unix` library bundled with it.
For most *nix systems with a OCaml compiler available it should work without problem.
If you unfortunately encounter any trouble on installation,
check out the following list of dependencies are available:

- A OCaml compiler. Only version 4.12 is tested.
But anything starting from 4.7 should work fine.
- The standard `Unix` library of OCaml.
Should be bundled with most OCaml installations.
- Standard POSIX utilities

### Manual Installation
do
```
git clone https://github.com/guest0x0/coqoune
```
In `/path/to/coqoune`, run
```
make
```
then in your kakrc
```
source /path/to/coqoune/rc/coqoune.kak
```
when you need coqoune (e.g. inside a filetype hook)

### Installation via plug.kak
```
plug "guest0x0/coqoune" do %{
    make
}
```
You can config coqoune within plug.kak as well, see [the plug.kak repo](https://gitlab.com/andreyorst/plug.kak)


## Usage
Coqoune facilities can be pulled in by calling `coq-start`.
The buffer where `coq-start` is called should be the coq file you want to edit with coqoune.
Once `coq-start` is called, two buffers,
`goal@your_buffer_name` and `result@your_buffer_name` will be created,
which displays proof goal and feedback message from Coq in respect.
You can open new kakoune clients to display them alongside the main buffer,
using a window manager, tmux or other tools.

Once coqoune is started,
you can perform various commands provided by coqoune.
Before playing with these commands,
you should learn about how coqoune interact with Coq first.

The content of the Coq file won't be sent to Coq for processing
unless you ask coqoune to do so.
So coqoune, like CoqIDE, maintains a position in the Coq file, called `tip`.
Texts from start of buffer to the tip are already sent to Coq,
while texts behind the tip are not.
The region from start of buffer to the tip is called `processed`.
And the content of `goal@your_buffer_name` and `result@your_buffer_name` buffers are based on the `processed` region,
rather than the whole file.

By default, the `processed` region is rendered with a strikethrough effect,
so that you can see it clearly.

Coqoune provides a set of commands for manupulating the `processed` region:

1.  `coq-next`: send the next complete Coq command,
starting from the tip, to Coq, growing `processed`.

2.  `coq-back`: undo the last sent command, shrinking `processed`.

3.  `coq-to-cursor`: place the tip on the end of the command where the main cursor is located.
Send/Undo commands, as well as growing/shrinking `processed`, if necessary.

Besides these commands, when you edit the main buffer,
coqoune shrink `processed` automatically so that no edit
will be inside `processed`,
i.e. you always need to re-send editted part and anything after it again manually.

There are several other useful commands:

-  `coq-query`: receive a string as the first parameter,
which contains a query to be sent to Coq, at current tip.
The query is just one or more ordinary Coq commands,
but these commands won't change the state (i.e. tip and `processed`)

- `coq-dump-log`: dump internal log to a file.
In case the plugin goes wrong please post the dumped log.


## Configuration
The face `coqoune_added` is used to highlight the commands that
you already ask coqoune to send, but Coq not yet process.
By default it renders with an extra underline effect.
The face `coqoune_processed` is used to highlight the commands
that Coq have already processed.
By default it renders with an extra strikethrough effect.
Note that except for very large files,
the existence `coqoune_added` should be hardly noticable.

For key-bindings, coqoune does not bundle any.
You also need to call `coq-start` somewhere manually.
Here's an example config:
```
hook global WinSetOption filetype=coq %{
    coq-start

    declare-user-mode coq

    map buffer user c ": enter-user-mode coq<ret>" \
        -docstring "enter the Coq user mode"

    map buffer coq c ": enter-user-mode -lock coq<ret>" \
        -docstring "stay in the Coq user mode"

    map buffer coq k ": coq-back<ret>" \
        -docstring "undo last sent command"

    map buffer coq j ": coq-next<ret>" \
        -docstring "send the next command to Coq"

    map buffer coq <ret> ": coq-to-cursor<ret>" \
        -docstring "move tip to main cursor"
}
```

## License
This software is distributed under the 0-BSD license.
