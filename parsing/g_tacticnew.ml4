(***********************************************************************)
(*  v      *   The Coq Proof Assistant  /  The Coq Development Team    *)
(* <O___,, *        INRIA-Rocquencourt  &  LRI-CNRS-Orsay              *)
(*   \VV/  *************************************************************)
(*    //   *      This file is distributed under the terms of the      *)
(*         *       GNU Lesser General Public License Version 2.1       *)
(***********************************************************************)

(* $Id$ *)

open Pp
open Ast
open Pcoq
open Util
open Tacexpr
open Rawterm
open Genarg

let tactic_kw =
  [ "->"; "<-" ]
let _ = List.iter (fun s -> Lexer.add_token("",s)) tactic_kw

(* Hack to parse "with n := c ..." as a binder without conflicts with the *)
(* admissible notation "with c1 c2..." *)
let test_lparcoloneq2 =
  Gram.Entry.of_parser "test_lparcoloneq2"
    (fun strm ->
      match Stream.npeek 1 strm with
        | [("", "(")] ->
            begin match Stream.npeek 3 strm with
              | [_; _; ("", ":=")] -> ()
              | _ -> raise Stream.Failure
            end
        | _ -> raise Stream.Failure)

(* open grammar entries, possibly in quotified form *)
ifdef Quotify then open Qast

open Constr
open Prim
open Tactic

(* Functions overloaded by quotifier *)

let induction_arg_of_constr c =
  try ElimOnIdent (Topconstr.constr_loc c,coerce_to_id c) with _ -> ElimOnConstr c

let local_compute = [FBeta;FIota;FDeltaBut [];FZeta]

let error_oldelim _ = error "OldElim no longer supported"

ifdef Quotify then
  let induction_arg_of_constr = function
  | Qast.Node ("Nvar", [_;id]) -> Qast.Node ("ElimOnIdent", [id])
  | c -> Qast.Node ("ElimOnConstr", [c])

ifdef Quotify then
let make_red_flag s = Qast.Apply ("make_red_flag", [s])

ifdef Quotify then
let local_compute = 
  Qast.List [
    Qast.Node ("FBeta", []);
    Qast.Node ("FDeltaBut", [Qast.List []]);
    Qast.Node ("FIota", []);
    Qast.Node ("FZeta", [])]

ifdef Quotify then open Q

let join_to_constr loc c2 = (fst loc), snd (Topconstr.constr_loc c2)

(* Auxiliary grammar rules *)

GEXTEND Gram
  GLOBAL: simple_tactic constrarg constr_with_bindings quantified_hypothesis
    red_expr int_or_var castedopenconstr;

  int_or_var:
    [ [ n = integer  -> Genarg.ArgArg n
      | id = identref -> Genarg.ArgVar id ] ]
  ;
  autoarg_depth:
  [ [ n = OPT natural -> n ] ]
  ;
  autoarg_adding:
  [ [ IDENT "adding" ; "["; l = LIST1 global; "]" -> l | -> [] ] ]
  ;
  autoarg_destructing:
  [ [ IDENT "destructing" -> true | -> false ] ]
  ;
  autoarg_usingTDB:
  [ [ "using"; "tdb"  -> true | -> false ] ]
  ;
  autoargs:
  [ [ a0 = autoarg_depth; l = autoarg_adding; 
      a2 = autoarg_destructing; a3 = autoarg_usingTDB -> (a0,l,a2,a3) ] ]
  ;
  (* Either an hypothesis or a ltac ref (variable or pattern patvar) *)
  id_or_ltac_ref:
    [ [ id = base_ident -> AN id
      | "?"; n = natural -> MetaNum (loc,Pattern.patvar_of_int n) ] ]
  ;
  (* Either a global ref or a ltac ref (variable or pattern patvar) *)
  global_or_ltac_ref:
    [ [ qid = global -> AN qid
      | "?"; n = natural -> MetaNum (loc,Pattern.patvar_of_int n) ] ]
  ;
  (* An identifier or a quotation meta-variable *)
  id_or_meta:
    [ [ id = identref -> AI id 

      (* This is used in quotations *)
      | id = METAIDENT -> MetaId (loc,id) ] ]
  ;
  (* A number or a quotation meta-variable *)
  num_or_meta:
    [ [ n = integer -> AI n
      |	id = METAIDENT -> MetaId (loc,id)
      ] ]
  ;
  constrarg:
    [ [ IDENT "inst"; id = identref; "["; c = Constr.lconstr; "]" ->
        ConstrContext (id, c)
      | IDENT "eval"; rtc = Tactic.red_expr; "in"; c = Constr.lconstr ->
        ConstrEval (rtc,c) 
      | IDENT "check"; c = Constr.lconstr -> ConstrTypeOf c
      | c = Constr.lconstr -> ConstrTerm c ] ]
  ;
  castedopenconstr:
    [ [ c = lconstr -> c ] ]
  ;
  induction_arg:
    [ [ n = natural -> ElimOnAnonHyp n
      | c = lconstr -> induction_arg_of_constr c
    ] ]
  ;
  quantified_hypothesis:
    [ [ id = base_ident -> NamedHyp id
      | n = natural -> AnonHyp n ] ]
  ;
  conversion:
    [ [ nl = LIST1 integer; c1 = constr; "with"; c2 = constr ->
         (Some (nl,c1), c2)
      |	c1 = constr; "with"; c2 = constr -> (Some ([],c1), c2)
      | c = constr -> (None, c) ] ]
  ;
  pattern_occ:
    [ [ nl = LIST0 integer; c = [c=constr->c | g=global->Topconstr.CRef g]-> (nl,c) ] ]
  ;
  pattern_occ_hyp_tail_list:
    [ [ pl = pattern_occ_hyp_list -> pl | -> (None,[]) ] ]
  ;
  pattern_occ_hyp_list:
    [ [ nl = LIST1 natural; IDENT "Goal" -> (Some nl,[])
      | nl = LIST1 natural; id = id_or_meta; (g,l) = pattern_occ_hyp_tail_list
	  -> (g,(id,nl)::l)
      | IDENT "Goal" -> (Some [],[])
      | id = id_or_meta; (g,l) = pattern_occ_hyp_tail_list -> (g,(id,[])::l)
    ] ]
  ;
  clause_pattern:
    [ [ "in"; p = pattern_occ_hyp_list -> p | -> None, [] ] ]
  ;
  intropatterns:
    [ [ l = LIST0 simple_intropattern -> l ]]
  ;
  simple_intropattern:
    [ [ "["; tc = LIST1 intropatterns SEP "|" ; "]" -> IntroOrAndPattern tc
      | "("; tc = LIST1 simple_intropattern SEP "," ; ")" -> IntroOrAndPattern [tc]
      | IDENT "_" -> IntroWildcard
      | id = base_ident -> IntroIdentifier id
      ] ]
  ;
  simple_binding:
    [ [ "("; id = base_ident; ":="; c = lconstr; ")" -> (loc, NamedHyp id, c)
      | "("; n = natural; ":="; c = lconstr; ")" -> (loc, AnonHyp n, c) ] ]
  ;
  binding_list:
    [ [ test_lparcoloneq2; bl = LIST1 simple_binding -> ExplicitBindings bl
      | bl = LIST1 constr -> ImplicitBindings bl ] ]
  ;
  constr_with_bindings:
    [ [ c = constr; l = with_binding_list -> (c, l) ] ]
  ;
  with_binding_list:
    [ [ "with"; bl = binding_list -> bl | -> NoBindings ] ]
  ;
  unfold_occ:
    [ [ nl = LIST0 integer; c = global_or_ltac_ref -> (nl,c) ] ]
  ;
  red_flag:
    [ [ IDENT "beta" -> FBeta
      | IDENT "delta" -> FDeltaBut []
      | IDENT "iota" -> FIota
      | IDENT "zeta" -> FZeta
      | IDENT "delta"; "["; idl = LIST1 global_or_ltac_ref; "]" -> FConst idl
      | IDENT "delta"; "-"; "["; idl = LIST1 global_or_ltac_ref; "]" -> FDeltaBut idl
    ] ]
  ;
  red_tactic:
    [ [ IDENT "red" -> Red false
      | IDENT "hnf" -> Hnf
      | IDENT "simpl"; po = OPT pattern_occ -> Simpl po
      | IDENT "cbv"; s = LIST1 red_flag -> Cbv (make_red_flag s)
      | IDENT "lazy"; s = LIST1 red_flag -> Lazy (make_red_flag s)
      | IDENT "compute" -> Cbv (make_red_flag [FBeta;FIota;FDeltaBut [];FZeta])
      | IDENT "unfold"; ul = LIST1 unfold_occ -> Unfold ul
      | IDENT "fold"; cl = LIST1 constr -> Fold cl
      | IDENT "pattern"; pl = LIST1 pattern_occ -> Pattern pl ] ]
  ;
  (* This is [red_tactic] including possible extensions *)
  red_expr:
    [ [ IDENT "red" -> Red false
      | IDENT "hnf" -> Hnf
      | IDENT "simpl"; po = OPT pattern_occ -> Simpl po
      | IDENT "cbv"; s = LIST1 red_flag -> Cbv (make_red_flag s)
      | IDENT "lazy"; s = LIST1 red_flag -> Lazy (make_red_flag s)
      | IDENT "compute" -> Cbv (make_red_flag [FBeta;FIota;FDeltaBut [];FZeta])
      | IDENT "unfold"; ul = LIST1 unfold_occ -> Unfold ul
      | IDENT "fold"; cl = LIST1 constr -> Fold cl
      | IDENT "pattern"; pl = LIST1 pattern_occ -> Pattern pl
      | s = IDENT; c = constr -> ExtraRedExpr (s,c) ] ]
  ;
  hypident:
    [ [ id = id_or_meta -> InHyp id
      | "("; "type"; "of"; id = id_or_meta; ")" -> InHypType id ] ]
  ;
  clause:
    [ [ "in"; idl = LIST1 hypident -> idl
      | -> [] ] ]
  ;
  fixdecl:
    [ [ id = base_ident; "/"; n = natural; ":"; c = constr -> (id,n,c) ] ]
  ;
  cofixdecl:
    [ [ id = base_ident; ":"; c = constr -> (id,c) ] ]
  ;
  hintbases:
    [ [ "with"; "*" -> None
      | "with"; l = LIST1 IDENT -> Some l
      | -> Some [] ] ]
  ;
  eliminator:
    [ [ "using"; el = constr_with_bindings -> el ] ]
  ;
  with_names:
    [ [ "as"; "["; ids = LIST1 (LIST0 base_ident) SEP "|"; "]" -> ids
      | -> [] ] ]
  ;
  simple_tactic:
    [ [ 
      (* Basic tactics *)
        IDENT "intros"; IDENT "until"; id = quantified_hypothesis -> 
	  TacIntrosUntil id
      | IDENT "intros"; pl = intropatterns -> TacIntroPattern pl
      | IDENT "intro"; id = base_ident; IDENT "after"; id2 = identref ->
	  TacIntroMove (Some id, Some id2)
      | IDENT "intro"; IDENT "after"; id2 = identref ->
	  TacIntroMove (None, Some id2)
      | IDENT "intro"; id = base_ident -> TacIntroMove (Some id, None)
      | IDENT "intro" -> TacIntroMove (None, None)

      | IDENT "assumption" -> TacAssumption
      | IDENT "exact"; c = lconstr -> TacExact c

      | IDENT "apply"; cl = constr_with_bindings -> TacApply cl
      | IDENT "elim"; cl = constr_with_bindings; el = OPT eliminator ->
          TacElim (cl,el)
      | IDENT "elimtype"; c = lconstr -> TacElimType c
      | IDENT "case"; cl = constr_with_bindings -> TacCase cl
      | IDENT "casetype"; c = lconstr -> TacCaseType c
      | "fix"; n = natural -> TacFix (None,n)
      | "fix"; id = base_ident; n = natural -> TacFix (Some id,n)
      | "fix"; id = base_ident; n = natural; "with"; fd = LIST0 fixdecl ->
	  TacMutualFix (id,n,fd)
      | "cofix" -> TacCofix None
      | "cofix"; id = base_ident -> TacCofix (Some id)
      | "cofix"; id = base_ident; "with"; fd = LIST0 cofixdecl ->
	  TacMutualCofix (id,fd)

      | IDENT "cut"; c = lconstr -> TacCut c
      | IDENT "assert"; c = lconstr ->
          (match c with
              Topconstr.CCast(_,c,t) -> TacTrueCut (Some (coerce_to_id c),t)
            | _ -> TacTrueCut (None,c))
      | IDENT "assert"; c = lconstr; ":="; b = lconstr ->
          TacForward (false,Names.Name (coerce_to_id c),b)
      | IDENT "pose"; c = lconstr; ":="; b = lconstr ->
	  TacForward (true,Names.Name (coerce_to_id c),b)
      | IDENT "pose"; b = lconstr -> TacForward (true,Names.Anonymous,b)
      | IDENT "generalize"; lc = LIST1 constr -> TacGeneralize lc
      | IDENT "generalize"; IDENT "dependent"; c = lconstr ->
          TacGeneralizeDep c
      | IDENT "lettac"; id = base_ident; ":="; c = lconstr; p = clause_pattern
        -> TacLetTac (id,c,p)
      | IDENT "instantiate"; n = natural; c = lconstr -> TacInstantiate (n,c)

      | IDENT "specialize"; n = OPT natural; lcb = constr_with_bindings ->
	  TacSpecialize (n,lcb)
      | IDENT "lapply"; c = lconstr -> TacLApply c

      (* Derived basic tactics *)
      | IDENT "oldinduction"; h = quantified_hypothesis -> TacOldInduction h
      | IDENT "induction"; c = induction_arg; el = OPT eliminator;
          ids = with_names -> TacNewInduction (c,el,ids)
      | IDENT "double"; IDENT "induction"; h1 = quantified_hypothesis;
	  h2 = quantified_hypothesis -> TacDoubleInduction (h1,h2)
      | IDENT "olddestruct"; h = quantified_hypothesis -> TacOldDestruct h
      | IDENT "destruct"; c = induction_arg; el = OPT eliminator; 
          ids = with_names -> TacNewDestruct (c,el,ids)
      | IDENT "decompose"; IDENT "record" ; c = lconstr -> TacDecomposeAnd c
      | IDENT "decompose"; IDENT "sum"; c = lconstr -> TacDecomposeOr c
      | IDENT "decompose"; "["; l = LIST1 global_or_ltac_ref; "]"; c = lconstr
        -> TacDecompose (l,c)

      (* Automation tactic *)
      | IDENT "trivial"; db = hintbases -> TacTrivial db
      | IDENT "auto"; n = OPT natural; db = hintbases -> TacAuto (n, db)

      | IDENT "autotdb"; n = OPT natural -> TacAutoTDB n
      | IDENT "cdhyp"; id = identref -> TacDestructHyp (true,id)
      | IDENT "dhyp";  id = identref -> TacDestructHyp (false,id)
      | IDENT "dconcl"  -> TacDestructConcl
      | IDENT "superauto"; l = autoargs -> TacSuperAuto l
      | IDENT "auto"; n = OPT natural; IDENT "decomp"; p = OPT natural ->
	  TacDAuto (n, p)

      (* Context management *)
      | IDENT "clear"; l = LIST1 id_or_ltac_ref -> TacClear l
      | IDENT "clearbody"; l = LIST1 id_or_ltac_ref -> TacClearBody l
      | IDENT "move"; id1 = identref; IDENT "after"; id2 = identref -> 
	  TacMove (true,id1,id2)
      | IDENT "rename"; id1 = identref; IDENT "into"; id2 = identref -> 
	  TacRename (id1,id2)

      (* Constructors *)
      | IDENT "left"; bl = with_binding_list -> TacLeft bl
      | IDENT "right"; bl = with_binding_list -> TacRight bl
      | IDENT "split"; bl = with_binding_list -> TacSplit (false,bl)
      | IDENT "exists"; bl = binding_list -> TacSplit (true,bl)
      | IDENT "exists" -> TacSplit (true,NoBindings)
      | IDENT "constructor"; n = num_or_meta; l = with_binding_list ->
	  TacConstructor (n,l)
      | IDENT "constructor"; t = OPT tactic -> TacAnyConstructor t

      (* Equivalence relations *)
      | IDENT "reflexivity" -> TacReflexivity
      | IDENT "symmetry" -> TacSymmetry
      | IDENT "transitivity"; c = lconstr -> TacTransitivity c

      (* Conversion *)
      | r = red_tactic; cl = clause -> TacReduce (r, cl)
      (* Change ne doit pas s'appliquer dans un Definition t := Eval ... *)
      | IDENT "change"; (oc,c) = conversion; cl = clause -> TacChange (oc,c,cl)
    ] ]
  ;
END;;
