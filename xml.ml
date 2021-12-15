
module Unix = UnixLabels

type xml_element =
    { tag   : string
    ; attrs : (string * string) list
    ; body  : xml_content list }

and xml_content =
    | Xml_Str  of string
    | Xml_Elem of xml_element


let make_input buffer_size fd = object(self)
    val buffer = Bytes.create buffer_size
    val mutable cursor   = 0
    val mutable buffered = 0

    method private can_read =
        buffered > cursor

    method really_can_read =
        let rec loop i =
            if i >= buffered
            then false
            else if List.mem (Bytes.get buffer i) [' '; '\t'; '\n']
            then loop (i + 1)
            else true
        in loop cursor

    method private refill =
        if not self#can_read then begin
            buffered <- Unix.read fd ~buf:buffer ~pos:0 ~len:buffer_size;
            cursor   <- 0
        end

    method peek_char =
        self#refill;
        if self#can_read
        then Bytes.get buffer cursor
        else '\x00'

    method next_char =
        self#refill;
        if self#can_read
        then ( cursor <- cursor + 1
             ; Bytes.get buffer (cursor - 1) )
        else '\x00'
end




exception Syntax_Error of string

let rec skip_whitespace input =
    match input#peek_char with
    | ' ' | '\t' | '\n' ->
        ignore input#next_char;
        skip_whitespace input
    | _ -> ()


let read_name input =
    let buffer = Buffer.create 100 in
    let rec loop () =
        match input#peek_char with
        | 'a'..'z' | 'A'..'Z' | '0'..'9' | '_' | '-' | '.' ->
            Buffer.add_char buffer input#next_char;
            loop ()
        | _ ->
            Buffer.contents buffer
    in loop ()

let read_string input =
    let buffer = Buffer.create 100 in
    let rec loop () =
        match input#next_char with
        | '"' ->
            Buffer.contents buffer
        | '\\' ->
            begin match input#next_char with
            | 'n' -> Buffer.add_char buffer '\n'
            | 't' -> Buffer.add_char buffer '\t'
            | c   -> Buffer.add_char buffer c
            end;
            loop ()
        | c ->
            Buffer.add_char buffer c;
            loop ()
    in
    loop ()

let read_attr input =
    skip_whitespace input;
    match input#peek_char with
    | 'a'..'z' | 'A'..'Z' | '0'..'9' | '-' | '_' ->
        let name = read_name input in
        skip_whitespace input;
        if input#next_char <> '=' then
            raise(Syntax_Error "expected '=' after attribute name");
        skip_whitespace input;
        if input#next_char <> '"' then
            raise(Syntax_Error "expected '\"' around attribute value");
        let value = read_string input in
        Some(name, value)
    | _ -> None


let rec read_attrs input =
    match read_attr input with
    | None      -> []
    | Some attr -> attr :: read_attrs input


