(***********************************************************************)
(*  v      *   The Coq Proof Assistant  /  The Coq Development Team    *)
(* <O___,, *        INRIA-Rocquencourt  &  LRI-CNRS-Orsay              *)
(*   \VV/  *************************************************************)
(*    //   *      This file is distributed under the terms of the      *)
(*         *       GNU Lesser General Public License Version 2.1       *)
(***********************************************************************)

(* $Id$ *)

open Pp
open Util
open Extend
open Pcoq
open Topconstr
open Ast
open Genarg
open Libnames
open Nameops

(* State of the grammar extensions *)

type all_grammar_command =
  | Notation of
      (int * Gramext.g_assoc option * notation * prod_item list *
      int list option)
  | Grammar of grammar_command
  | TacticGrammar of
      (string * (string * grammar_production list) * 
      (Names.dir_path * Tacexpr.raw_tactic_expr))
      list

let subst_all_grammar_command subst = function
  | Notation _ -> anomaly "Notation not in GRAMMAR summary"
  | Grammar gc -> Grammar (subst_grammar_command subst gc)
  | TacticGrammar g -> TacticGrammar g (* TODO ... *)

let (grammar_state : all_grammar_command list ref) = ref []


(**************************************************************************)
(* Interpretation of the right hand side of grammar rules *)

(* When reporting errors, we add the name of the grammar rule that failed *)
let specify_name name e =
  match e with
    | UserError(lab,strm) ->
        UserError(lab, (str"during interpretation of grammar rule " ++
                          str name ++ str"," ++ spc () ++ strm))
    | Anomaly(lab,strm) ->
        Anomaly(lab, (str"during interpretation of grammar rule " ++
                        str name ++ str"," ++ spc () ++ strm))
    | Failure s ->
        Failure("during interpretation of grammar rule "^name^", "^s)
    | e -> e

(* Translation of environments: a production
 *   [ nt1(x1) ... nti(xi) ] -> act(x1..xi)
 * is written (with camlp4 conventions):
 *   (fun vi -> .... (fun v1 -> act(v1 .. vi) )..)
 * where v1..vi are the values generated by non-terminals nt1..nti.
 * Since the actions are executed by substituting an environment,
 * make_act builds the following closure:
 *
 *      ((fun env ->
 *          (fun vi -> 
 *             (fun env -> ...
 *           
 *                  (fun v1 ->
 *                     (fun env -> gram_action .. env act)
 *                     ((x1,v1)::env))
 *                  ...)
 *             ((xi,vi)::env)))
 *         [])
 *)

open Names

type 'a action_env = (identifier * 'a) list

let make_act (f : loc -> constr_expr action_env -> constr_expr) pil =
  let rec make (env : constr_expr action_env) = function
    | [] ->
	Gramext.action (fun loc -> f loc env)
    | None :: tl -> (* parse a non-binding item *)
        Gramext.action (fun _ -> make env tl)
    | Some (p, (ETConstr _| ETOther _)) :: tl -> (* constr non-terminal *)
        Gramext.action (fun (v:constr_expr) -> make ((p,v) :: env) tl)
    | Some (p, ETReference) :: tl -> (* non-terminal *)
        Gramext.action (fun (v:reference) -> make ((p,CRef v) :: env) tl)
    | Some (p, ETIdent) :: tl -> (* non-terminal *)
        Gramext.action (fun (v:identifier) ->
	  make ((p,CRef (Ident (dummy_loc,v))) :: env) tl)
    | Some (p, ETBigint) :: tl -> (* non-terminal *)
        Gramext.action (fun (v:Bignat.bigint) ->
	  make ((p,CNumeral (dummy_loc,v)) :: env) tl)
    | Some (p, ETPattern) :: tl -> 
	failwith "Unexpected entry of type cases pattern" in
  make [] (List.rev pil)

