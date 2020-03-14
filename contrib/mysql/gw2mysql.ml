(* Copyright (c) 2020 Ludovic LEDIEU *)

open Def
open Gwdb

let null = "__NULL__"

let n_id = ref 0
let s_id = ref 0
let e_id = ref 0
let m_id = ref 0
let ln_id = ref 0
let h_id = ref 0

let open_oc dir_out table =
  open_out_gen [ Open_wronly ; Open_creat ; Open_trunc ; Open_text ] 0o644 (dir_out ^ "/" ^ table ^ ".txt")

let string_of_sex = function
| Male -> "M"
| Female -> "F"
| Neuter -> ""

let string_of_access = function
| IfTitles -> "IfTitles"
| Public -> "Public"
| Private -> "Private"
| Friend -> "Friend"
| Friend_m -> "Friend_m"

let string_of_calendar = function
| Dgregorian -> "Gregorian"
| Djulian -> "Julian"
| Dfrench -> "French"
| Dhebrew -> "Hebrew"

let get_calendar = function
| Some (Dgreg (_, calendar)) -> string_of_calendar calendar
| _ -> "Gregorian"

let get_day = function
| Some (Dgreg (dmy, _)) -> dmy.day
| _ -> 0

let get_month = function
| Some (Dgreg (dmy, _)) -> dmy.month
| _ -> 0

let get_year = function
| Some (Dgreg (dmy, _)) -> dmy.year
| _ -> 0

let get_day2 _ = 0

let get_month2 _ = 0

let get_year2 = function
| Some y -> y
| _ -> 0

let string_of_isDead = function
| NotDead -> "NotDead"
| Death _ -> "Dead"
| DeadYoung -> "DeadYoung"
| DeadDontKnowWhen -> "DeadDontKnowWhen"
| DontKnowIfDead -> "DontKnowIfDead"
| OfCourseDead -> "OfCourseDead"

let string_of_death_reason = function
| Death (r, _) -> begin match r with
    | Killed -> "Killed"
    | Murdered -> "Murdered"
    | Executed -> "Executed"
    | Disappeared -> "Disappeared"
    | Unspecified -> ""
  end
| _ -> ""

type gen_record = History_diff.gen_record =
  { date : string;
    wizard : string;
    gen_p : (iper, string) gen_person;
    gen_f : (iper, string) gen_family list;
    gen_c : iper array list }

