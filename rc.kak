

declare-option str coqoune_path %sh{
    echo ${kak_source:0:-7}
}

# source syntax file
source /home/guest0/Projects/kakoune/rc/filetype/coq.kak

define-command coq-start -params 0 %{

    declare-option -hidden str coqoune_buffer %val{bufname}

# init the coqoune scripts
    nop %sh{
        ( $kak_opt_coqoune_path/coqoune.sh -s $kak_session user-input
          $kak_opt_coqoune_path/coqoune.sh -s $kak_session init
        ) 1>/dev/null 2>&1 &
    }

# hooks for cleanup
    hook -group coqoune buffer BufClose '.*' %{
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
    }

# set up highlighters.
    # highlighter for marking commands already executed
    # `coqoune_executed' should contain only one region
    declare-option -hidden range-specs coqoune_executed_highlighters %val{timestamp}
    evaluate-commands %{
        add-highlighter buffer/coqoune_executed ranges coqoune_executed_highlighters
    }

    # face for marking executed commands
    set-face buffer coqoune_executed default,default+u

    # semantic highlighters based on coq's output
    declare-option -hidden range-specs coqoune_goal_highlighters     %val{timestamp}
    evaluate-commands -buffer '*goal*' %{
        add-highlighter buffer/coqoune_goal ranges coqoune_goal_highlighters
    }

    declare-option -hidden range-specs coqoune_result_highlighters   %val{timestamp}
    evaluate-commands -buffer '*result*' %{
        add-highlighter buffer/coqoune_result ranges coqoune_result_highlighters
    }

# callback commands
    define-command -hidden coq-refresh-goal -params 0 %{
        execute-keys -buffer '*goal*' %sh{ echo "%|cat<space>/tmp/coqoune-$kak_session/goal<ret>" }
    }

    define-command -hidden coq-refresh-result -params 0 %{
        execute-keys -buffer '*result*' %sh{ echo "%|cat<space>/tmp/coqoune-$kak_session/result<ret>" }
    }

    define-command -hidden coq-recover-error -params 2 %{
        evaluate-commands %sh{
            echo -n "set-option buffer coqoune_executed_highlighters $kak_timestamp "
            echo "1.1,$1.$2|coqoune_executed"
        }
    }


# user interaction

    # request for goal. Should be called automatically.
    define-command -hidden coq-goal -params 0 %{
        nop %sh{ $kak_opt_coqoune_path/coqoune.sh -s $kak_session goal }
    }

    define-command -hidden coq-move-command -params 1 %{
        nop %sh{ $kak_opt_coqoune_path/coqoune.sh -s $kak_session user-input }
        execute-keys -draft %sh{
            echo $kak_opt_coqoune_executed_highlighters | (
                read -d ' ' # timestamp
                read -d '.' # start line (should be beginning of buffer)
                read -d ',' # end line (should be beginning of buffer)
                read -d '.' line0 || line0=1
                read -d '|' col0  || col0=1
                case $1 in
                    ( 'next' | 'to' )
                        keys="$line0"gghGe
                        keys="$keys<a-|>$kak_opt_coqoune_path/coqoune.sh -s $kak_session"
                        if [ "$1" = 'next' ]; then
                            keys="$keys next $line0 $col0"
                        else
                            keys="$keys to $line0 $col0 $kak_cursor_line $kak_cursor_column"
                        fi
                        echo "$keys<ret>" | sed -n 's/ /<space>/g; p'
                        ;;
                    ( 'back' )
                        $kak_opt_coqoune_path/coqoune.sh -s $kak_session back
                        exit 1
                        ;;
                esac
            )
        }
        coq-goal
    }

    define-command coq-next -params 0 %{ coq-move-command next }
    define-command coq-back -params 0 %{ coq-move-command back }
    define-command coq-to-cursor -params 0 %{ coq-move-command to }


    define-command -hidden coq-on-text-change -params 0 %{
        nop %sh{ $kak_opt_coqoune_path/coqoune.sh -s $kak_session user-input }
        nop %sh{
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
            echo $kak_opt_coqoune_executed_highlighters | (
                    read -d ' '
                    read -d '.'
                    read -d ','
                    read -d '.' line0 || line0=1
                    read -d '|' col0  || col0=1
                    earliest_line=99999999
                    earliest_col=99999999
                    echo $kak_selections_desc | (
                        while read -d '.'; read -d ','; do
                            read -d '.' line
                            read -d ' ' col
                            if [ "$(compare_cursor $earliest_line $earliest_col $line $col)" -eq 1 ]; then
                                earliest_line=$line
                                earliest_col=$col
                            fi
                        done
                        if [ "$(compare_cursor $earliest_line $earliest_col $line0 $col0)" -eq '-1' ]; then
                            $kak_opt_coqoune_path/coqoune.sh -s $kak_session to $line0 $col0 $earliest_line $earliest_col
                        fi
                    )
            )
        }
    }

    hook -group coqoune buffer InsertChar .* coq-on-text-change
    hook -group coqoune buffer InsertDelete .* coq-on-text-change
}