let make_act_in_cases_pattern (* For Notations *)
  (f : loc -> cases_pattern_expr action_env -> cases_pattern_expr) pil =
  let rec make (env : cases_pattern_expr action_env) = function
    | [] ->
	Gramext.action (fun loc -> f loc env)
    | None :: tl -> (* parse a non-binding item *)
        Gramext.action (fun _ -> make env tl)
    | Some (p, ETConstr _) :: tl -> (* pattern non-terminal *)
        Gramext.action (fun (v:cases_pattern_expr) -> make ((p,v) :: env) tl)
    | Some (p, ETReference) :: tl -> (* non-terminal *)
        Gramext.action (fun (v:reference) ->
	  make ((p,CPatAtom (dummy_loc,Some v)) :: env) tl)
    | Some (p, ETIdent) :: tl -> (* non-terminal *)
        Gramext.action (fun (v:identifier) ->
	  make ((p,CPatAtom (dummy_loc,Some (Ident (dummy_loc,v)))) :: env) tl)
    | Some (p, ETBigint) :: tl -> (* non-terminal *)
        Gramext.action (fun (v:Bignat.bigint) ->
	  make ((p,CPatNumeral (dummy_loc,v)) :: env) tl)
    | Some (p, (ETPattern | ETOther _)) :: tl -> 
	failwith "Unexpected entry of type cases pattern or other" in
  make [] (List.rev pil)

let make_cases_pattern_act (* For Grammar *)
  (f : loc -> cases_pattern_expr action_env -> cases_pattern_expr) pil =
  let rec make (env : cases_pattern_expr action_env) = function
    | [] ->
	Gramext.action (fun loc -> f loc env)
    | None :: tl -> (* parse a non-binding item *)
        Gramext.action (fun _ -> make env tl)
    | Some (p, ETPattern) :: tl -> (* non-terminal *)
        Gramext.action (fun v -> make ((p,v) :: env) tl)
    | Some (p, ETReference) :: tl -> (* non-terminal *)
	Gramext.action (fun v -> make ((p,CPatAtom(dummy_loc,Some v)) :: env)
	  tl)
    | Some (p, ETBigint) :: tl -> (* non-terminal *)
	Gramext.action (fun v -> make ((p,CPatNumeral(dummy_loc,v)) :: env) tl)
    | Some (p, (ETIdent | ETConstr _ | ETOther _)) :: tl ->
	error "ident and constr entry not admitted in patterns cases syntax extensions" in
  make [] (List.rev pil)

(* Grammar extension command. Rules are assumed correct.
 * Type-checking of grammar rules is done during the translation of
 * ast to the type grammar_command.  We only check that the existing
 * entries have the type assumed in the grammar command (these types
 * annotations are added when type-checking the command, function
 * Extend.of_ast) *)

let rec build_prod_item univ assoc fromlevel pat = function
  | ProdList0 s -> Gramext.Slist0 (build_prod_item univ assoc fromlevel pat s)
  | ProdList1 s -> Gramext.Slist1 (build_prod_item univ assoc fromlevel pat s)
  | ProdOpt s   -> Gramext.Sopt   (build_prod_item univ assoc fromlevel pat s)
  | ProdPrimitive typ -> symbol_of_production assoc fromlevel pat typ

let symbol_of_prod_item univ assoc from forpat = function
  | Term tok -> (Gramext.Stoken tok, None)
  | NonTerm (nt, ovar) ->
      let eobj = build_prod_item univ assoc from forpat nt in
      (eobj, ovar)

let coerce_to_id = function
  | CRef (Ident (_,id)) -> id 
  | c ->
      user_err_loc (constr_loc c, "subst_rawconstr",
        str"This expression should be a simple identifier")

let coerce_to_ref = function
  | CRef r -> r
  | c ->
      user_err_loc (constr_loc c, "subst_rawconstr",
        str"This expression should be a simple reference")

let subst_ref loc subst id =
  try coerce_to_ref (List.assoc id subst) with Not_found -> Ident (loc,id)

let subst_pat_id loc subst id =
  try List.assoc id subst
  with Not_found -> CPatAtom (loc,Some (Ident (loc,id)))

let subst_id subst id =
  try coerce_to_id (List.assoc id subst) with Not_found -> id

(*
let subst_cases_pattern_expr a loc subs =
  let rec subst = function
  | CPatAlias (_,p,x) -> CPatAlias (loc,subst p,x)
    (* No subst in compound pattern ? *)
  | CPatCstr (_,ref,pl) -> CPatCstr (loc,ref,List.map subst pl)
  | CPatAtom (_,Some (Ident (_,id))) -> subst_pat_id loc subs id
  | CPatAtom (_,x) -> CPatAtom (loc,x)
  | CPatNotation (_,ntn,l) -> CPatNotation 
  | CPatNumeral (_,n) -> CPatNumeral (loc,n)
  | CPatDelimiters (_,key,p) -> CPatDelimiters (loc,key,subst p)
  in subst a
*)

