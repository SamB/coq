(************************************************************************)
(*  v      *   The Coq Proof Assistant  /  The Coq Development Team     *)
(* <O___,, * CNRS-Ecole Polytechnique-INRIA Futurs-Universite Paris Sud *)
(*   \VV/  **************************************************************)
(*    //   *      This file is distributed under the terms of the       *)
(*         *       GNU Lesser General Public License Version 2.1        *)
(************************************************************************)

(*i $Id$ i*)

{

open Filename
open Lexing 
open Printf

open Cdglobals

type loc = int

type entry_type = 
  | Library
  | Module
  | Definition
  | Inductive
  | Constructor
  | Lemma
  | Variable
  | Axiom
  | TacticDefinition

type index_entry = 
  | Def of string * entry_type
  | Ref of coq_module * string
  | Mod of coq_module * string

let table = Hashtbl.create 97

let current_module = ref ""

let add_def loc ty id = Hashtbl.add table (!current_module, loc) (Def (id, ty))

let add_ref m loc m' id = Hashtbl.add table (m, loc) (Ref (m', id))

let add_mod m loc m' id = Hashtbl.add table (m, loc) (Mod (m', id))

let find m l = Hashtbl.find table (m, l)

let current_type = ref Library

(* Coq modules *)

let split_sp s = 
  try
    let i = String.rindex s '.' in
    String.sub s 0 i, String.sub s (i + 1) (String.length s - i - 1)
  with Not_found -> 
    "", s

let modules = Hashtbl.create 97
let local_modules = Hashtbl.create 97

let add_module m =
  let _,id = split_sp m in
  Hashtbl.add modules id m;
  Hashtbl.add local_modules m ()

type module_kind = Local | Coqlib | Unknown

let coq_module m =
  String.length m >= 4 && String.sub m 0 4 = "Coq."

let find_module m =
  if Hashtbl.mem local_modules m then 
    Local
  else if coq_module m then
    Coqlib
  else
    Unknown

let ref_module loc s =
  try
    let n = String.length s in
    let i = String.rindex s ' ' in 
    let id = String.sub s (i+1) (n-i-1) in
    add_mod !current_module (loc+i+1) (Hashtbl.find modules id) id
  with Not_found -> 
    ()

(* Building indexes *)

type 'a index = { 
  idx_name : string;
  idx_entries : (char * (string * 'a) list) list;
  idx_size : int }
		  
let map f i = 
  { i with idx_entries = 
      List.map 
	(fun (c,l) -> (c, List.map (fun (s,x) -> (s,f s x)) l)) 
	i.idx_entries }

let compare_entries (s1,_) (s2,_) = Alpha.compare_string s1 s2

let sort_entries el =
  let t = Hashtbl.create 97 in
  List.iter 
    (fun c -> Hashtbl.add t c [])
    ['A'; 'B'; 'C'; 'D'; 'E'; 'F'; 'G'; 'H'; 'I'; 'J'; 'K'; 'L'; 'M'; 'N'; 
     'O'; 'P'; 'Q'; 'R'; 'S'; 'T'; 'U'; 'V'; 'W'; 'X'; 'Y'; 'Z'; '_'];  
  List.iter 
    (fun ((s,_) as e) -> 
       let c = Alpha.norm_char s.[0] in 
       let l = try Hashtbl.find t c with Not_found -> [] in
       Hashtbl.replace t c (e :: l)) 
    el;
  let res = ref [] in
  Hashtbl.iter 
    (fun c l -> res := (c, List.sort compare_entries l) :: !res) t;
  List.sort (fun (c1,_) (c2,_) -> Alpha.compare_char c1 c2) !res
    
let index_size = List.fold_left (fun s (_,l) -> s + List.length l) 0

let hashtbl_elements h = Hashtbl.fold (fun x y l -> (x,y)::l) h []

let type_name = function
  | Library -> "library"
  | Module -> "module"
  | Definition -> "definition"
  | Inductive -> "inductive"
  | Constructor -> "constructor"
  | Lemma -> "lemma"
  | Variable -> "variable"
  | Axiom -> "axiom"
  | TacticDefinition -> "tactic"

let all_entries () =
  let gl = ref [] in
  let add_g s m t = gl := (s,(m,t)) :: !gl in
  let bt = Hashtbl.create 11 in
  let add_bt t s m =
    let l = try Hashtbl.find bt t with Not_found -> [] in
    Hashtbl.replace bt t ((s,m) :: l)
  in
  let classify (m,_) e = match e with 
    | Def (s,t) -> add_g s m t; add_bt t s m
    | Ref _ | Mod _ -> ()
  in
  Hashtbl.iter classify table;
  Hashtbl.iter (fun id m -> add_g id m Library; add_bt Library id m) modules;
  { idx_name = "global"; 
    idx_entries = sort_entries !gl; 
    idx_size = List.length !gl },
  Hashtbl.fold (fun t e l -> (t, { idx_name = type_name t; 
				   idx_entries = sort_entries e; 
				   idx_size = List.length e }) :: l) bt []

}

(*s Shortcuts for regular expressions. *)