let gw_to_mysql base dir_out fname =
  let empty_string = insert_string base "" in
  let oc_n = open_oc dir_out "notes" in
  let insert_note istr =
    let s = sou base istr in
    if s = "" then null
    else begin
      incr n_id ;
      Printf.fprintf oc_n "$%d$££$%s$££\n" !n_id s ;
      string_of_int !n_id
    end
  in
  let oc_s = open_oc dir_out "sources" in
  let insert_source istr =
    let s = sou base istr in
    if s = "" then null
    else begin
      incr s_id ;
      Printf.fprintf oc_s "$%d$££$%s$££\n" !s_id s ;
      string_of_int !s_id
    end
  in
  let oc_p = open_oc dir_out "persons" in
  let oc_e = open_oc dir_out "events" in
  let oc_e_od = open_oc dir_out "occupation_details" in
  let oc_e_t = open_oc dir_out "title_details" in
  let oc_pe = open_oc dir_out "person_event" in
  let oc_m = open_oc dir_out "medias" in
  let oc_pm = open_oc dir_out "person_media" in
  let oc_pn = open_oc dir_out "person_name" in
  let oc_g = open_oc dir_out "groups" in
  let oc_pg = open_oc dir_out "person_group" in
  (* events *)
  let event base i_p1 i_p2 t n date place note source reason witnesses =
    let place = sou base place in
    if date <> Adef.codate_None || place <> "" || (sou base note) <> "" || (sou base source) <> "" then
      let date = Adef.od_of_codate date in
        let go_insert d =
	  let n_id_opt = insert_note note in
	  let s_id_opt = insert_source source in
          incr e_id ;
          Printf.fprintf oc_e "$%d$££$%s$££$%s$££$%s$££$%s$££$%d$££$%d$££$%d$££$Gregorian$££$0$££$0$££$0$££$%s$££$%s$££$%s$££$%s$££$%s$££\n" !e_id
	    (if t = "Name" then "EVEN" else t)
	    (if t = "EVEN" || t = "FACT" then n else "")
	    (match d with
	      | Some (Dgreg (dmy, _)) ->
		begin match dmy.prec with
		| Sure -> ""
		| About -> "ABT"
		| Maybe -> "Maybe" (* FIXME: mauvais usage dans GeneWeb => comment ajuster ? *)
		| Before -> "BEF"
		| After -> "AFT"
		| OrYear _ -> raise (Failure "OrYear")
		| YearInt _ -> raise (Failure "YearInt")
		end
	      | _ -> "")
	    (get_calendar d) (get_day d) (get_month d) (get_year d)
	    (match d with
	      | Some Dtext s -> s
	      | _ -> "")
	    reason place n_id_opt s_id_opt ;
          Printf.fprintf oc_pe "$%d$££$%d$££$Main$££\n" !e_id i_p1 ;
	  begin match i_p2 with
	  | Some i -> Printf.fprintf oc_pe "$%d$££$%d$££$Main$££\n" !e_id i ;
	  | _ -> ()
	  end ;
	  Array.iter (fun iper ->
            Printf.fprintf oc_pe "$%d$££$%d$££$%s$££\n" !e_id (Adef.int_of_iper iper) "Witness"
          ) witnesses
        in
        match date with
        | Some (Dgreg (dmy, calendar)) -> begin
	    match dmy.prec with
	    | OrYear dmy2 -> begin
		go_insert (Some (Dgreg ({dmy with prec = Sure ; day = 0 ; month = 0 ; year = dmy2}, calendar)));
		go_insert (Some (Dgreg ({dmy with prec = Sure}, calendar)))
	      end
	    | YearInt dmy2 -> begin
		go_insert (Some (Dgreg ({dmy with prec = Before ; day = 0 ; month = 0 ; year = dmy2}, calendar)));
		go_insert (Some (Dgreg ({dmy with prec = After}, calendar)))
	      end
	    | _ -> go_insert date
	  end
        | _ -> go_insert date
  in
  Printf.eprintf "Parsing persons :\n%!" ;
  (* For each person *)
  let nb_ind = nb_of_persons base in
  (* iper -> p_id *)
  ProgrBar.start ();
  for i = 0 to nb_ind - 1 do
    ProgrBar.run i nb_ind;
    let p = poi base (Adef.iper_of_int i) in
    let sn = p_surname base p in
    let fn = p_first_name base p in
    let oc = get_occ p in
    let death = get_death p in
    let n_id_opt = insert_note (get_notes p) in
    let s_id_opt = insert_source (get_psources p) in
    let consang = get_consang p in
    let consang =
      if consang = Adef.fix (-1) then -1.0
      else Adef.float_of_fix consang *. 100.0
    in
    let pkey =
      (Mutil.tr ' ' '_' (Name.lower fn)) ^ "." ^
      (string_of_int oc) ^ "." ^
      (Mutil.tr ' ' '_' (Name.lower sn))
    in
    Printf.fprintf oc_p "$%d$££$%s$££$%s$££$%d$££$%s$££$%s$££$%s$££$%f$££$%s$££$%s$££\n"
      i pkey (fn ^ "." ^ (string_of_int oc) ^ " " ^ sn) oc
      (string_of_isDead death)
      n_id_opt s_id_opt consang
      (string_of_sex (get_sex p))
      (string_of_access (get_access p)) ;
    (* Dispatch occupation on events *)
    let insert_occupation occu y_start y_end =
      incr e_id ;
      Printf.fprintf oc_e "$%d$££$OCCU$££$$££$%s$££$Gregorian$££$0$££$0$££$%d$££$Gregorian$££$0$££$0$££$%d$££$$££$$££$$££$%s$££$%s$££\n" !e_id
        (if y_end <> 0 then "FROM-TO" else "") y_start y_end null null ;
      Printf.fprintf oc_e_od "$%d$££$%s$££\n" !e_id occu ;
      Printf.fprintf oc_pe "$%d$££$%d$££$Main$££\n" !e_id i ;
    in
    let occu = sou base (get_occupation p) in
    if occu <> "" then insert_occupation occu 0 0 ;
    (* FIXME trop simplifié ? *)
    let has_image_file =
      let f = "images/" ^ fname ^ "/" ^ pkey in
      if Sys.file_exists (f ^ ".gif") then Some (f ^ ".gif")
      else if Sys.file_exists (f ^ ".jpg") then Some (f ^ ".jpg")
      else if Sys.file_exists (f ^ ".png") then Some (f ^ ".png")
      else None
    in
    begin match has_image_file with
    | Some f ->
        incr m_id ;
        Printf.fprintf oc_m "$%d$££$%s$££\n" !m_id f ;
        Printf.fprintf oc_pm "$%d$££$%d$££\n" i !m_id
    | None -> ()
    end ;
    let insert_person_name givn nick surn t =
      Printf.fprintf oc_pn "$%d$££$%s$££$%s$££$%s$££$%s$££\n" i givn nick surn t
    in
    if sn <> "?" || fn <> "?" then begin
      insert_person_name fn "" sn "Main"
    end ;
    List.iter (fun a ->
      insert_person_name (sou base a) "" sn "FirstNamesAlias"
    ) (get_first_names_aliases p) ;
    List.iter (fun a ->
      insert_person_name fn "" (sou base a) "SurnamesAlias"
    ) (get_surnames_aliases p) ;
    List.iter (fun a ->
      insert_person_name (sou base a) "" "" "Alias"
    ) (get_aliases p) ;
    List.iter (fun a ->
      insert_person_name fn (sou base a) "" "Qualifier"
    ) (get_qualifiers p) ;
    let public_name = sou base (get_public_name p) in
    if public_name <> "" then begin
      insert_person_name public_name "" "" "PublicName"
    end ;
    (* titles FIXME rework needed *)
    let get_dmy2 d =
      match d with
      | Some (Dgreg (dmy, _)) ->
	begin match dmy.prec with
	| OrYear dmy2 -> Some dmy2
	| YearInt dmy2 -> Some dmy2
	| _ -> None
	end
      | _ -> None
    in
    List.iter (fun t ->
      let d_start = Adef.od_of_codate t.t_date_start in
      let d_start_dmy2 = get_dmy2 d_start in
      let d_end = Adef.od_of_codate t.t_date_end in
      let d_end_dmy2 = get_dmy2 d_end in
        incr e_id ;
        Printf.fprintf oc_e "$%d$££$TITL$££$$££$%s$££$%s$££$%d$££$%d$££$%d$££$%s$££$%d$££$%d$££$%d$££$$££$$££$$££$%s$££$%s$££\n" !e_id
	  (match d_start, d_end with
	    | None, None -> ""
            | Some _, None -> "FROM"
            | None, Some _ -> "TO"
            | Some _, Some _ -> "FROM-TO"
	  )
	  (get_calendar d_start) (get_day d_start) (get_month d_start) (get_year d_start)
	  (get_calendar d_end) (get_day d_end) (get_month d_end) (get_year d_end)
	  null null ;
        Printf.fprintf oc_e_t "$%d$££$%s$££$%s$££$%d$££$%s$££$%s$££$%s$££$%s$££$%d$££$%d$££$%d$££$%d$££$%d$££$%d$££$%s$££$%s$££$%s$££$%d$££$%d$££$%d$££$%d$££$%d$££$%d$££$%s$££\n" !e_id
          (sou base t.t_ident) (sou base t.t_place) t.t_nth
	  (match t.t_name with | Tmain -> "True" | _ -> "False")
          (match t.t_name with | Tname n -> sou base n | _ -> "")
	  (match d_start with
	     | Some (Dgreg (dmy, _)) -> begin
	         match dmy.prec with
		 | Sure -> ""
		 | About -> "ABT"
		 | Maybe -> "Maybe"
		 | Before -> "BEF"
		 | After -> "AFT"
		 | OrYear _ -> "OrYear"
		 | YearInt _ -> "YearInt"
	       end
	     | _ -> "")
	  (get_calendar d_start) (get_day d_start) (get_month d_start) (get_year d_start)
	  (get_day2 d_start_dmy2) (get_month2 d_start_dmy2) (get_year2 d_start_dmy2)
	  (match d_start with | Some Dtext s -> s | _ -> "")
	  (match d_end with
	     | Some (Dgreg (dmy, _)) -> begin
	         match dmy.prec with
		 | Sure -> ""
		 | About -> "ABT"
		 | Maybe -> "Maybe"
		 | Before -> "BEF"
		 | After -> "AFT"
		 | OrYear _ -> "OrYear"
		 | YearInt _ -> "YearInt"
	       end
	     | _ -> "")
	  (get_calendar d_end) (get_day d_end) (get_month d_end) (get_year d_end)
	  (get_day2 d_end_dmy2) (get_month2 d_end_dmy2) (get_year2 d_end_dmy2)
	  (match d_end with | Some Dtext s -> s | _ -> "")
    ) (get_titles p) ;
    (* Initialize family group / parent link *)
    Array.iteri (fun seq ifam ->
      let g_id = (Adef.int_of_ifam ifam) in
      let cpl = foi base ifam in
      let i_father = Adef.int_of_iper (get_father cpl) in
      let i_mother = Adef.int_of_iper (get_mother cpl) in
      if (i = i_father && i_father < i_mother) ||
         (i = i_mother && i_mother < i_father) then begin
        let n_id_opt = insert_note (get_comment cpl) in
        let s_id_opt = insert_source (get_fsources cpl) in
        Printf.fprintf oc_g "$%d$££$%s$££$%s$££$%s$££\n" g_id n_id_opt s_id_opt (sou base (get_origin_file cpl))
      end ;
      Printf.fprintf oc_pg "$%d$££$%d$££$Parent$££$%d$££\n" g_id i seq
    ) (get_family p) ;
    (* Événement v6 *)
    event base i None "BIRT" "" (get_birth p) (get_birth_place p) empty_string (get_birth_src p) "" [||];
    event base i None "BAPM" "" (get_baptism p) (get_baptism_place p) empty_string (get_baptism_src p) "" [||];
    begin match death with
    | Death (r, d) ->
	let reason = match r with
          | Killed -> "Killed"
          | Murdered -> "Murdered"
          | Executed -> "Executed"
          | Disappeared -> "Disappeared"
          | Unspecified -> ""
	in
        event base i None "DEAT" "" (Adef.codate_of_od (Some (Adef.date_of_cdate d))) (get_death_place p) empty_string (get_death_src p) reason [||];
    | _ -> ()
    end ;
    begin match get_burial p with
    | Buried d ->
        event base i None "BURI" "" d (get_burial_place p) empty_string (get_burial_src p) "" [||];
    | Cremated d ->
        event base i None "CREM" "" d (get_burial_place p) empty_string (get_burial_src p) "" [||];
    | UnknownBurial -> ()
    end ;
    (* *)
    let insert_person_event opt_p role =
      match opt_p with
      | Some iper -> Printf.fprintf oc_pe "$%d$££$%d$££$%s$££\n" !e_id (Adef.int_of_iper iper) role
      | None -> ()
    in
    let as_an_event e_t e_n r s_id_opt role =
      incr e_id ;
      Printf.fprintf oc_e "$%d$££$%s$££$%s$££$$££$Gregorian$££$0$££$0$££$0$££$Gregorian$££$0$££$0$££$0$££$$££$$££$$££$%s$££$%s$££\n"
        !e_id e_t e_n null s_id_opt ;
      insert_person_event (Some (Adef.iper_of_int i)) "Main" ;
      insert_person_event r.r_fath role ;
      insert_person_event r.r_moth role
    in
    List.iter (fun r ->
      (* Only populated from API ! *)
      let s_id_opt = insert_source r.r_sources in
      match r.r_type with
      | Adoption -> as_an_event "ADOP" "" r s_id_opt "AdoptionParent"
      | Recognition -> as_an_event "EVEN" "Recognition" r s_id_opt "RecognitionParent"
      | CandidateParent -> as_an_event "FACT" "CandidateParent" r s_id_opt "CandidateParent"
      | GodParent -> as_an_event "BAPM" "" r s_id_opt "GodParent"
      | FosterParent -> as_an_event "EVEN" "FosterParent" r s_id_opt "FosterParent"
    ) (get_rparents p) ;
  done ;
  ProgrBar.finish () ;
  close_out oc_p ;
  close_out oc_e_od ;
  close_out oc_e_t ;
  close_out oc_pm ;
  close_out oc_pn ;
  close_out oc_m ;
  (* For each family *)
  Printf.eprintf "Parsing families :\n%!" ;
  let nb_fam = nb_of_families base in
  (* ifam -> g_id *)
  ProgrBar.start ();
  for i = 0 to nb_fam - 1 do
    ProgrBar.run i nb_fam;
    let fam = foi base (Adef.ifam_of_int i) in
    if is_deleted_family fam then ()
    else begin
      let ip_father = Adef.int_of_iper (get_father fam) in
      let ip_mother = Adef.int_of_iper (get_mother fam) in
      Array.iteri
        (fun seq c ->
           Printf.fprintf oc_pg "$%d$££$%d$££$Child$££$%d$££\n" i (Adef.int_of_iper c) seq)
        (get_children fam) ;
      event base ip_father (Some ip_mother) "MARR" "" (get_marriage fam) (get_marriage_place fam) (get_comment fam) (get_fsources fam) "" (get_witnesses fam)
    end
  done ;
  ProgrBar.finish () ;
  close_out oc_n ;
  close_out oc_s ;
  close_out oc_e ;
  close_out oc_pe ;
  close_out oc_g ;
  close_out oc_pg ;
  let oc_ln = open_oc dir_out "linked_notes" in
  let oc_lnn = open_oc dir_out "linked_notes_nt" in
  let oc_lni = open_oc dir_out "linked_notes_ind" in
  Printf.eprintf "Parsing linked notes...\n%!" ;
  let insert_linked_note ln_type ln_key ln_iper ln_ifam (list_nt, list_ind) =
    incr ln_id ;
    Printf.fprintf oc_ln "$%d$££$%s$££$%s$££$%s$££$%s$££\n" !ln_id ln_type ln_key ln_iper ln_ifam ;
    List.iter (fun nt -> Printf.fprintf oc_lnn "$%d$££$%s$££\n" !ln_id nt) list_nt ;
    List.iter (fun ((fn, sn, oc), { NotesLinks.lnTxt = text ; NotesLinks.lnPos = pos } ) ->
      Printf.fprintf oc_lni "$%d$££$%s$££$%s$££$%d$££\n" !ln_id 
	(fn ^ "." ^ (string_of_int oc) ^ "." ^ sn)
        (match text with | Some s -> s | None -> null)
	pos
    ) list_ind
  in
  List.iter (function
    | NotesLinks.PgInd iper, l -> insert_linked_note "PgInd" "" (string_of_int (Adef.int_of_iper iper)) null l
    | NotesLinks.PgFam ifam, l -> insert_linked_note "PgFam" "" null (string_of_int (Adef.int_of_ifam ifam)) l
    | NotesLinks.PgNotes, l -> insert_linked_note "PgNotes" "" null null l
    | NotesLinks.PgMisc s, l -> insert_linked_note "PgMisc" s null null l
    | NotesLinks.PgWizard s, l -> insert_linked_note "PgWizard" s null null l
  ) (NotesLinks.read_db (fname ^ ".gwb/")) ;
  close_out oc_ln ;
  close_out oc_lnn ;
  close_out oc_lni

