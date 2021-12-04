

declare-option -hidden str coqoune_path %sh{
    echo ${kak_source%/*/*}
}

declare-option -docstring "
    The name of the shell used to execute coqoune scripts.
    Possible options are:
        1. bash
        2. zsh
        3. ksh
    The default will be the first available, from up to down.
" str coqoune_shell %sh{
    if bash --help >/dev/null 2>&1; then
        echo bash
    elif zsh --help >/dev/null 2>&1; then
        echo zsh
    elif ksh --help >/dev/null 2>&1; then
        echo ksh
    fi
}

# source syntax file
source "%opt{coqoune_path}/rc/syntax.kak"

define-command coq-start -params 0 %{

# Check for capabilities
    evaluate-commands %sh{
        if [ -z "$kak_opt_coqoune_path" -o -z "$kak_opt_coqoune_shell" ]; then
            echo fail
        elif xmllint --version 2>/dev/null && coqidetop --version >/dev/null 2>&1; then
            exit 0
        else
            echo fail
        fi
    }

    declare-option -hidden str coqoune_buffer %val{bufname}

# init the coqoune scripts
    nop %sh{
         $kak_opt_coqoune_shell $kak_opt_coqoune_path/coqoune.sh -s $kak_session init $kak_opt_coqoune_shell 1>/dev/null 2>&1 &
    }

# hooks for cleanup
    hook -group coqoune -once buffer BufClose .* %{
        nop %sh{
            ( $kak_opt_coqoune_path/coqoune.sh -s $kak_session user-input
              $kak_opt_coqoune_path/coqoune.sh -s $kak_session quit
            ) 1>/dev/null 2>&1
        }
    }

# create goal & result buffers
    evaluate-commands -draft %{
        edit -scratch '*goal*'
        edit -scratch '*result*'
        declare-option -hidden str coqoune_goal_buffer '*goal*'
        declare-option -hidden str coqoune_result_buffer '*result*'
    }
    evaluate-commands -draft -buffer %opt{coqoune_goal_buffer} %{
        set-option buffer filetype coq-goal
    }

# set up highlighters.
    # highlighter for marking commands already processed
    # `coqoune_processed' should contain only one region
    declare-option -hidden range-specs coqoune_processed_highlighters %val{timestamp}
    evaluate-commands -buffer %opt{coqoune_buffer} %{
        add-highlighter buffer/coqoune_processed ranges coqoune_processed_highlighters
    }

    # face for marking processed commands
    set-face buffer coqoune_processed default,default+u

    # semantic highlighters based on coq's output
    declare-option -hidden range-specs coqoune_goal_highlighters     %val{timestamp}
    evaluate-commands -buffer %opt{coqoune_goal_buffer} %{
        add-highlighter buffer/coqoune_goal ranges coqoune_goal_highlighters
    }

    declare-option -hidden range-specs coqoune_result_highlighters   %val{timestamp}
    evaluate-commands -buffer %opt{coqoune_result_buffer} %{
        add-highlighter buffer/coqoune_result ranges coqoune_result_highlighters
    }


# user interaction

    # manually request for goal. Should be called automatically.
    define-command -hidden coq-goal -params 0 %{
        nop %sh{ $kak_opt_coqoune_shell $kak_opt_coqoune_path/coqoune.sh -s $kak_session goal }
    }

    # receive a movement command ('next', 'back' or 'to') and send it to coqoune
    define-command -hidden coq-move-command -params 1 %{
        nop %sh{ $kak_opt_coqoune_shell $kak_opt_coqoune_path/coqoune.sh -s $kak_session user-input }
        execute-keys -draft %sh{
            echo $kak_opt_coqoune_processed_highlighters | (
                read -d ' ' # timestamp
                read -d '.' # start line (should be beginning of buffer)
                read -d ',' # end line (should be beginning of buffer)
                read -d '.' line0 || line0=1
                read -d '|' col0  || col0=1
                case $1 in
                    ( 'next' ) 
                        keys="$line0"gghGe
                        keys="$keys<a-|>$kak_opt_coqoune_shell $kak_opt_coqoune_path/parse_command.sh"
                        keys="$keys $line0 $col0 -next|"
                        keys="$keys$kak_opt_coqoune_shell $kak_opt_coqoune_path/coqoune.sh -s $kak_session add"
                        echo "$keys<ret>" | sed -n 's/ /<space>/g; p'
                        ;;
                    ( 'to' )
                        if [ "$line0" -gt "$kak_cursor_line" ] || \
                           [ "$line0" -eq "$kak_cursor_line" -a "$col0" -ge "$kak_cursor_column" ];
                        then
                            $kak_opt_coqoune_shell $kak_opt_coqoune_path/coqoune.sh -s $kak_session back-to:$kak_cursor_line.$kak_cursor_column
                            exit 0
                        else
                            keys="$line0"gghGe
                            keys="$keys<a-|>$kak_opt_coqoune_shell $kak_opt_coqoune_path/parse_command.sh"
                            keys="$keys $line0 $col0 $kak_cursor_line $kak_cursor_column|"
                            keys="$keys$kak_opt_coqoune_shell $kak_opt_coqoune_path/coqoune.sh -s $kak_session add"
                            echo "$keys<ret>" | sed -n 's/ /<space>/g; p'
                        fi
                        ;;
                    ( 'back' )
                        $kak_opt_coqoune_shell $kak_opt_coqoune_path/coqoune.sh -s $kak_session back
                        exit 0
                        ;;
                esac
            )
        }
        coq-goal
    }

    define-command coq-next \
        -docstring "send the next command to coq" \
        -params 0 %{
            coq-move-command next
        }
    define-command coq-back \
        -docstring "undo the last sent command" \
        -params 0 %{
            coq-move-command back
        }
    define-command coq-to-cursor \
        -docstring "move processed area boundary to main cursor, sending or undoing commands if necessary" \
        -params 0 %{
            coq-move-command to
        }

    # automatically backward execution on text change 
    define-command -hidden coq-on-text-change -params 0 %{
        nop %sh{ $kak_opt_coqoune_path/coqoune.sh -s $kak_session user-input }
        echo -debug -- %sh{
            function compare_cursor() {
                line1=$1
                col1=$2
                line2=$3
                col2=$4
                if [ "$line1" -gt "$line2" ]; then
                    echo 1
                elif [ "$line1" -lt "$line2" ]; then
                    echo -1
                elif [ "$col1" -gt "$col2" ]; then
                    echo 1
                elif [ "$col1" -lt "$col2" ]; then
                    echo -1
                else
                    echo 0
                fi
            }
            echo $kak_opt_coqoune_processed_highlighters | (
                    read -d ' '
                    read -d '.'
                    read -d ','
                    read -d '.' line0 || line0=1
                    read -d '|' col0  || col0=1
                    earliest_line=99999999
                    earliest_col=99999999
                    echo $kak_selections_desc | (
                        # find the earliest selection
                        while read -d '.'; read -d ','; do
                            read -d '.' line
                            read -d ' ' col
                            if [ "$(compare_cursor $earliest_line $earliest_col $line $col)" = 1 ]; then
                                earliest_line=$line
                                earliest_col=$col
                            fi
                        done
                        # if (any part of) the edit happens inside processed region, backward execution
                        if [ "$(compare_cursor $earliest_line $earliest_col $line0 $col0)" = '-1' ]; then
                            $kak_opt_coqoune_path/coqoune.sh -s $kak_session back-to:$earliest_line.$earliest_col
                        fi
                    )
            )
        }
    }

    hook -group coqoune buffer InsertChar   .* coq-on-text-change
    hook -group coqoune buffer InsertDelete .* coq-on-text-change


    define-command coq-query \
        -docstring "send the first argument as a query to coqoune" \
        -params 1 %{
            nop %sh{
                $kak_opt_coqoune_path/coqoune.sh -s $kak_session user-input
                $kak_opt_coqoune_path/coqoune.sh -s $kak_session query "$1"
            }
        }

    define-command coq-hints \
        -docstring "ask coq for hints" \
        -params 0 %{
            nop %sh{
                $kak_opt_coqoune_path/coqoune.sh -s $kak_session user-input
                $kak_opt_coqoune_path/coqoune.sh -s $kak_session hints
            }
        }


    define-command coq-dump-log \
        -docstring "dump coqoune log to the specified file" \
        -params 1 %{
            nop %sh{
                cp /tmp/coqoune-$kak_session/log $1
            }
        }

}