let subst_constr_expr a loc subs =
  let rec subst = function
  | CRef (Ident (_,id)) ->
      (try List.assoc id subs with Not_found -> CRef (Ident (loc,id)))
  (* Temporary: no robust treatment of substituted binders *)
  | CLambdaN (_,[],c) -> subst c
  | CLambdaN (_,([],t)::bl,c) -> subst (CLambdaN (loc,bl,c))
  | CLambdaN (_,((_,na)::bl,t)::bll,c) -> 
      let na = name_app (subst_id subs) na in
      CLambdaN (loc,[[loc,na],subst t], subst (CLambdaN (loc,(bl,t)::bll,c)))
  | CProdN (_,[],c) -> subst c
  | CProdN (_,([],t)::bl,c) -> subst (CProdN (loc,bl,c))
  | CProdN (_,((_,na)::bl,t)::bll,c) -> 
      let na = name_app (subst_id subs) na in
      CProdN (loc,[[loc,na],subst t], subst (CProdN (loc,(bl,t)::bll,c)))
  | CLetIn (_,(_,na),b,c) ->
      let na = name_app (subst_id subs) na in
      CLetIn (loc,(loc,na),subst b,subst c)
  | CArrow (_,a,b) -> CArrow (loc,subst a,subst b)
  | CAppExpl (_,(p,Ident (_,id)),l) ->
      CAppExpl (loc,(p,subst_ref loc subs id),List.map subst l) 
  | CAppExpl (_,r,l) -> CAppExpl (loc,r,List.map subst l) 
  | CApp (_,(p,a),l) ->
      CApp (loc,(p,subst a),List.map (fun (a,i) -> (subst a,i)) l)
  | CCast (_,a,b) -> CCast (loc,subst a,subst b)
  | CNotation (_,n,l) -> CNotation (loc,n,List.map subst l)
  | CDelimiters (_,s,a) -> CDelimiters (loc,s,subst a)
  | CHole _ | CEvar _ | CPatVar _ | CSort _ 
  | CNumeral _ | CDynamic _ | CRef _ as x -> x
  | CCases (_,(po,rtntypo),a,bl) ->
      (* TODO: apply g on the binding variables in pat... *)
      let bl = List.map (fun (_,pat,rhs) -> (loc,pat,subst rhs)) bl in
      CCases (loc,(option_app subst po,option_app subst rtntypo),
        List.map (fun (tm,x) -> subst tm,x) a,bl)
  | COrderedCase (_,s,po,a,bl) ->
      COrderedCase (loc,s,option_app subst po,subst a,List.map subst bl)
  | CLetTuple (_,nal,(na,po),a,b) ->
      let na = option_app (name_app (subst_id subs)) na in
      let nal = List.map (name_app (subst_id subs)) nal in
      CLetTuple (loc,nal,(na,option_app subst po),subst a,subst b)
  | CIf (_,c,(na,po),b1,b2) ->
      let na = option_app (name_app (subst_id subs)) na in
      CIf (loc,subst c,(na,option_app subst po),subst b1,subst b2)
  | CFix (_,id,dl) ->
      CFix (loc,id,List.map (fun (id,n,on, t,d) -> (id,n, on,subst t,subst d)) dl)
  | CCoFix (_,id,dl) ->
      CCoFix (loc,id,List.map (fun (id,t,d) -> (id,subst t,subst d)) dl)
  in subst a

