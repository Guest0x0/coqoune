
let row_s = int_of_string Sys.argv.(1)
let col_s = int_of_string Sys.argv.(2)

let (row_e, col_e) =
    if Array.length Sys.argv >= 5
    then (int_of_string Sys.argv.(3), int_of_string Sys.argv.(4))
    else (row_s, col_s + 1)


type parser_state =
    | In_Bullet

    | In_Comment        of int
    | In_Comment_Star   of int
    | In_Comment_LParen of int

    | In_String           of parser_state
    | In_String_Backslash of parser_state

    | In_Expr_Beg
    | In_Expr
    | In_Expr_LParen
    | In_Expr_Dot

    | End


exception Quit

let rec next_state state c =
    match state, c with
    | In_Bullet, ('-' | '+' | '*') ->
        In_Bullet
    | In_Bullet, (' ' | '\t' | '\n') ->
        raise Quit
    | In_Bullet, _ ->
        In_Expr

    | In_Comment d, '*' ->
        In_Comment_Star d
    | In_Comment d, '(' ->
        In_Comment_LParen d

    | In_Comment_Star d, ')' ->
        if d = 1
        then In_Expr
        else In_Comment(d - 1)

    | In_Comment_LParen d, '*' ->
        In_Comment (d + 1)

    | (In_Comment d | In_Comment_Star d | In_Comment_LParen d), '"' ->
        In_String (In_Comment d)
    | (In_Comment d | In_Comment_Star d | In_Comment_LParen d), _ ->
        In_Comment d

    | In_String parent, '"' ->
        parent
    | In_String parent, '\\' ->
        In_String_Backslash parent
    | In_String parent, _ ->
        In_String parent

    | In_String_Backslash parent, _ ->
        In_String parent

    | In_Expr_Beg, ('-' | '+' | '*') ->
        In_Bullet
    | In_Expr_Beg, ('{' | '}') ->
        End
    | In_Expr_Beg, (' ' | '\t' | '\n') ->
        In_Expr_Beg
    | In_Expr_Beg, c ->
        next_state In_Expr c

    | In_Expr_LParen, '*' ->
        In_Comment 1
    | In_Expr_LParen, c ->
        next_state In_Expr c

    | In_Expr_Dot, (' ' | '\t' | '\n') ->
        raise Quit
    | In_Expr_Dot, c ->
        next_state In_Expr c

    | In_Expr, '(' ->
        In_Expr_LParen
    | In_Expr, '"' ->
        In_String In_Expr
    | In_Expr, '.' ->
        In_Expr_Dot
    | In_Expr, _ ->
        In_Expr

    | End, _ ->
        raise Quit


let rec parse buffer (row, col) state last_char =
    match next_state state last_char with
    | exception Quit ->
        (row, col), last_char
    | state' ->
        let (row', col') =
            if last_char = '\n' || last_char = '\r'
            then (row + 1, 1)
            else (row, col + 1)
        in
        begin match last_char with
        | '>'  -> Buffer.add_string buffer "&gt;"
        | '<'  -> Buffer.add_string buffer "&lt;"
        | '"'  -> Buffer.add_string buffer "&quot;"
        | '\'' -> Buffer.add_string buffer "&apos;"
        (* | '\\' -> Buffer.add_string buffer "\\\\" *)
        | '&'  -> Buffer.add_string buffer "&amp;"
        | _    -> Buffer.add_char   buffer last_char
        end;
        parse buffer (row', col') state' (input_char stdin)


let rec loop (row, col) c =
    if row > row_e || row = row_e && col >= col_e
    then ()
    else begin
        let buf = Buffer.create 100 in
        let (row', col'), end_char = parse buf (row, col) In_Expr_Beg c in
        print_string "<Add><pair><string>";
        Buffer.output_buffer stdout buf;
        print_string "</string><pair><int>";
        print_int row'; print_string "</int><int>";
        print_int col'; print_string "</int></pair></pair></Add> ";
        loop (row', col') end_char
    end


let _ =
    try ignore @@ loop (row_s, col_s) (input_char stdin) with
      End_of_file -> ()
