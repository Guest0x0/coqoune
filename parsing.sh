
# $1: a line number for generating `range-specs' for highlighting,
# -line_var (optional): a variable to feedback line number
# -default (optional): a default face to use for unhighlighted text
# stdin: a `<richpp>...</richpp>' node returned by Coq
#        (escaped properly to let xmllint admit)
#        (single line)
# stdout:
#     (second line) A kakoune `range-specs' list (without timestamp) for highlighting the goal buffer
#     (third line) The text of the richpp node
function parse_richpp() {
    local line=$1
    local col=1

    shift 1
    while [ ! -z "$1" ]; do
        case "$1" in
            ( '-line_var' )
                local line_var=$2
                shift 2
                ;;
            ( '-default' )
                local default_hl=$2
                shift 2
                ;;
        esac
    done

    # don't escape '\'
    read -r pp_text
    # trim '<richpp><pp><_>' and '</_></pp></richpp>'
    pp_text=${pp_text:15:-18}

    output=""
    highlighters=""

    hl_line=1
    hl_col=1
    # Coq's richpp output may contains:
    #     1. pure text, without any highlighting (`untagged')
    #     2. highlighted text, wrapped in a xml child node indicating
    #        how it is highlighted (`tagged')
    printf "%s\n" "$pp_text" \
        | sed -n '
            s|&lt;|<lt/>|g;
            s|&gt;|<gt/>|g;
            s|&amp;nbsp;|<spc/>|g;
            s/&amp;/\&/g;
            s|&apos;|<apos/>|g;
            s|\\n|<newline/>|g;
            p' \
        | while [ 1 ]; do

        read -r -d '<' text
        output="$output$text"
        (( col = col + ${#text} ))

        read -r -d '>' tag
        case "$tag" in
            ( 'newline/' )
                output="$output\n"
                (( line = line + 1, col = 1 ))
                ;;
            ( 'lt/' )
                output="$output<"
                (( col = col + 1 ))
                ;;
            ( 'gt/' )
                output="$output>"
                (( col = col + 1 ))
                ;;
            ( 'spc/' )
                output="$output "
                (( col = col + 1 ))
                ;;
            ( 'apos/' )
                output="$output'"
                (( col = col + 1 ))
                ;;
            ( * )
                if [ "${tag:0:1}" = "/" ]; then
                    case $tag in
                        # TODO: check Coq's source code for a more complete list
                        # TODO: use custom faces
                        ( '/constr.keyword' )
                            highlighters="$highlighters $hl_line.$hl_col,$line.$col|keyword"
                            ;;
                        ( '/constr.variable' )
                            highlighters="$highlighters $hl_line.$hl_col,$line.$col|variable"
                            ;;
                        ( '/constr.reference' )
                            highlighters="$highlighters $hl_line.$hl_col,$line.$col|variable"
                            ;;
                        ( '/constr.notation' )
                            highlighters="$highlighters $hl_line.$hl_col,$line.$col|operator"
                            ;;
                        ( '/constr.type' )
                            highlighters="$highlighters $hl_line.$hl_col,$line.$col|type"
                            ;;
                        ( '/constr.path' )
                            highlighters="$highlighters $hl_line.$hl_col,$line.$col|module"
                            ;;
                    esac
                    hl_type=""
                    hl_line=$line
                    hl_col=$col
                else
                    hl_type=$tag
                    hl_line=$line
                    hl_col=$col
                fi
                ;;
        esac

        if [ -z "$text" ] && [ -z "$tag" ]; then
            if [ -n "$line_var" ]; then
                export $line_var=$line
            fi
            printf "%s\n%s\n" "$highlighters" "$output"
            break
        fi
    done
}



# stdin: goal output from coq (single line), of the form '<value>...</value>'
# stdout:
#     1. (first line) A kakoune `range-specs' list (without timestamp) for highlighting the goal buffer
#     2. (rest) The content of text to be displayed in the goal buffer (properly formatted, decoration added)
function parse_goals() {
    if local all_goals=($(xmllint --xpath '/value/option[@val="some"]/goals/child::list' - 2>/dev/null));
    then
        local goals=""
        local highlighters=""
        if goals=($(printf '%s\n' "${all_goals[0]}" | xmllint --xpath '/list/child::goal/child::*' - 2>/dev/null));
        then # There are current goals available, display them only
            for elem in ${all_goals[@]}; do
                printf '%s\n' "$elem" >&2
            done
            local goal_content="$((${#goals[@]} / 3)) goals:"
        else # There are no current goals, display the nearest layer of background goals
            local background_goals=($(echo ${all_goals[1]} | xmllint --xpath '/list/child::pair' - 2>/dev/null))
            for goal_stack in ${background_goals[@]}; do
                goals=($(echo "$goal_stack" | xmllint --xpath '/pair/list/goal/child::*' - 2>/dev/null)) \
                && break
            done
            # Current proof is already completed
            if [ ${#goals[@]} -eq 0 ]; then
                local message="There are no goals left."
                printf "\n%s\n" "$message"
                return
            fi
            local goal_content="There are no current goals left.\\n"
            local goal_content="$goal_content But there are $((${#goals[@]} / 3)) background goals:"
        fi

        local index=0
        local goal_id=1

        # parse all hypotheses and goals altogether, inserting proper decorations
        # To properly calculate line number, this process is done in three steps:
        #     1. (the first sub-shell) merge all hypotheses, goals and decorations into
        #        one big '<richpp>...</richpp>' node (input of $parse_richpp)
        #     2. let $parse_richpp parse the whole goal contents
        #     3. (last sub-shell) output the result
        ( printf '<richpp><pp><_>'
          printf '%s\\n' "$goal_content"
          while [ "$index" -lt "${#goals[@]}" ]; do
              printf '\\n'

              if [ "${#goals[@]}" -eq 3 ]; then
                  for hyp in $(echo ${goals[index + 1]} | xmllint --xpath '/list/child::richpp' - 2>/dev/null); do
                      printf '%s\\n' "${hyp:15:-18}"
                  done
              else
                  printf '...\\n'
              fi

              printf -- '-------------------------------(%s)\\n' "$goal_id"
              (( goal_id = goal_id + 1 ))

              printf 'goal: %s\n' "${goals[index + 2]}" >&2
              printf '%s\\n' "${goals[index + 2]:15:(-18)}"
              (( index = $index + 3 ))
          done
          printf '</_></pp></richpp>'
        ) | parse_richpp 1 | (
            read highlighters
            read -r content
            printf -- "%s\n" "$highlighters"
            printf -- "$content"
        )
    else # We are not inside a proof at all
        printf "\n\n"
    fi
}

