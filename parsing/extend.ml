(***********************************************************************)
(*  v      *   The Coq Proof Assistant  /  The Coq Development Team    *)
(* <O___,, *        INRIA-Rocquencourt  &  LRI-CNRS-Orsay              *)
(*   \VV/  *************************************************************)
(*    //   *      This file is distributed under the terms of the      *)
(*         *       GNU Lesser General Public License Version 2.1       *)
(***********************************************************************)


(*i $Id$ i*)

open Util
open Pp
open Gramext
open Names
open Ast
open Ppextend
open Topconstr
open Genarg

type entry_type = argument_type
type constr_entry_type =
  | ETIdent | ETReference
  | ETConstr of (int * parenRelation) * int option
  | ETPattern
  | ETOther of string * string

type nonterm_prod =
  | ProdList0 of nonterm_prod
  | ProdList1 of nonterm_prod
  | ProdOpt of nonterm_prod
  | ProdPrimitive of constr_entry_type

type prod_item =
  | Term of Token.pattern
  | NonTerm of nonterm_prod * (Names.identifier * constr_entry_type) option

type grammar_rule = {
  gr_name : string; 
  gr_production : prod_item list; 
  gr_action : aconstr }

type grammar_entry = { 
  ge_name : string;
  gl_assoc : Gramext.g_assoc option;
  gl_rules : grammar_rule list }

type grammar_command = { 
  gc_univ : string; 
  gc_entries : grammar_entry list }

type grammar_associativity = Gramext.g_assoc option

(**********************************************************************)
(* Globalisation and type-checking of Grammar actions *)

type entry_context = (identifier * constr_entry_type) list

let ast_to_rawconstr = ref (fun _ _ -> AVar (id_of_string "Z"))
let set_ast_to_rawconstr f = ast_to_rawconstr := f

let act_of_ast env = function
  | SimpleAction (loc,ConstrNode a) -> !ast_to_rawconstr env a
  | SimpleAction (loc,CasesPatternNode a) -> 
      failwith "TODO:act_of_ast: cases_pattern"
  | CaseAction _ -> failwith "case/let not supported"

let to_act_check_vars = act_of_ast

type syntax_modifier =
  | SetItemLevel of string list * int
  | SetLevel of int
  | SetAssoc of Gramext.g_assoc
  | SetEntryType of string * constr_entry_type
  | SetOnlyParsing

type nonterm =
  | NtShort of string
  | NtQual of string * string
type grammar_production =
  | VTerm of string
  | VNonTerm of loc * nonterm * Names.identifier option
type raw_grammar_rule = string * grammar_production list * grammar_action
type raw_grammar_entry = string * grammar_associativity * raw_grammar_rule list

let subst_grammar_rule subst gr =
  { gr with gr_action = subst_aconstr subst gr.gr_action }

let subst_grammar_entry subst ge =
  { ge with gl_rules = List.map (subst_grammar_rule subst) ge.gl_rules }

let subst_grammar_command subst gc =
  { gc with gc_entries = List.map (subst_grammar_entry subst) gc.gc_entries }


(*s Terminal symbols interpretation *)

let is_ident_not_keyword s =
  match s.[0] with
    | 'a'..'z' | 'A'..'Z' | '_' -> not (Lexer.is_keyword s)
    | _ -> false

let is_number s =
  match s.[0] with
    | '0'..'9' -> true
    | _ -> false

let strip s =
  let len =
    let rec loop i len =
      if i = String.length s then len
      else if s.[i] == ' ' then loop (i + 1) len
      else loop (i + 1) (len + 1)
    in
    loop 0 0
  in
  if len == String.length s then s
  else
    let s' = String.create len in
    let rec loop i i' =
      if i == String.length s then s'
      else if s.[i] == ' ' then loop (i + 1) i'
      else begin s'.[i'] <- s.[i]; loop (i + 1) (i' + 1) end
    in
    loop 0 0

let terminal s =
  let s = strip s in
  if s = "" then failwith "empty token";
  if is_ident_not_keyword s then ("IDENT", s)
  else if is_number s then ("INT", s)
  else ("", s)

(*s Non-terminal symbols interpretation *)

(* For compatibility *)
let warn nt nt' =
  warning ("'"^nt^"' grammar entry is obsolete; use name '"^nt'^"' instead");
  nt'

let rename_command nt =
  if String.length nt >= 7 & String.sub nt 0 7 = "command"
  then warn nt ("constr"^(String.sub nt 7 (String.length nt - 7)))
  else if nt = "lcommand" then warn nt "lconstr"
  else if nt = "lassoc_command4" then warn nt "lassoc_constr4"
  else nt

(* This translates constr0, constr1, ... level into camlp4 levels of constr *)

let explicitize_entry univ nt =
  if univ = "prim" & nt = "var" then ETIdent else
  if univ <> "constr" then ETOther (univ,nt) else
  match nt with
  | "constr0" -> ETConstr ((0,E),Some 0)
  | "constr1" -> ETConstr ((1,E),Some 1)
  | "constr2" -> ETConstr ((2,E),Some 2)
  | "constr3" -> ETConstr ((3,E),Some 3)
  | "lassoc_constr4" -> ETConstr ((4,E),Some 4)
  | "constr5" -> ETConstr ((5,E),Some 5)
  | "constr6" -> ETConstr ((6,E),Some 6)
  | "constr7" -> ETConstr ((7,E),Some 7)
  | "constr8" | "constr" -> ETConstr ((8,E),Some 8)
  | "constr9" -> ETConstr ((9,E),Some 9)
  | "constr10" | "lconstr" -> ETConstr ((10,E),Some 10)
  | "pattern" -> ETPattern
  | "ident" -> ETIdent
  | "global" -> ETReference
  | _ -> ETOther (univ,nt)

(* This determines if a reference to constr_n is a reference to the level
   below wrt associativity (to be translated in camlp4 into "constr" without 
   level) or to another level (to be translated into "constr LEVEL n") *)

let clever_explicitize_entry univ name from assoc pos =
  match explicitize_entry univ name, explicitize_entry "" from, pos with
    | ETConstr ((n,_ as s),_),ETConstr ((lev,_),_),Some start
	when n = lev - 1 & assoc <> Some Gramext.LeftA & start
	  or n = lev & assoc = Some Gramext.LeftA & start
	  or n = lev & assoc = Some Gramext.RightA & not start
	  or n = lev - 1 & assoc <> Some Gramext.RightA & not start
	-> ETConstr (s, None)
    | x,_,_ -> x

let qualified_nterm current_univ from ass pos = function
  | NtQual (univ, en) ->
      let univ = rename_command univ in
      clever_explicitize_entry univ (rename_command en) from ass pos
  | NtShort en ->
      clever_explicitize_entry current_univ (rename_command en) from ass pos

let check_entry check_entry_type = function
  | ETOther (u,n) -> check_entry_type (u,n)
  | _ -> ()

let nterm loc (((check_entry_type,univ),lev,ass),pos) nont =
  let typ = qualified_nterm univ lev ass pos nont in
  check_entry check_entry_type typ;
  typ

let prod_item univ env = function
  | VTerm s -> env, Term (terminal s)
  | VNonTerm (loc, nt, Some p) ->
     let typ = nterm loc univ nt in
      ((p, typ) :: env, NonTerm (ProdPrimitive typ, Some (p,typ)))
  | VNonTerm (loc, nt, None) ->
      let typ = nterm loc univ nt in 
      env, NonTerm (ProdPrimitive typ, None)

let rec prod_item_list univ penv pil start =
  match pil with
    | [] -> [], penv
    | pi :: pitl ->
	let pos = if pitl=[] then Some false else start in
	let (env, pic) = prod_item (univ,pos) penv pi in
	let (pictl, act_env) = prod_item_list univ env pitl None in
        (pic :: pictl, act_env)

let gram_rule univ (name,pil,act) =
  let (pilc, act_env) = prod_item_list univ [] pil (Some true) in
  let a = to_act_check_vars act_env act in
  { gr_name = name; gr_production = pilc; gr_action = a }

let gram_entry univ (nt, ass, rl) =
  let name = rename_command nt in
  { ge_name = name;
    gl_assoc = ass;
    gl_rules = List.map (gram_rule (univ,name,ass)) rl }

let interp_grammar_command univ ge entryl =
  let univ = rename_command univ in
  { gc_univ = univ;
    gc_entries = List.map (gram_entry (ge,univ)) entryl }

(* unparsing objects *)

type 'pat unparsing_hunk = 
  | PH of 'pat * string option * parenRelation
  | RO of string
  | UNP_BOX of ppbox * 'pat unparsing_hunk list
  | UNP_BRK of int * int
  | UNP_TBRK of int * int
  | UNP_TAB
  | UNP_FNL
  | UNP_SYMBOLIC of string * string * 'pat unparsing_hunk

let rec subst_hunk subst_pat subst hunk = match hunk with
  | PH (pat,so,pr) ->
      let pat' = subst_pat subst pat in
	if pat'==pat then hunk else
	  PH (pat',so,pr)
  | RO _ -> hunk
  | UNP_BOX (ppbox, hunkl) ->
      let hunkl' = list_smartmap (subst_hunk subst_pat subst) hunkl in
	if hunkl' == hunkl then hunk else
	  UNP_BOX (ppbox, hunkl')
  | UNP_BRK _
  | UNP_TBRK _
  | UNP_TAB
  | UNP_FNL -> hunk
  | UNP_SYMBOLIC (s1, s2, pat) ->
      let pat' = subst_hunk subst_pat subst pat in
	if pat' == pat then hunk else
	  UNP_SYMBOLIC (s1, s2, pat')

(* Checks if the precedence of the parent printer (None means the
   highest precedence), and the child's one, follow the given
   relation. *)

(*
let compare_prec (a1,b1,c1) (a2,b2,c2) =
  match (a1=a2),(b1=b2),(c1=c2) with
    | true,true,true -> 0
    | true,true,false -> c1-c2
    | true,false,_ -> b1-b2
    | false,_,_ -> a1-a2
*)
let compare_prec a1 a2 = a1-a2

let tolerable_prec oparent_prec_reln child_prec =
  match oparent_prec_reln with
    | Some (pprec, L) -> (compare_prec child_prec pprec) < 0
    | Some (pprec, E) -> (compare_prec child_prec pprec) <= 0
    | Some (_, Prec level) -> (compare_prec child_prec level) <= 0
    | _ -> true

type 'pat syntax_entry = {
  syn_id : string;
  syn_prec: precedence;
  syn_astpat : 'pat;
  syn_hunks : 'pat unparsing_hunk list }

let subst_syntax_entry subst_pat subst sentry = 
  let syn_astpat' = subst_pat subst sentry.syn_astpat in
  let syn_hunks' = list_smartmap (subst_hunk subst_pat subst) sentry.syn_hunks 
  in
    if syn_astpat' == sentry.syn_astpat 
      && syn_hunks' == sentry.syn_hunks then sentry 
    else
      { sentry with
	  syn_astpat = syn_astpat' ;
	  syn_hunks = syn_hunks' ;
      }
      
type 'pat syntax_command = { 
  sc_univ : string; 
  sc_entries : 'pat syntax_entry list }

let subst_syntax_command subst_pat subst scomm = 
  let sc_entries' = 
    list_smartmap (subst_syntax_entry subst_pat subst) scomm.sc_entries 
  in
    if sc_entries' == scomm.sc_entries then scomm else
      { scomm with sc_entries = sc_entries' }
      
type syntax_rule = string * Coqast.t * Coqast.t unparsing_hunk list
type raw_syntax_entry = precedence * syntax_rule list

let rec interp_unparsing env = function
  | PH (ast,ext,pr) -> PH (Ast.val_of_ast env ast,ext,pr)
  | UNP_BOX (b,ul) -> UNP_BOX (b,List.map (interp_unparsing env) ul)
  | UNP_BRK _ | RO _ | UNP_TBRK _ | UNP_TAB | UNP_FNL as x -> x
  | UNP_SYMBOLIC (x,y,u) -> UNP_SYMBOLIC (x,y,interp_unparsing env u)

let rule_of_ast univ prec (s,spat,unp) =
  let (astpat,meta_env) = Ast.to_pat [] spat in
  let hunks = List.map (interp_unparsing meta_env) unp in
  { syn_id = s;
    syn_prec = prec;
    syn_astpat = astpat;
    syn_hunks = hunks }

let level_of_ast univ (prec,rl) = List.map (rule_of_ast univ prec) rl

let interp_syntax_entry univ sel =
  { sc_univ = univ;
    sc_entries = List.flatten (List.map (level_of_ast univ) sel)}