let make_rule univ assoc etyp rule =
  let pil = List.map (symbol_of_prod_item univ assoc etyp false) rule.gr_production in
  let (symbs,ntl) = List.split pil in
  let act = match etyp with
    | ETPattern ->
        (* Ugly *)
        let f loc env = match rule.gr_action, env with
          | CRef (Ident(_,p)), [p',a] when p=p' -> a
          | CDelimiters (_,s,CRef (Ident(_,p))), [p',a] when p=p' ->
	      CPatDelimiters (loc,s,a)
          | _ -> error "Unable to handle this grammar extension of pattern" in
	make_cases_pattern_act f ntl
    | ETIdent | ETBigint | ETReference -> error "Cannot extend"
    | ETConstr _ | ETOther _ -> 
	make_act (subst_constr_expr rule.gr_action) ntl in
  (symbs, act)

(* Rules of a level are entered in reverse order, so that the first rules
   are applied before the last ones *)
let extend_entry univ (te, etyp, pos, name, ass, p4ass, rls) =
  let rules = List.rev (List.map (make_rule univ ass etyp) rls) in
  grammar_extend te pos [(name, p4ass, rules)]

(* Defines new entries. If the entry already exists, check its type *)
let define_entry univ {ge_name=typ; gl_assoc=ass; gl_rules=rls} =
  let e,lev,keepassoc = get_constr_entry false typ in
  let pos,p4ass,name = find_position false keepassoc ass lev in
  (e,typ,pos,name,ass,p4ass,rls)

(* Add a bunch of grammar rules. Does not check if it is well formed *)
let extend_grammar_rules gram =
  let univ = get_univ gram.gc_univ in
  let tl = List.map (define_entry univ) gram.gc_entries in
  List.iter (extend_entry univ) tl

(* Add a grammar rules for tactics *)
type grammar_tactic_production =
  | TacTerm of string
  | TacNonTerm of loc * (Gram.te Gramext.g_symbol * argument_type) * string option

let make_prod_item = function
  | TacTerm s -> (Gramext.Stoken (Extend.terminal s), None)
  | TacNonTerm (_,(nont,t), po) ->
      (nont, option_app (fun p -> (p,t)) po)

let make_gen_act f pil =
  let rec make env = function
    | [] -> 
	Gramext.action (fun loc -> f loc env)
    | None :: tl -> (* parse a non-binding item *)
        Gramext.action (fun _ -> make env tl)
    | Some (p, t) :: tl -> (* non-terminal *)
        Gramext.action (fun v -> make ((p,in_generic t v) :: env) tl) in
  make [] (List.rev pil)

let extend_constr entry (n,assoc,pos,p4assoc,name) make_act (forpat,pt) =
  let univ = get_univ "constr" in
  let pil = List.map (symbol_of_prod_item univ assoc n forpat) pt in
  let (symbs,ntl) = List.split pil in
  let act = make_act ntl in
  grammar_extend entry pos [(name, p4assoc, [symbs, act])]

let extend_constr_notation (n,assoc,ntn,rule,permut) =
  let mkact =
    match permut with
        None -> (fun loc env -> CNotation (loc,ntn,List.map snd env))
      | Some p -> (fun loc env ->
          CNotation (loc,ntn,List.map (fun i -> snd (List.nth env i)) p)) in
  let (e,level,keepassoc) = get_constr_entry false (ETConstr (n,())) in
  let pos,p4assoc,name = find_position false keepassoc assoc level in
  extend_constr e (ETConstr(n,()),assoc,pos,p4assoc,name)
    (make_act mkact) (false,rule);
  if not !Options.v7 then
  let mkact loc env = CPatNotation (loc,ntn,List.map snd env) in
  let (e,level,keepassoc) = get_constr_entry true (ETConstr (n,())) in
  let pos,p4assoc,name = find_position true keepassoc assoc level in
  extend_constr e (ETConstr (n,()),assoc,pos,p4assoc,name)
    (make_act_in_cases_pattern mkact) (true,rule)
    
(* These grammars are not a removable *)
let make_rule univ f g (s,pt) =
  let hd = Gramext.Stoken ("IDENT", s) in
  let pil = (hd,None) :: List.map g pt in
  let (symbs,ntl) = List.split pil in
  let act = make_gen_act f ntl in
  (symbs, act)

let tac_exts = ref []
let get_extend_tactic_grammars () = !tac_exts

let extend_tactic_grammar s gl =
  tac_exts := (s,gl) :: !tac_exts;
  let univ = get_univ "tactic" in
  let make_act loc l = Tacexpr.TacExtend (loc,s,List.map snd l) in
  let rules = List.map (make_rule univ make_act make_prod_item) gl in
  Gram.extend Tactic.simple_tactic None [(None, None, List.rev rules)]

let vernac_exts = ref []
let get_extend_vernac_grammars () = !vernac_exts

let extend_vernac_command_grammar s gl =
  vernac_exts := (s,gl) :: !vernac_exts;
  let univ = get_univ "vernac" in
  let make_act loc l = Vernacexpr.VernacExtend (s,List.map snd l) in
  let rules = List.map (make_rule univ make_act make_prod_item) gl in
  Gram.extend Vernac_.command None [(None, None, List.rev rules)]

let rec interp_entry_name u s =
  let l = String.length s in
  if l > 8 & String.sub s 0 3 = "ne_" & String.sub s (l-5) 5 = "_list" then
    let t, g = interp_entry_name u (String.sub s 3 (l-8)) in
    List1ArgType t, Gramext.Slist1 g
  else if l > 5 & String.sub s (l-5) 5 = "_list" then
    let t, g = interp_entry_name u (String.sub s 0 (l-5)) in
    List0ArgType t, Gramext.Slist0 g
  else if l > 4 & String.sub s (l-4) 4 = "_opt" then
    let t, g = interp_entry_name u (String.sub s 0 (l-4)) in
    OptArgType t, Gramext.Sopt g
  else
    let e = 
    if !Options.v7 then get_entry (get_univ u) s
    else
      (* Qualified entries are no longer in use *)
      try get_entry (get_univ "tactic") s
      with _ -> 
      try get_entry (get_univ "prim") s
      with _ ->
      try get_entry (get_univ "constr") s
      with _ -> error ("Unknown entry "^s)
    in
    let o = object_of_typed_entry e in
    let t = type_of_typed_entry e in
    t,Gramext.Snterm (Pcoq.Gram.Entry.obj o)

let qualified_nterm current_univ = function
  | NtQual (univ, en) -> if !Options.v7 then (univ, en) else assert false
  | NtShort en -> (current_univ, en)

let make_vprod_item univ = function
  | VTerm s -> (Gramext.Stoken (Extend.terminal s), None)
  | VNonTerm (loc, nt, po) ->
      let (u,nt) = qualified_nterm univ nt in
      let (etyp, e) = interp_entry_name u nt in
      e, option_app (fun p -> (p,etyp)) po

let add_tactic_entries gl =
  let univ = get_univ "tactic" in
  let make_act s tac loc l = Tacexpr.TacAlias (loc,s,l,tac) in
  let f (s,l,tac) =
    make_rule univ (make_act s tac) (make_vprod_item "tactic") l in
  let rules = List.map f gl in
  let _ = find_position true true None None (* to synchronise with remove *) in
  grammar_extend Tactic.simple_tactic None [(None, None, List.rev rules)]

let extend_grammar gram =
  (match gram with
  | Notation a -> extend_constr_notation a
  | Grammar g -> extend_grammar_rules g
  | TacticGrammar l -> add_tactic_entries l);
  grammar_state := gram :: !grammar_state

let reset_extend_grammars_v8 () =
  let te = List.rev !tac_exts in
  let tv = List.rev !vernac_exts in
  tac_exts := [];
  vernac_exts := [];
  List.iter (fun (s,gl) -> extend_tactic_grammar s gl) te;
  List.iter (fun (s,gl) -> extend_vernac_command_grammar s gl) tv


(* Summary functions: the state of the lexer is included in that of the parser.
   Because the grammar affects the set of keywords when adding or removing
   grammar rules. *)
type frozen_t = all_grammar_command list * Lexer.frozen_t

let freeze () = (!grammar_state, Lexer.freeze ())

(* We compare the current state of the grammar and the state to unfreeze, 
   by computing the longest common suffixes *)
let factorize_grams l1 l2 =
  if l1 == l2 then ([], [], l1) else list_share_tails l1 l2

let number_of_entries gcl =
  List.fold_left
    (fun n -> function
      | Notation _ -> 
          if !Options.v7 then n + 1
	  else n + 2 (* 1 for operconstr, 1 for pattern *)
      | Grammar gc ->
          n + (List.length gc.gc_entries)
      | TacticGrammar _ -> n + 1)
    0 gcl

let unfreeze (grams, lex) =
  let (undo, redo, common) = factorize_grams !grammar_state grams in
  let n = number_of_entries undo in
  remove_grammars n;
  remove_levels n;
  grammar_state := common;
  Lexer.unfreeze lex;
  List.iter extend_grammar (List.rev redo)
 
let init_grammar () =
  remove_grammars (number_of_entries !grammar_state);
  grammar_state := []

let init () =
  init_grammar ()

open Summary

let _ = 
  declare_summary "GRAMMAR_LEXER"
    { freeze_function = freeze;
      unfreeze_function = unfreeze;
      init_function = init;
      survive_module = false;
      survive_section = false }