let space = 
  [' ' '\010' '\013' '\009' '\012']
let firstchar = 
  ['$' 'A'-'Z' 'a'-'z' '_' '\192'-'\214' '\216'-'\246' '\248'-'\255']
let identchar = 
  ['$' 'A'-'Z' 'a'-'z' '_' '\192'-'\214' '\216'-'\246' '\248'-'\255' 
   '\'' '0'-'9']
let ident = 
  firstchar identchar*

let begin_hide = "(*" space* "begin" space+ "hide" space* "*)"
let end_hide = "(*" space* "end" space+ "hide" space* "*)"

(*s Indexing entry point. *)

rule traverse = parse
  | "Definition" space
      { current_type := Definition; index_ident lexbuf; traverse lexbuf }
  | "Tactic" space+ "Definition" space
      { current_type := TacticDefinition; index_ident lexbuf; traverse lexbuf }
  | ("Axiom" | "Parameter") space 
      { current_type := Axiom; index_ident lexbuf; traverse lexbuf }
  | "Fixpoint" space
      { current_type := Definition; index_ident lexbuf; fixpoint lexbuf;
	traverse lexbuf }
  | ("Lemma" | "Theorem") space
      { current_type := Lemma; index_ident lexbuf; traverse lexbuf }
  | "Inductive" space
      { current_type := Inductive; 
	index_ident lexbuf; inductive lexbuf; traverse lexbuf }
  | "Record" space
      { current_type := Inductive; index_ident lexbuf; traverse lexbuf }
  | "Module" (space+ "Type")? space
      { current_type := Module; index_ident lexbuf; traverse lexbuf }
(*i***
  | "Variable" 's'? space
      { current_type := Variable; index_idents lexbuf; traverse lexbuf }
***i*)
  | "Require" (space+ ("Export"|"Import"))? space+ ident
      { ref_module (lexeme_start lexbuf) (lexeme lexbuf); traverse lexbuf }
  | begin_hide 
      { skip_hide lexbuf; traverse lexbuf }
  | "(*" 
      { comment lexbuf; traverse lexbuf }
  | '"'
      { string lexbuf; traverse lexbuf }
  | eof          
      { () }
  | _            
      { traverse lexbuf }

(*s Index one identifier. *)

and index_ident = parse
  | space+ 
      { index_ident lexbuf }
  | ident  
      { add_def (lexeme_start lexbuf) !current_type (lexeme lexbuf) }
  | eof    
      { () }
  | _      
      { () }

(*s Index identifiers separated by blanks and/or commas. *)

and index_idents = parse
  | space+ | ','
      { index_idents lexbuf }
  | ident  
      { add_def (lexeme_start lexbuf) !current_type (lexeme lexbuf);
	index_idents lexbuf }
  | eof    
      { () }
  | _
      { skip_until_point lexbuf }

(*s Index identifiers in an inductive definition (types and constructors). *)

and inductive = parse
  | '|' | ":=" space* '|'? 
      { current_type := Constructor; index_ident lexbuf; inductive lexbuf }
  | "with" space
      { current_type := Inductive; index_ident lexbuf; inductive lexbuf }
  | '.'    
      { () }
  | eof    
      { () }
  | _      
      { inductive lexbuf }

(*s Index identifiers in a Fixpoint declaration. *)

and fixpoint = parse
  | "with" space
      { index_ident lexbuf; fixpoint lexbuf }
  | '.' 
      { () }
  | eof    
      { () }
  | _      
      { fixpoint lexbuf }

(*s Skip a possibly nested comment. *)

and comment = parse
  | "*)" { () }
  | "(*" { comment lexbuf; comment lexbuf }
  | '"'  { string lexbuf; comment lexbuf }
  | eof  { eprintf " *** Unterminated comment while indexing" }
  | _    { comment lexbuf }

(*s Skip a constant string. *)

and string = parse
  | '"'  { () }
  | eof  { eprintf " *** Unterminated string while indexing" }
  | _    { string lexbuf }

(*s Skip everything until the next dot. *)

and skip_until_point = parse
  | '.'  { () }
  | eof  { () }
  | _    { skip_until_point lexbuf }

(*s Skip everything until [(* end hide *)] *)

and skip_hide = parse
  | eof | end_hide { () }
  | _ { skip_hide lexbuf }

{
  
  let read_glob f = 
    let c = open_in f in
    let cur_mod = ref "" in
    try
      while true do
	let s = input_line c in
	let n = String.length s in
	if n > 0 then begin
	  match s.[0] with
	    | 'F' -> 
		cur_mod := String.sub s 1 (n - 1)
	    | 'R' ->
		(try
		   let i = String.index s ' ' in
		   let loc = int_of_string (String.sub s 1 (i - 1)) in
		   let sp = String.sub s (i + 1) (n - i - 1) in
		   let m',id = split_sp sp in
		   add_ref !cur_mod loc m' id
		 with Not_found -> 
		   ())
	    | _ -> ()
	end
      done
    with End_of_file -> 
      close_in c

  let scan_file f m = 
    current_module := m;
    let c = open_in f in
    let lb = from_channel c in
    traverse lb;
    close_in c
}