let gw_history_to_mysql dir_out fname =
  let oc_h = open_oc dir_out "history" in
  let oc_hd = open_oc dir_out "history_details" in
  let load_person_history fname =
    let history = ref [] in
    begin match
      (try Some (Secure.open_in_bin fname) with Sys_error _ -> None)
    with
      Some ic ->
        begin try
          while true do
            let v : gen_record = input_value ic in history := v :: !history
          done
        with End_of_file -> ()
        end;
        close_in ic
    | None -> ()
    end;
    !history
  in
  Printf.eprintf "Parsing history...\n%!" ;
  let rec list_remove_same d_old d_new =
    match d_old, d_new with
    | [], l_new -> [], l_new
    | l_old, [] -> l_old, []
    | e_old :: l_old, e_new :: l_new ->
        if e_old = e_new then list_remove_same l_old l_new
        else
          let old_in_new = List.mem e_old l_new in
          let new_in_old = List.mem e_new l_old in
          let l_old = List.filter (fun e -> e <> e_new) l_old in
          let l_new = List.filter (fun e -> e <> e_old) l_new in
          let l1, l2 = list_remove_same l_old l_new in
          begin match old_in_new, new_in_old with
          | true, true -> l1, l2
          | false, true -> e_old :: l1, l2
          | true, false -> l1, e_new :: l2
          | false, false -> e_old :: l1, e_new :: l2
          end
  in
  let rec loop dir =
    Array.iter (fun f ->
      let dir = dir ^ "/" ^ f in
      if Sys.is_directory dir then loop dir
      else
        let insert_history r =
          incr h_id ;
          Printf.fprintf oc_h "$%d$££$%s$££$%s$££$%s$££\n" !h_id r.date r.wizard f
        in
        let insert_history_detail data d_old d_new =
          Printf.fprintf oc_hd "$%d$££$%s$££$%s$££$%s$££\n" !h_id data d_old d_new
        in
        let string_of_date d =
          let d = Adef.od_of_codate d in
          match d with
          | Some d -> begin match d with
              | Dgreg (dmy, cal) -> begin
                  let cal = string_of_calendar cal in
                  let prec = match dmy.prec with
                  | Sure -> "Sure"
                  | About -> "About"
                  | Maybe -> "Maybe"
                  | Before -> "Before"
                  | After -> "After"
                  | OrYear _ -> "OrYear"
                  | YearInt _ -> "YearInt"
                  in
                  match dmy.prec with
                  | OrYear y2 | YearInt y2 ->
                      Printf.sprintf "%s - %s %d/%d/%d %d/%d/%d" cal prec dmy.day dmy.month dmy.year 0 0 y2
                  | _ -> Printf.sprintf "%s - %s %d/%d/%d" cal prec dmy.day dmy.month dmy.year
                end
              | Dtext s -> "(" ^ s ^ ")"
            end
          | None -> ""
        in
(*
        let string_of_witnesses aw =
          Array.fold_left (fun s (iper, _) ->
            let s =
              if s <> "" then s ^ ","
              else ""
            in
            s ^ (string_of_int (Adef.int_of_iper iper))
	  ) "" aw
        in
*)
        let string_of_children ac =
          Array.fold_left (fun s iper ->
            let s =
              if s <> "" then s ^ ","
              else ""
            in
            s ^ (string_of_int (Adef.int_of_iper iper))
	  ) "" ac
        in
(* v7
        let diff_pevent n prefix e_old e_new =
          let data = prefix ^ "pevent[" ^ (string_of_int n) ^ "]." in
          let old_e_t, old_e_n = string_of_pevent (fun s -> s) e_old.epers_name in
          let new_e_t, new_e_n = string_of_pevent (fun s -> s) e_new.epers_name in
          insert_history_detail (data ^ "e_type") old_e_t new_e_t ;
          if old_e_n <> "" && new_e_n <> "" then
            insert_history_detail (data ^ "t_name") old_e_n new_e_n ;
          if e_old.epers_date <> e_new.epers_date then begin
            let old_date = string_of_date e_old.epers_date in
            let new_date = string_of_date e_new.epers_date in
            insert_history_detail (data ^ "date") old_date new_date
          end ;
          if e_old.epers_place <> e_new.epers_place then
            insert_history_detail (data ^ "place") e_old.epers_place e_new.epers_place ;
          if e_old.epers_reason <> e_new.epers_reason then
            insert_history_detail (data ^ "reason") e_old.epers_reason e_new.epers_reason ;
          if e_old.epers_note <> e_new.epers_note then
            insert_history_detail (data ^ "note") e_old.epers_note e_new.epers_note ;
          if e_old.epers_src <> e_new.epers_src then
            insert_history_detail (data ^ "src") e_old.epers_src e_new.epers_src ;
          if e_old.epers_witnesses <> e_new.epers_witnesses then
            insert_history_detail (data ^ "witnesses") (string_of_witnesses e_old.epers_witnesses) (string_of_witnesses e_new.epers_witnesses) ;
        in
        let add_pevent n prefix e =
          let data = prefix ^ "+pevent[" ^ (string_of_int n) ^ "]." in
          let e_t, e_n = string_of_pevent (fun s -> s) e.epers_name in
          insert_history_detail (data ^ "e_type") "" e_t ;
          if e_n <> "" then
            insert_history_detail (data ^ "t_name") "" e_n ;
          let new_date = string_of_date e.epers_date in
          if new_date <> "" then
            insert_history_detail (data ^ "date") "" new_date ;
          if e.epers_place <> "" then
            insert_history_detail (data ^ "place") "" e.epers_place ;
          if e.epers_reason <> "" then
            insert_history_detail (data ^ "reason") "" e.epers_reason ;
          if e.epers_note <> "" then
            insert_history_detail (data ^ "note") "" e.epers_note ;
          if e.epers_src <> "" then
            insert_history_detail (data ^ "src") "" e.epers_src ;
          let ws = string_of_witnesses e.epers_witnesses in
          if ws <> "" then
           insert_history_detail (data ^ "witnesses") "" ws ;
        in
        let del_pevent n prefix e =
          let data = prefix ^ "-pevent[" ^ (string_of_int n) ^ "]." in
          let e_t, e_n = string_of_pevent (fun s -> s) e.epers_name in
          insert_history_detail (data ^ "e_type") e_t "" ;
          if e_n <> "" then
            insert_history_detail (data ^ "t_name") e_n "" ;
          let old_date = string_of_date e.epers_date in
          if old_date <> "" then
            insert_history_detail (data ^ "date") old_date "" ;
          if e.epers_place <> "" then
            insert_history_detail (data ^ "place") e.epers_place "" ;
          if e.epers_reason <> "" then
            insert_history_detail (data ^ "reason") e.epers_reason "" ;
          if e.epers_note <> "" then
            insert_history_detail (data ^ "note") e.epers_note "" ;
          if e.epers_src <> "" then
            insert_history_detail (data ^ "src") e.epers_src "" ;
          let ws = string_of_witnesses e.epers_witnesses in
          if ws <> "" then
            insert_history_detail (data ^ "witnesses") ws "" ;
        in
        let diff_fevent n prefix e_old e_new =
          let data = prefix ^ "fevent[" ^ (string_of_int n) ^ "]." in
          let old_e_t, old_e_n = string_of_fevent (fun s -> s) e_old.efam_name in
          let new_e_t, new_e_n = string_of_fevent (fun s -> s) e_new.efam_name in
          insert_history_detail (data ^ "e_type") old_e_t new_e_t ;
          if old_e_n <> "" && new_e_n <> "" then
            insert_history_detail (data ^ "t_name") old_e_n new_e_n ;
          if e_old.efam_date <> e_new.efam_date then begin
            let old_date = string_of_date e_old.efam_date in
            let new_date = string_of_date e_new.efam_date in
            insert_history_detail (data ^ "date") old_date new_date
          end ;
          if e_old.efam_place <> e_new.efam_place then
            insert_history_detail (data ^ "place") e_old.efam_place e_new.efam_place ;
          if e_old.efam_reason <> e_new.efam_reason then
            insert_history_detail (data ^ "reason") e_old.efam_reason e_new.efam_reason ;
          if e_old.efam_note <> e_new.efam_note then
            insert_history_detail (data ^ "note") e_old.efam_note e_new.efam_note ;
          if e_old.efam_src <> e_new.efam_src then
            insert_history_detail (data ^ "src") e_old.efam_src e_new.efam_src ;
          if e_old.efam_witnesses <> e_new.efam_witnesses then
            insert_history_detail (data ^ "witnesses") (string_of_witnesses e_old.efam_witnesses) (string_of_witnesses e_new.efam_witnesses) ;
        in
        let add_fevent n prefix e =
          let data = prefix ^ "+fevent[" ^ (string_of_int n) ^ "]." in
          let e_t, e_n = string_of_fevent (fun s -> s) e.efam_name in
          insert_history_detail (data ^ "e_type") "" e_t ;
          if e_n <> "" then
            insert_history_detail (data ^ "t_name") "" e_n ;
          let new_date = string_of_date e.efam_date in
          if new_date <> "" then
            insert_history_detail (data ^ "date") "" new_date ;
          if e.efam_place <> "" then
            insert_history_detail (data ^ "place") "" e.efam_place ;
          if e.efam_reason <> "" then
            insert_history_detail (data ^ "reason") "" e.efam_reason ;
          if e.efam_note <> "" then
            insert_history_detail (data ^ "note") "" e.efam_note ;
          if e.efam_src <> "" then
            insert_history_detail (data ^ "src") "" e.efam_src ;
          let ws = string_of_witnesses e.efam_witnesses in
          if ws <> "" then
            insert_history_detail (data ^ "witnesses") "" ws ;
        in
        let del_fevent n prefix e =
          let data = prefix ^ "-fevent[" ^ (string_of_int n) ^ "]." in
          let e_t, e_n = string_of_fevent (fun s -> s) e.efam_name in
          insert_history_detail (data ^ "e_type") e_t "" ;
          if e_n <> "" then
            insert_history_detail (data ^ "t_name") e_n "" ;
          let old_date = string_of_date e.efam_date in
          if old_date <> "" then
            insert_history_detail (data ^ "date") old_date "" ;
          if e.efam_place <> "" then
            insert_history_detail (data ^ "place") e.efam_place "" ;
          if e.efam_reason <> "" then
            insert_history_detail (data ^ "reason") e.efam_reason "" ;
          if e.efam_note <> "" then
            insert_history_detail (data ^ "note") e.efam_note "" ;
          if e.efam_src <> "" then
            insert_history_detail (data ^ "src") e.efam_src "" ;
          let ws = string_of_witnesses e.efam_witnesses in
          if ws <> "" then
           insert_history_detail (data ^ "witnesses") ws "" ;
        in
        let rec diff_events n prefix diff del add d_old d_new =
          match d_old, d_new with
          | e_old :: l_old, e_new :: l_new -> begin
              diff n prefix e_old e_new ;
              diff_events (n+1) prefix diff del add l_old l_new
            end
          | e_old :: l_old, [] -> begin
              del n prefix e_old ;
              diff_events (n+1) prefix diff del add l_old []
            end
          | [], e_new :: l_new -> begin
              add n prefix e_new ;
              diff_events (n+1) prefix diff del add [] l_new
            end
          | [], [] -> ()
        in
*)
        let rec diff_families n fc_old fc_new =
          let data = "fam[" ^ (string_of_int n) ^ "]." in
          match fc_old, fc_new with
          | (f_old, c_old) :: l_old, (f_new, c_new) :: l_new -> begin
              insert_history_detail (data ^ "index") (string_of_int (Adef.int_of_ifam f_old.fam_index)) (string_of_int (Adef.int_of_ifam f_new.fam_index)) ;
(* v7
              if f_old.fevents <> f_new.fevents then begin
                let d_old, d_new = list_remove_same f_old.fevents f_new.fevents in
                diff_events 0 data diff_fevent del_fevent add_fevent d_old d_new
              end ;
*)
              if f_old.comment <> f_new.comment then
                insert_history_detail (data ^ "comment") f_old.comment f_new.comment ;
              if f_old.fsources <> f_new.fsources then
                insert_history_detail (data ^ "fsources") f_old.fsources f_new.fsources ;
              if c_old <> c_new then
                insert_history_detail (data ^ "children") (string_of_children c_old) (string_of_children c_new) ;
              diff_families (n+1) l_old l_new
            end
          | [], (f_new, c_new) :: l_new -> begin
              let data = "+" ^ data in
              insert_history_detail (data ^ "index") "" (string_of_int (Adef.int_of_ifam f_new.fam_index)) ;
(* v7
              diff_events 0 data diff_fevent del_fevent add_fevent [] f_new.fevents ;
*)
              if f_new.comment <> "" then
                insert_history_detail (data ^ "comment") "" f_new.comment ;
              if f_new.fsources <> "" then
                insert_history_detail (data ^ "fsources") "" f_new.fsources ;
              let c_new = string_of_children c_new in
              if c_new <> "" then
                insert_history_detail (data ^ "children") "" c_new ;
              diff_families (n+1) [] l_new
            end
          | (f_old, c_old) :: l_old, [] -> begin
              let data = "-" ^ data in
              insert_history_detail (data ^ "index") (string_of_int (Adef.int_of_ifam f_old.fam_index)) "" ;
(* v7
              diff_events 0 data diff_fevent del_fevent add_fevent f_old.fevents [] ;
*)
              if f_old.comment <> "" then
                insert_history_detail (data ^ "comment") f_old.comment "" ;
              if f_old.fsources <> "" then
                insert_history_detail (data ^ "fsources") f_old.fsources "" ;
              let c_old = string_of_children c_old in
              if c_old <> "" then
                insert_history_detail (data ^ "children") c_old "" ;
              diff_families (n+1) l_old []
            end
          | [], [] -> ()
        in
(* batteries
        let split_notes s = (* WARNING maybe specific *)
          (* Printf.eprintf "DEBUG split_notes %s\n%!" s ; *)
          let r = BatText.of_string s in
          let last = (BatText.length r) - 1 in
          let part posd posf =
            if posd >= posf then raise (Failure "part")
            else BatText.to_string (BatText.sub r posd (posf-posd+1))
          in
          let rec loop pos posf l =
            (* Printf.eprintf "DEBUG part %d-%d\n%!" pos posf ; *)
            if pos <= 0 then l
            else try begin
                let pos1 = BatText.rindex_from r (pos-1) (BatUChar.of_char '\n') in
                if (BatText.get r (pos1+1)) = (BatUChar.of_char '*') then
                  loop (pos1-1) (pos1-1) ((part (pos1+1) posf) :: l)
                else loop pos1 posf l
              end with Not_found -> (part 0 posf) :: l
          in loop last last []
        in
*)
        let rec diff_string_list data d_old d_new =
          match d_old, d_new with
          | e_old :: l_old, e_new :: l_new -> begin
              insert_history_detail data e_old e_new ;
              diff_string_list data l_old l_new
            end
          | e_old :: l_old, [] -> begin
              insert_history_detail ("-" ^ data) e_old "" ;
              diff_string_list data l_old []
            end
          | [], e_new :: l_new -> begin
              insert_history_detail ("+" ^ data) "" e_new ;
              diff_string_list data [] l_new
            end
          | [], [] -> ()
        in
        let string_of_tname = function
        | Tmain -> "(main)"
        | Tname s -> s
        | Tnone -> "(none)"
        in
	let diff_title data t_old t_new =
          if t_old.t_name <> t_new.t_name then
            insert_history_detail (data ^ "name") (string_of_tname t_old.t_name) (string_of_tname t_new.t_name) ;
          if t_old.t_ident <> t_new.t_ident then
            insert_history_detail (data ^ "ident") t_old.t_ident t_new.t_ident ;
          if t_old.t_place <> t_new.t_place then
            insert_history_detail (data ^ "place") t_old.t_place t_new.t_place ;
          if t_old.t_date_start <> t_new.t_date_start then
            insert_history_detail (data ^ "date_start") (string_of_date t_old.t_date_start) (string_of_date t_new.t_date_start) ;
          if t_old.t_date_end <> t_new.t_date_end then
            insert_history_detail (data ^ "date_end") (string_of_date t_old.t_date_end) (string_of_date t_new.t_date_end) ;
          if t_old.t_nth <> t_new.t_nth then
            insert_history_detail (data ^ "nth") (string_of_int t_old.t_nth) (string_of_int t_new.t_nth) ;
        in
	let del_title data t =
          insert_history_detail (data ^ "name") (string_of_tname t.t_name) "" ;
          if t.t_ident <> "" then
            insert_history_detail (data ^ "ident") t.t_ident "" ;
          if t.t_place <> "" then
            insert_history_detail (data ^ "place") t.t_place "" ;
          let d_start = string_of_date t.t_date_start in
          if d_start <> "" then
            insert_history_detail (data ^ "date_start") d_start "" ;
          let d_end = string_of_date t.t_date_end in
          if d_end <> "" then
            insert_history_detail (data ^ "date_end") d_end "" ;
          if t.t_nth <> 0 then
            insert_history_detail (data ^ "nth") (string_of_int t.t_nth) "" ;
        in
	let add_title data t =
          insert_history_detail (data ^ "name") "" (string_of_tname t.t_name) ;
          if t.t_ident <> "" then
            insert_history_detail (data ^ "ident") "" t.t_ident ;
          if t.t_place <> "" then
            insert_history_detail (data ^ "place") "" t.t_place ;
          let d_start = string_of_date t.t_date_start in
          if d_start <> "" then
            insert_history_detail (data ^ "date_start") "" d_start ;
          let d_end = string_of_date t.t_date_end in
          if d_end <> "" then
            insert_history_detail (data ^ "date_end") "" d_end ;
          if t.t_nth <> 0 then
            insert_history_detail (data ^ "nth") "" (string_of_int t.t_nth) ;
        in
        let rec diff_titles_list pos d_old d_new =
          let data = "title[" ^ (string_of_int pos) ^ "]." in
          match d_old, d_new with
          | e_old :: l_old, e_new :: l_new -> begin
              diff_title data e_old e_new ;
              diff_titles_list (pos+1) l_old l_new
            end
          | e_old :: l_old, [] -> begin
              del_title ("-"^data) e_old ;
              diff_titles_list (pos+1) l_old []
            end
          | [], e_new :: l_new -> begin
              add_title ("+"^data) e_new ;
              diff_titles_list (pos+1) [] l_new
            end
          | [], [] -> ()
        in
        let rec loop =
          function
          | [] -> ()
          | [r] ->
              insert_history r ;
              insert_history_detail "created" "" "" (* FIXME trop simplifié ? *)
          | new_r :: old_r :: l ->
              begin
                insert_history new_r ;
	        if old_r.gen_p.first_name <> new_r.gen_p.first_name then
                  insert_history_detail "first_name" old_r.gen_p.first_name new_r.gen_p.first_name ;
	        if old_r.gen_p.surname <> new_r.gen_p.surname then
                  insert_history_detail "surname" old_r.gen_p.surname new_r.gen_p.surname ;
	        if old_r.gen_p.occ <> new_r.gen_p.occ then
                  insert_history_detail "occ" (string_of_int old_r.gen_p.occ) (string_of_int new_r.gen_p.occ) ;
	        if old_r.gen_p.image <> new_r.gen_p.image then
                  insert_history_detail "image" old_r.gen_p.image new_r.gen_p.image ;
	        if old_r.gen_p.public_name <> new_r.gen_p.public_name then
                  insert_history_detail "public_name" old_r.gen_p.public_name new_r.gen_p.public_name ;
	        if old_r.gen_p.qualifiers <> new_r.gen_p.qualifiers then begin
                  let d_old, d_new = list_remove_same old_r.gen_p.qualifiers new_r.gen_p.qualifiers in
                  diff_string_list "qualifiers" d_old d_new
                end ;
	        if old_r.gen_p.aliases <> new_r.gen_p.aliases then begin
                  let d_old, d_new = list_remove_same old_r.gen_p.aliases new_r.gen_p.aliases in
                  diff_string_list "aliases" d_old d_new
                end ;
	        if old_r.gen_p.first_names_aliases <> new_r.gen_p.first_names_aliases then begin
                  let d_old, d_new = list_remove_same old_r.gen_p.first_names_aliases new_r.gen_p.first_names_aliases in
                  diff_string_list "first_names_aliases" d_old d_new
                end ;
	        if old_r.gen_p.surnames_aliases <> new_r.gen_p.surnames_aliases then begin
                  let d_old, d_new = list_remove_same old_r.gen_p.surnames_aliases new_r.gen_p.surnames_aliases in
                  diff_string_list "surnames_aliases" d_old d_new
                end ;
	        if old_r.gen_p.titles <> new_r.gen_p.titles then begin
                  let d_old, d_new = list_remove_same old_r.gen_p.titles new_r.gen_p.titles in
                  diff_titles_list 0 d_old d_new
		end ;
	        if old_r.gen_p.occupation <> new_r.gen_p.occupation then
                  insert_history_detail "occupation" old_r.gen_p.occupation new_r.gen_p.occupation ;
	        if old_r.gen_p.sex <> new_r.gen_p.sex then
                  insert_history_detail "sex" (string_of_sex old_r.gen_p.sex) (string_of_sex new_r.gen_p.sex) ;
(* v7
	        if old_r.gen_p.pevents <> new_r.gen_p.pevents then begin
                  let d_old, d_new = list_remove_same old_r.gen_p.pevents new_r.gen_p.pevents in
                  diff_events 0 "" diff_pevent del_pevent add_pevent d_old d_new
                end ;
*)
	        if old_r.gen_p.notes <> new_r.gen_p.notes then begin
(* on verra plus tard...
                  let d_old, d_new = list_remove_same (split_notes old_r.gen_p.notes) (split_notes new_r.gen_p.notes) in
                  diff_string_list "notes" d_old d_new
*)
                  insert_history_detail "notes" old_r.gen_p.notes new_r.gen_p.notes ;
                end ;
	        if old_r.gen_p.psources <> new_r.gen_p.psources then
                  insert_history_detail "psources" old_r.gen_p.psources new_r.gen_p.psources ;
		let old_isDead = string_of_isDead old_r.gen_p.death in
		let new_isDead = string_of_isDead new_r.gen_p.death in
		if old_isDead <> new_isDead then
                  insert_history_detail "isDead" old_isDead new_isDead ;
		let old_death_reason = string_of_death_reason old_r.gen_p.death in
		let new_death_reason = string_of_death_reason new_r.gen_p.death in
		if old_death_reason <> new_death_reason then
                  insert_history_detail "death_reason" old_death_reason new_death_reason ;
                let old_fc = List.map2 (fun f c -> f, c) old_r.gen_f old_r.gen_c in
                let new_fc = List.map2 (fun f c -> f, c) new_r.gen_f new_r.gen_c in
                if old_fc <> new_fc then begin
                  let d_old, d_new = list_remove_same old_fc new_fc in
                  diff_families 0 d_old d_new
                end ;
                loop (old_r :: l)
              end
        in
        loop (load_person_history dir)
    ) (Sys.readdir dir)
  in
  loop (fname ^ ".gwb/history_d") ;
  close_out oc_h ;
  close_out oc_hd

(* main *)

let dir_out = ref ""

let fname = ref ""

let current = ref true

let history = ref true

let errmsg = "usage: " ^ Sys.argv.(0) ^ " [options] <output_dir> <database>"

let speclist = [
 ("-nolock", Arg.Set Lock.no_lock_flag, ": do not lock data base");
 ("-noCurrent", Arg.Clear current, ": do not export current data");
 ("-noHistory", Arg.Clear history, ": do not export history data")
]

let anonfun s =
  if !dir_out = "" then dir_out := s
  else if !fname = "" then fname := s
  else raise (Arg.Bad "Cannot treat several data bases")

let main () =
  Argl.parse speclist anonfun errmsg;
  if !fname = "" then begin
    Printf.eprintf "Missing file name\n";
    Printf.eprintf "Use option -help for usage\n";
    flush stderr;
    exit 2
  end
  else
    let base = open_base !fname in
    if !current then begin
      let () = load_strings_array base in
      let () = load_ascends_array base in
      let () = load_couples_array base in
      let () = load_descends_array base in
      gw_to_mysql base !dir_out !fname
    end ;
    if !history then begin gw_history_to_mysql !dir_out !fname end

let _ = Printexc.catch main ()