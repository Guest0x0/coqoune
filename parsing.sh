#!/bin/sh


# $1: a line number for generating `range-specs' for highlighting
# stdin: a `<richpp>...</richpp>' node returned by Coq
#        (escaped properly to let xmllint admit)
#        (single line)
# stdout:
#     1. (first line) A kakoune `range-specs' list (without timestamp) for highlighting the goal buffer
#     2. (second line) The text of the richpp node
function parse_richpp() {
    line=$1
    col=1

    # don't escape '\'
    read -r pp_text
    # trim '<richpp><pp><_>' and '</_></pp></richpp>'
    pp_text=${pp_text:15:-18}

    # sed command to unescape the text
    unescape_cmd='s/&amp;nbsp;/ /g; s/&amp;/\&/g; s/&lt;/</g; s/&gt;/>/g; p'

    output=""
    highlighters=""

    # Coq's richpp output may contains:
    #     1. pure text, without any highlighting (`untagged')
    #     2. highlighted text, wrapped in a xml child node indicating
    #        how it is highlighted (`tagged')
    echo $pp_text | while [ 1 ]; do

        read -r -d '<' untagged_text
        untagged_text=$(echo $untagged_text | sed -n "$unescape_cmd")
        (( col = $col + ${#untagged_text} ))

        read -r -d '>' tag
        read -r -d '<' tagged_text
        read -r -d '>'
        tagged_text=$(echo $tagged_text | sed -n "$unescape_cmd")
        case $tag in
            # TODO: check Coq's source code for a more complete list
            # TODO: use custom face
            ( 'constr.variable' )
                highlighters="$highlighters $line.$col+${#tagged_text}|variable"
                ;;
            ( 'constr.notation' )
                highlighters="$highlighters $line.$col+${#tagged_text}|operator"
                ;;
        esac
        (( col = $col + ${#tagged_text} ))

        output="$output$untagged_text$tagged_text"

        if [ -z "$untagged_text" -a -z "$tag" -a -z "$tagged_text" ]; then
            echo "$highlighters"
            echo "$output"
            break
        fi
    done
}




# stdin: goal output from coq (with '<value>...</value>' trimmed) (single line)
# stdout:
#     1. (first line) A kakoune `range-specs' list (without timestamp) for highlighting the goal buffer
#     2. (rest) The content of text to be displayed in the goal buffer (properly formatted, decoration added)
function parse_goals() {
    if all_goals=($(xmllint --xpath '/option[@val="some"]/goals/child::list' - 2>/dev/null));
    then
        if goals=($(echo ${all_goals[0]} | xmllint --xpath '/list/child::goal/child::*' - 2>/dev/null));
        then # There are current goals available, display them only
            goal_content="$((${#goals[@]} / 3)) goals:"
            highlighters="1.1+${#goal_content}|keyword"
        else # There are no current goals, display the nearest layer of background goals
            background_goals=($(echo ${all_goals[1]} | xmllint --xpath '/list/child::pair' - 2>/dev/null))
            for goal_stack in ${background_goals[@]}; do
                goals=($(echo $goal_stack | xmllint --xpath '/pair/list/goal/child::*' - 2>/dev/null)) \
                && break
            done
            # Current proof is already completed
            if [ ${#goals[@]} -eq 0 ]; then
                message="There are no goals left."
                echo "1.1+${#message}|keyword"
                echo $message
                return
            fi
            goal_content="There are no current goals left."
            goal_content="$goal_content But there are $((${#goals[@]} / 3)) background goals:"
            highlighters="1.1+${#goal_content}|keyword"
        fi

        index=0
        # The frist line is already used to display number of goals
        linenum=2

        # parse all hypotheses and goals altogether, inserting proper decorations
        # every line in the goal buffer corresponds to two lines here:
        #     1. (first line) highlighters
        #     2. (second line) text
        while [ "$index" -lt "${#goals[@]}" ]; do
            # Goals are separated by one newline
            echo ""
            echo ""
            (( linenum = linenum + 1 ))

            for hyp in $(echo ${goals[index + 1]} | xmllint --xpath '/list/child::richpp' - 2>/dev/null); do
                echo $hyp | parse_richpp $linenum
                (( linenum = $linenum + 1 ))
            done

            # trim `<string>...</string>'
            goal_id=${goals[index]:8:-9}
            echo "$linenum.32+1|operator $linenum.33+${#goal_id}|value $linenum.$((33 + ${#goal_id}))+1|operator"
            echo "-------------------------------($goal_id)"
            (( linenum = linenum + 1 ))

            echo ${goals[index + 2]} | parse_richpp $linenum
            (( linenum = linenum + 1 ))

            (( index = $index + 3 ))
        done | ( # join all the outputs
            while read highlighters_delta;
                  read -r line;
            do
                 [ -n "$highlighters_delta" ] && highlighters="$highlighters $highlighters_delta"
                 goal_content="$goal_content\n$line"
            done
            echo $highlighters
            echo -e $goal_content
        )
    else # We are not inside a proof at all
        echo ""
        echo ""
    fi
}