(* with the first '<' already processed *)
let rec read_element_or_close_tag input =
    match input#peek_char with
    | '/' ->
        ignore input#next_char;
        let tag =
            if input#peek_char = '>'
            then ""
            else read_name input
        in
        if input#next_char <> '>' then
            raise(Syntax_Error "expected '>' after closing tag");
        `Close_Tag tag
    | c ->
        let tag, attrs =
            if c = '>'
            then ("", [])
            else 
                let tag = read_name input in
                let attrs = read_attrs input in
                (tag, attrs)
        in
        match input#next_char with
        | '>' ->
            let body = read_contents tag input in
            `Element { tag; attrs; body }
        | '/' ->
            if input#next_char <> '>' then
                raise(Syntax_Error "expected '>' after closing tag");
            `Element { tag; attrs; body = [] }
        | _ ->
            raise(Syntax_Error "expected '>' or '/>' to close tag");

and read_contents tag input =
    let str = read_content_str input in
    let rest =
        match read_element_or_close_tag input with
        | `Close_Tag tag' ->
            if tag = tag'
            then []
            else raise @@ Syntax_Error(
                    "opening tag and closing tag mismatch: "
                    ^ tag ^ " v.s. " ^ tag'
                )
        | `Element elem ->
            Xml_Elem elem :: read_contents tag input
    in
    if str = ""
    then rest
    else Xml_Str str :: rest

and read_content_str input =
    let buffer = Buffer.create 100 in
    let rec loop () =
        match input#next_char with
        | '<' ->
            Buffer.contents buffer
        | '&' ->
            let escape_seq = read_name input in
            if input#next_char <> ';' then
                raise(Syntax_Error "expected ';' at the end of escape sequence");
            begin match escape_seq with
            | "nbsp" ->
                Buffer.add_char buffer ' '
            | "quot" ->
                Buffer.add_char buffer '"'
            | "gt" ->
                Buffer.add_char buffer '>'
            | "lt" ->
                Buffer.add_char buffer '<'
            | "apos" ->
                Buffer.add_char buffer '\''
            | "amp" ->
                (* `coqidetop` uses "&amp;nbsp" instead of "&nbsp;"
                 * for non-breaking white space *)
                let next_escape_seq = read_name input in
                let next_escape_end = input#peek_char in
                if next_escape_end = ';' && next_escape_seq = "nbsp"
                then ( Buffer.add_char buffer ' '
                     ; ignore input#next_char )
                else ( Buffer.add_char buffer '&'
                     ; Buffer.add_string buffer next_escape_seq )
            | _ ->
                (* For unknown escape sequence,
                 * don't abort but instead display it as it is.
                 * When there are missed escape sequences
                 * this would make the program more robust
                 * and make debugging easier *)
                Buffer.add_char buffer '&';
                Buffer.add_string buffer escape_seq;
                Buffer.add_char buffer ';';
            end;
            loop ()
        (*
        | '\\' ->
            begin match input#next_char with
            | 'n' -> Buffer.add_char buffer '\n'
            | 't' -> Buffer.add_char buffer '\t'
            | c   -> Buffer.add_char buffer c
            end;
            loop ()
       *)
        | c ->
            Buffer.add_char buffer c;
            loop ()
    in loop ()


let read_element input =
    skip_whitespace input;
    begin match input#next_char with
    | '<'    -> ()
    | '\x00' -> raise End_of_file
    | c      -> raise @@ Syntax_Error(
            "unexpected char '" ^  String.make 1 c ^ "', '<' expected"
        )
    end;
    match read_element_or_close_tag input with
    | `Close_Tag _ ->
        raise(Syntax_Error "unexpected closing tag, open tag expected")
    | `Element elem ->
        elem



let output_string fd str =
    ignore @@ Unix.write_substring fd
        ~buf:str ~pos:0 ~len:(String.length str)

let output_xml_string fd str =
    let buffered = ref 0 in
    let flush i =
        ignore @@ Unix.write_substring fd
            ~buf:str ~pos:!buffered ~len:(i - !buffered);
        buffered := i
    in
    let rec loop i =
        if i >= String.length str
        then flush i
        else begin
            begin match String.unsafe_get str i with
            | '"' -> flush i; output_string fd "\\\""
            | _   -> ()
            end;
            loop (i + 1)
        end
    in loop 0


let output_xml_body fd str =
    let buffered = ref 0 in
    let flush i =
        ignore @@ Unix.write_substring fd
            ~buf:str ~pos:!buffered ~len:(i - !buffered);
        buffered := i
    in
    let rec loop i =
        if i >= String.length str
        then flush i
        else begin
            begin match String.unsafe_get str i with
            | '&'  -> flush i; incr buffered; output_string fd "&amp;"
            | '"'  -> flush i; incr buffered; output_string fd "&quot;"
            | '\'' -> flush i; incr buffered; output_string fd "&apos;"
            | '>'  -> flush i; incr buffered; output_string fd "&gt;" 
            | '<'  -> flush i; incr buffered; output_string fd "&lt;" 
            | _    -> ()
            end;
            loop (i + 1)
        end
    in loop 0


let rec output_element fd elem =
    output_string fd ("<" ^ elem.tag);
    elem.attrs |> List.iter begin fun (name, value) ->
        output_string fd (" " ^ name ^ "=\"");
        output_xml_string fd value;
        output_string fd "\""
    end;
    match elem.body with
    | [] ->
        output_string fd "/>"
    | body ->
        output_string fd ">";
        List.iter (output_xml_content fd) body;
        output_string fd ("</" ^ elem.tag ^ ">")

and output_xml_content fd = function
    | Xml_Str str ->
        output_xml_body fd str
    | Xml_Elem elem ->
        output_element fd elem
