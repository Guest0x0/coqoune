
type filled   = Filled
type unfilled = Unfilled

type _ t =
    | Init       : 'kind t
    | About      : 'kind t
    | Quit       : 'kind t
    | User_React : 'kind t
    | AddF : Data.state_id * (int * int) * (int * int) * string -> filled t
    | AddE : (int * int) * string -> unfilled t
    | Back_To_Prev  : unfilled t
    | Back_To_Loc   : (int * int) -> unfilled t
    | Back_To_State : Data.state_id -> 'kind t
    | Goal   : 'kind t
    | QueryF : Data.state_id * Data.route_id * string -> filled t
    | QueryE : string -> unfilled t


let to_xml coq_version cmd =
    let open Data in
    let call func arg =
        Xml.{
            tag = "call";
            attrs = ["val", func];
            body = [Xml_Elem(xml_of_data arg)]
        }
    in
    match cmd with
    | Init ->
        call "Init" @@ D_Option None
    | About ->
        call "About" D_Unit
    | Quit ->
        call "Quit" D_Unit
    | AddF({ state_id }, (row, col), _, src) ->
        begin match Data.compare_version coq_version (8, 16) with
        | n when n < 0 ->
            call "Add" @@ D_Pair(
                D_Pair(D_String src, D_Int 2),
                D_Pair(D_State_Id state_id, D_Bool true)
            )
        | _ ->
            call "Add" @@ D_Pair(
                D_Pair(
                    D_Pair(
                        D_Pair(D_String src, D_Int 2),
                        D_Pair(D_State_Id state_id, D_Bool true)
                    ),
                    D_Int 0
                ),
                D_Pair(D_Int row, D_Int col)
            )
        end
    | User_React ->
        failwith "Usercmd.to_xml"
    | Back_To_State { state_id } ->
        call "Edit_at" @@ D_State_Id state_id
    | Goal ->
        call "Goal" D_Unit
    | QueryF({ state_id }, { route_id }, query) ->
        call "Query" @@ D_Pair(
            D_Route_Id route_id,
            D_Pair(
                D_String query,
                D_State_Id state_id
            )
        )



let of_xml xml =
    let open Xml in
    let open Data in
    match xml.tag, xml.attrs, xml.body with
    | "User_React", [], [] ->
        Some User_React
    | "Quit", [], [] ->
        Some Quit
    | "Add", [], [Xml_Elem data] ->
        let (src, (row_e, col_e)) = extract_data
                (T_Pair(T_String, T_Pair(T_Int, T_Int)))
                (data_of_xml data)
        in
        Some(AddE((row_e, col_e), src))
    | "Back", [], [] ->
        Some Back_To_Prev
    | "Back_To", [], [Xml_Elem data] ->
        let (row, col) = extract_data (T_Pair(T_Int, T_Int)) (data_of_xml data) in
        Some(Back_To_Loc(row, col))
    | "Goal", [], [] ->
        Some Goal
    | "Query", [], [Xml_Elem data] ->
        let query = extract_data T_String (data_of_xml data) in
        Some(QueryE query)
    | _ ->
        None
