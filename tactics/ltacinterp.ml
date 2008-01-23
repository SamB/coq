(************************************************************************)
(*  v      *   The Coq Proof Assistant  /  The Coq Development Team     *)
(* <O___,, * CNRS-Ecole Polytechnique-INRIA Futurs-Universite Paris Sud *)
(*   \VV/  **************************************************************)
(*    //   *      This file is distributed under the terms of the       *)
(*         *       GNU Lesser General Public License Version 2.1        *)
(************************************************************************)

(* $Id$ *)

(*arnaud: commenter le module en général aussi *)

(* arnaud: peut-être faut-il considérer l'idée d'avoir un type des refine-step
   soit un constr et un environement d'evar, qui pourrait se passer en argument de tactique, plutôt que bêtement raw-constr... 
   A ce stade de la réflexion, rawconstr paraît mieux*)

open Tacexpr (*arnaud: probablement enlever les références à tacexpr qui restent*)
open Genarg
open Names
open Libnames (* arnaud: probablement garder comme ça et enlever les Libnames. *)
open Rawterm (* arnaud: probablement garder comme ça et enlever les Rawterm. *)
open Pp

(* arnaud: à commenter un peu plus dans le sens de ce que c'est vraiment. A savoir les valeurs qui peuvent être dans des variables de tactique *)
(* Values for interpretation *)
type value =
  | VTactic of Util.loc * Subproof.tactic  (* For mixed ML/Ltac tactics (e.g. Tauto) *)
  | VFun of (Names.identifier * value) list * Names.identifier option list * Tacexpr.glob_tactic_expr
  | VVoid
  | VInteger of int
  | VIntroPattern of Genarg.intro_pattern_expr
  | VConstr of Term.constr (* arnaud: constr ou rawconstr ? *)
  | VConstr_context of Term.constr (* arnaud: contr ou rawconstr ? *)
  | VList of value list
  | VRec of value ref



(*** ***)
(* arnaud: partie pas certaine, probablement souvent temporaire *)

(* arnaud: très temporaire *)
(* Gives the state of debug *)
let get_debug () = Tactic_debug.DebugOff

let locate_error_in_file dir = function
  | Stdpp.Exc_located (loc,e) -> Util.Error_in_file ("",(true,dir,loc),e)
  | e -> Util.Error_in_file ("",(true,dir,Util.dummy_loc),e)

let error_syntactic_metavariables_not_allowed loc =
  Util.user_err_loc 
    (loc,"out_ident",
     str "Syntactic metavariables allowed only in quotations")

let skip_metaid = function
  | AI x -> x
  | MetaId (loc,_) -> error_syntactic_metavariables_not_allowed loc

(* Tactics table (TacExtend). *)

let tac_tab = Hashtbl.create 17

let lookup_tactic s =
  try 
    Hashtbl.find tac_tab s
  with Not_found -> 
    Util.errorlabstrm "Refiner.lookup_tactic"
      (str"The tactic " ++ str s ++ str" is not installed")

(* arnaud: plutôt "contexte de généralisation je suppose" *)
(* Interpretation of extra generic arguments *)
type glob_sign = { 
  ltacvars : Names.identifier list * Names.identifier list;
     (* ltac variables and the subset of vars introduced by Intro/Let/... *)
  ltacrecvars : (Names.identifier * Nametab.ltac_constant) list;
     (* ltac recursive names *)
  gsigma : Evd.evar_map;
     (* arnaud: environnement pour typer les evars, pourquoi pas un defs ? *)
  genv : Environ.env }
     (* environement pour typer le reste, normal *)


(* arnaud: je comprends pas ça :( *)
(* Table of "pervasives" macros tactics (e.g. auto, simpl, etc.) *)
let atomic_mactab = ref Idmap.empty
let add_primitive_tactic s tac =
  let id = id_of_string s in
  atomic_mactab := Idmap.add id tac !atomic_mactab

let _ =
  let nocl = {onhyps=Some[];onconcl=true; concl_occs=[]} in
  List.iter
      (fun (s,t) -> add_primitive_tactic s (TacAtom(Util.dummy_loc,t)))
      [ "red", TacReduce(Red false,nocl);
        "hnf", TacReduce(Hnf,nocl);
        "simpl", TacReduce(Simpl None,nocl);
        "compute", TacReduce(Cbv all_flags,nocl);
        "intro", TacIntroMove(None,None);
        "intros", TacIntroPattern [];
        "assumption", TacAssumption;
        "cofix", TacCofix None;
        "trivial", TacTrivial ([],None);
        "auto", TacAuto(None,[],None);
        "left", TacLeft NoBindings;
        "right", TacRight NoBindings;
        "split", TacSplit(false,NoBindings);
        "constructor", TacAnyConstructor None;
        "reflexivity", TacReflexivity;
        "symmetry", TacSymmetry nocl
      ];
  List.iter
      (fun (s,t) -> add_primitive_tactic s t)
      [ "idtac",TacId [];
        "fail", TacFail(ArgArg 0,[]);
        "fresh", TacArg(TacFreshId [])
      ]
 
let lookup_atomic id = Idmap.find id !atomic_mactab
let is_atomic id = Idmap.mem id !atomic_mactab
let is_atomic_kn kn =
  let (_,_,l) = repr_kn kn in
  is_atomic (id_of_label l)

(* arnaud: / je comprends pas ça *)

let error_not_evaluable s =
  Util.errorlabstrm "evalref_of_ref" 
    (str "Cannot coerce" ++ spc ()  ++ s ++ spc () ++
     str "to an evaluable reference")



(* arnaud: recommenter peut-être ? *)
(* Signature for interpretation: val_interp and interpretation functions *)
type interp_sign =
    { lfun : (Names.identifier * value) list;
      avoid_ids : Names.identifier list; (* ids inherited from the call context
				      (needed to get fresh ids) *)
      debug : Tactic_debug.debug_info;
      last_loc : Util.loc }


(*****************)
(* Globalization *)
(*****************)
(* arnaud: globalization = jouer au binder ? *)

(* arnaud: Que veut dire ce truc ? *)
(* We have identifier <| global_reference <| constr *)








let find_ident id sign = 
  List.mem id (fst sign.ltacvars) or 
  List.mem id (Termops.ids_of_named_context (Environ.named_context sign.genv))

let find_recvar qid sign = List.assoc qid sign.ltacrecvars

(* a "var" is a ltac var or a var introduced by an intro tactic *)
let find_var id sign = List.mem id (fst sign.ltacvars)

(* a "ctxvar" is a var introduced by an intro tactic (Intro/LetTac/...) *)
let find_ctxvar id sign = List.mem id (snd sign.ltacvars)

(* a "ltacvar" is an ltac var (Let-In/Fun/...) *)
let find_ltacvar id sign = find_var id sign & not (find_ctxvar id sign)

let find_hyp id sign =
  List.mem id (Termops.ids_of_named_context (Environ.named_context sign.genv))

(* Globalize a name introduced by Intro/LetTac/... ; it is allowed to *)
(* be fresh in which case it is binding later on *)
let intern_ident l ist id =
  (* We use identifier both for variables and new names; thus nothing to do *)
  if not (find_ident id ist) then l:=(id::fst !l,id::snd !l);
  id

let intern_name l ist = function
  | Anonymous -> Anonymous
  | Name id -> Name (intern_ident l ist id)

let vars_of_ist (lfun,_,_,env) =
  List.fold_left (fun s id -> Idset.add id s)
    (Termops.vars_of_env env) lfun

(* arnaud:
let get_current_context () =
    try Pfedit.get_current_goal_context ()
    with e when Logic.catchable_exception e -> 
      (Evd.empty, Global.env())
*)

let strict_check = ref false

let adjust_loc loc = if !strict_check then Util.dummy_loc else loc

(* Globalize a name which must be bound -- actually just check it is bound *)
let intern_hyp ist (loc,id as locid) =
  if not !strict_check then
    locid
  else if find_ident id ist then
    (Util.dummy_loc,id)
  else
    Pretype_errors.error_var_not_found_loc loc id

let intern_hyp_or_metaid ist id = intern_hyp ist (skip_metaid id)

let intern_or_var ist = function
  | Rawterm.ArgVar locid -> Rawterm.ArgVar (intern_hyp ist locid)
  | Rawterm.ArgArg _ as x -> x

let loc_of_by_notation f = function
  | AN c -> f c
  | ByNotation (loc,s) -> loc

let destIndRef = function Libnames.IndRef ind -> ind | _ -> failwith "destIndRef"

let intern_inductive_or_by_notation = function
  | AN r -> Nametab.inductive_of_reference r
  | ByNotation (loc,ntn) ->
      destIndRef (Notation.interp_notation_as_global_reference loc
        (function Libnames.IndRef ind -> true | _ -> false) ntn)

let intern_inductive ist = function
  | AN (Libnames.Ident (loc,id)) when find_var id ist -> Rawterm.ArgVar (loc,id)
  | r -> Rawterm.ArgArg (intern_inductive_or_by_notation r)

let intern_global_reference ist = function
  | Libnames.Ident (loc,id) when find_var id ist -> Rawterm.ArgVar (loc,id)
  | r -> 
      let loc,qid as lqid = Libnames.qualid_of_reference r in
      try Rawterm.ArgArg (loc,Syntax_def.locate_global_with_alias lqid)
      with Not_found -> 
	Nametab.error_global_not_found_loc loc qid

let intern_tac_ref ist = function
  | Libnames.Ident (loc,id) when find_ltacvar id ist -> Rawterm.ArgVar (loc,id)
  | Libnames.Ident (loc,id) ->
      Rawterm.ArgArg (loc,
         try find_recvar id ist 
         with Not_found -> Nametab.locate_tactic (Libnames.make_short_qualid id))
  | r -> 
      let (loc,qid) = Libnames.qualid_of_reference r in
      Rawterm.ArgArg (loc,Nametab.locate_tactic qid)

let intern_tactic_reference ist r =
  try intern_tac_ref ist r
  with Not_found -> 
    let (loc,qid) = qualid_of_reference r in
    Nametab.error_global_not_found_loc loc qid

let intern_constr_reference strict ist = function
  | Ident (_,id) when (not strict & find_hyp id ist) or find_ctxvar id ist ->
      RVar (Util.dummy_loc,id), None
  | r ->
      let loc,_ as lqid = qualid_of_reference r in
      RRef (loc,Syntax_def.locate_global_with_alias lqid), if strict then None else Some (Topconstr.CRef r)

let intern_reference strict ist r =
  (try Reference (intern_tac_ref ist r)
   with Not_found ->
     (try ConstrMayEval (ConstrTerm (intern_constr_reference strict ist r))
      with Not_found ->
        (match r with
          | Ident (loc,id) when is_atomic id -> Tacexp (lookup_atomic id)
          | Ident (loc,id) when not strict -> IntroPattern (IntroIdentifier id)
          | _ ->
              let (loc,qid) = qualid_of_reference r in
              Nametab.error_global_not_found_loc loc qid)))

let intern_message_token ist = function
  | (MsgString _ | MsgInt _ as x) -> x
  | MsgIdent id -> MsgIdent (intern_hyp_or_metaid ist id)

let intern_message ist = List.map (intern_message_token ist)

let rec intern_intro_pattern lf ist = function
  | IntroOrAndPattern l ->
      IntroOrAndPattern (intern_case_intro_pattern lf ist l)
  | IntroIdentifier id ->
      IntroIdentifier (intern_ident lf ist id)
  | IntroWildcard | IntroAnonymous | IntroFresh _ as x -> x

and intern_case_intro_pattern lf ist =
  List.map (List.map (intern_intro_pattern lf ist))

let intern_quantified_hypothesis ist = function
  | AnonHyp n -> AnonHyp n
  | NamedHyp id ->
      (* Uncomment to disallow "intros until n" in ltac when n is not bound *)
      NamedHyp ((*snd (intern_hyp ist (Util.dummy_loc,*)id(* ))*))
      
let intern_binding_name ist x =
  (* We use identifier both for variables and binding names *)
  (* Todo: consider the body of the lemma to which the binding refer 
     and if a term w/o ltac vars, check the name is indeed quantified *)
  x

let intern_constr_gen isarity {ltacvars=lfun; gsigma=sigma; genv=env} c =
  let warn = if !strict_check then fun x -> x else Constrintern.for_grammar in
  let c' = 
    warn (Constrintern.intern_gen isarity ~ltacvars:(fst lfun,[]) sigma env) c
  in
  (c',if !strict_check then None else Some c)

let intern_constr = intern_constr_gen false
let intern_type = intern_constr_gen true

(* Globalize bindings *)
let intern_binding ist (loc,b,c) =
  (loc,intern_binding_name ist b,intern_constr ist c)

let intern_bindings ist = function
  | NoBindings -> NoBindings
  | ImplicitBindings l -> ImplicitBindings (List.map (intern_constr ist) l)
  | ExplicitBindings l -> ExplicitBindings (List.map (intern_binding ist) l)

let intern_constr_with_bindings ist (c,bl) =
  (intern_constr ist c, intern_bindings ist bl)

let intern_clause_pattern ist (l,occl) =
  let rec check = function
    | (hyp,l) :: rest -> (intern_hyp ist (skip_metaid hyp),l)::(check rest)
    | [] -> []
  in (l,check occl)

  (* TODO: catch ltac vars *)
let intern_induction_arg ist = function
  | ElimOnConstr c -> ElimOnConstr (intern_constr_with_bindings ist c)
  | ElimOnAnonHyp n as x -> x
  | ElimOnIdent (loc,id) ->
      if !strict_check then
	(* If in a defined tactic, no intros-until *)
	ElimOnConstr (intern_constr ist (Topconstr.CRef (Ident (Util.dummy_loc,id))),NoBindings)
      else
	ElimOnIdent (loc,id)

let evaluable_of_global_reference = function
  | ConstRef c -> EvalConstRef c
  | VarRef c -> EvalVarRef c
  | r -> error_not_evaluable (Printer.pr_global r)

let short_name = function
  | AN (Ident (loc,id)) when not !strict_check -> Some (loc,id)
  | _ -> None

let interp_global_reference r =
  let loc,qid as lqid = qualid_of_reference r in
  try Syntax_def.locate_global_with_alias lqid
  with Not_found ->
  match r with 
  | Ident (loc,id) when not !strict_check -> VarRef id
  | _ -> Nametab.error_global_not_found_loc loc qid

let intern_evaluable_reference_or_by_notation = function
  | AN r -> evaluable_of_global_reference (interp_global_reference r)
  | ByNotation (loc,ntn) ->
      evaluable_of_global_reference
      (Notation.interp_notation_as_global_reference loc
        (function ConstRef _ | VarRef _ -> true | _ -> false) ntn)

(* Globalizes a reduction expression *)
let intern_evaluable ist = function
  | AN (Ident (loc,id)) when find_ltacvar id ist -> ArgVar (loc,id)
  | AN (Ident (_,id)) when
      (not !strict_check & find_hyp id ist) or find_ctxvar id ist ->
      ArgArg (EvalVarRef id, None)
  | r ->
      let e = intern_evaluable_reference_or_by_notation r in
      let na = short_name r in
      ArgArg (e,na)

let intern_unfold ist (l,qid) = (l,intern_evaluable ist qid)

let intern_flag ist red =
  { red with rConst = List.map (intern_evaluable ist) red.rConst }

let intern_constr_occurrence ist (l,c) = (l,intern_constr ist c)

let intern_red_expr ist = function
  | Unfold l -> Unfold (List.map (intern_unfold ist) l)
  | Fold l -> Fold (List.map (intern_constr ist) l)
  | Cbv f -> Cbv (intern_flag ist f)
  | Lazy f -> Lazy (intern_flag ist f)
  | Pattern l -> Pattern (List.map (intern_constr_occurrence ist) l)
  | Simpl o -> Simpl (Option.map (intern_constr_occurrence ist) o)
  | (Red _ | Hnf | ExtraRedExpr _ | CbvVm as r ) -> r
  

let intern_inversion_strength lf ist = function
  | NonDepInversion (k,idl,ids) ->
      NonDepInversion (k,List.map (intern_hyp_or_metaid ist) idl,
      intern_intro_pattern lf ist ids)
  | DepInversion (k,copt,ids) ->
      DepInversion (k, Option.map (intern_constr ist) copt,
      intern_intro_pattern lf ist ids)
  | InversionUsing (c,idl) ->
      InversionUsing (intern_constr ist c, List.map (intern_hyp_or_metaid ist) idl)

(* Interprets an hypothesis name *)
let intern_hyp_location ist ((occs,id),hl) =
  ((List.map (intern_or_var ist) occs,intern_hyp ist (skip_metaid id)), hl)

let interp_constrpattern_gen sigma env ltacvar c =
  let c = Constrintern.intern_gen false ~allow_patvar:true ~ltacvars:(ltacvar,[])
                     sigma env c in
  Pattern.pattern_of_rawconstr c

(* Reads a pattern *)
let intern_pattern sigma env lfun = function
  | Subterm (ido,pc) ->
      let (metas,pat) = interp_constrpattern_gen sigma env lfun pc in
      ido, metas, Subterm (ido,pat)
  | Term pc ->
      let (metas,pat) = interp_constrpattern_gen sigma env lfun pc  in
      None, metas, Term pat

let intern_constr_may_eval ist = function
  | ConstrEval (r,c) -> ConstrEval (intern_red_expr ist r,intern_constr ist c)
  | ConstrContext (locid,c) ->
      ConstrContext (intern_hyp ist locid,intern_constr ist c)
  | ConstrTypeOf c -> ConstrTypeOf (intern_constr ist c)
  | ConstrTerm c -> ConstrTerm (intern_constr ist c)

(* External tactics *)
let print_xml_term = ref (fun _ -> failwith "print_xml_term unset")
let declare_xml_printer f = print_xml_term := f

let internalise_tacarg ch = G_xml.parse_tactic_arg ch

let extern_tacarg ch env sigma = function
  | VConstr c -> !print_xml_term ch env sigma c
  | VTactic _ | VFun _ | VVoid | VInteger _ | VConstr_context _
  | VIntroPattern _  | VRec _ | VList _ ->
     Util. error "Only externing of terms is implemented"

(* arnaud: à restaurer 
let extern_request ch req gl la =
  output_string ch "<REQUEST req=\""; output_string ch req;
  output_string ch "\">\n";
  List.iter (pf_apply (extern_tacarg ch) gl) la;
  output_string ch "</REQUEST>\n"
*)

(* Reads the hypotheses of a Match Context rule *)
let rec intern_match_context_hyps sigma env lfun = function
  | (Hyp ((_,na) as locna,mp))::tl ->
      let ido, metas1, pat = intern_pattern sigma env lfun mp in
      let lfun, metas2, hyps = intern_match_context_hyps sigma env lfun tl in
      let lfun' = Nameops.name_cons na (Option.List.cons ido lfun) in
      lfun', metas1@metas2, Hyp (locna,pat)::hyps
  | [] -> lfun, [], []

(* Utilities *)
let extract_names lrc =
  List.fold_right 
    (fun ((loc,name),_) l ->
      if List.mem name l then
	Util.user_err_loc
	  (loc, "intern_tactic", str "This variable is bound several times");
      name::l)
    lrc []

let extract_let_names lrc =
  List.fold_right 
    (fun ((loc,name),_,_) l ->
      if List.mem name l then
	Util.user_err_loc
	  (loc, "glob_tactic", str "This variable is bound several times");
      name::l)
    lrc []

let clause_app f = function
    { onhyps=None; onconcl=b;concl_occs=nl } ->
      { onhyps=None; onconcl=b; concl_occs=nl }
  | { onhyps=Some l; onconcl=b;concl_occs=nl } ->
      { onhyps=Some(List.map f l); onconcl=b;concl_occs=nl}

(* Globalizes tactics : raw_tactic_expr -> glob_tactic_expr *)
let rec intern_atomic lf ist x =
  match (x:raw_atomic_tactic_expr) with 
  (* Basic tactics *)
  | TacIntroPattern l ->
      TacIntroPattern (List.map (intern_intro_pattern lf ist) l)
  | TacIntrosUntil hyp -> TacIntrosUntil (intern_quantified_hypothesis ist hyp)
  | TacIntroMove (ido,ido') ->
      TacIntroMove (Option.map (intern_ident lf ist) ido,
          Option.map (intern_hyp ist) ido')
  | TacAssumption -> TacAssumption
  | TacExact c -> TacExact (intern_constr ist c)
  | TacExactNoCheck c -> TacExactNoCheck (intern_constr ist c)
  | TacVmCastNoCheck c -> TacVmCastNoCheck (intern_constr ist c)
  | TacApply (ev,cb) -> TacApply (ev,intern_constr_with_bindings ist cb)
  | TacElim (ev,cb,cbo) ->
      TacElim (ev,intern_constr_with_bindings ist cb,
               Option.map (intern_constr_with_bindings ist) cbo)
  | TacElimType c -> TacElimType (intern_type ist c)
  | TacCase (ev,cb) -> TacCase (ev,intern_constr_with_bindings ist cb)
  | TacCaseType c -> TacCaseType (intern_type ist c)
  | TacFix (idopt,n) -> TacFix (Option.map (intern_ident lf ist) idopt,n)
  | TacMutualFix (id,n,l) ->
      let f (id,n,c) = (intern_ident lf ist id,n,intern_type ist c) in
      TacMutualFix (intern_ident lf ist id, n, List.map f l)
  | TacCofix idopt -> TacCofix (Option.map (intern_ident lf ist) idopt)
  | TacMutualCofix (id,l) ->
      let f (id,c) = (intern_ident lf ist id,intern_type ist c) in
      TacMutualCofix (intern_ident lf ist id, List.map f l)
  | TacCut c -> TacCut (intern_type ist c)
  | TacAssert (otac,ipat,c) ->
      TacAssert (Option.map (intern_tactic ist) otac,
                 intern_intro_pattern lf ist ipat,
                 intern_constr_gen (otac<>None) ist c)
  | TacGeneralize cl -> TacGeneralize (List.map (intern_constr ist) cl)
  | TacGeneralizeDep c -> TacGeneralizeDep (intern_constr ist c)
  | TacLetTac (na,c,cls) ->
      let na = intern_name lf ist na in
      TacLetTac (na,intern_constr ist c,
                 (clause_app (intern_hyp_location ist) cls))

  (* Automation tactics *)
  | TacTrivial (lems,l) -> TacTrivial (List.map (intern_constr ist) lems,l)
  | TacAuto (n,lems,l) ->
      TacAuto (Option.map (intern_or_var ist) n,
        List.map (intern_constr ist) lems,l)
  | TacAutoTDB n -> TacAutoTDB n
  | TacDestructHyp (b,id) -> TacDestructHyp(b,intern_hyp ist id)
  | TacDestructConcl -> TacDestructConcl
  | TacSuperAuto (n,l,b1,b2) -> TacSuperAuto (n,l,b1,b2)
  | TacDAuto (n,p,lems) ->
      TacDAuto (Option.map (intern_or_var ist) n,p,
        List.map (intern_constr ist) lems)

  (* Derived basic tactics *)
  | TacSimpleInduction h ->
      TacSimpleInduction (intern_quantified_hypothesis ist h)
  | TacNewInduction (ev,lc,cbo,ids) ->
      TacNewInduction (ev,List.map (intern_induction_arg ist) lc,
               Option.map (intern_constr_with_bindings ist) cbo,
               (intern_intro_pattern lf ist ids))
  | TacSimpleDestruct h ->
      TacSimpleDestruct (intern_quantified_hypothesis ist h)
  | TacNewDestruct (ev,c,cbo,ids) ->
      TacNewDestruct (ev,List.map (intern_induction_arg ist) c,
               Option.map (intern_constr_with_bindings ist) cbo,
	       (intern_intro_pattern lf ist ids))
  | TacDoubleInduction (h1,h2) ->
      let h1 = intern_quantified_hypothesis ist h1 in
      let h2 = intern_quantified_hypothesis ist h2 in
      TacDoubleInduction (h1,h2)
  | TacDecomposeAnd c -> TacDecomposeAnd (intern_constr ist c)
  | TacDecomposeOr c -> TacDecomposeOr (intern_constr ist c)
  | TacDecompose (l,c) -> let l = List.map (intern_inductive ist) l in
      TacDecompose (l,intern_constr ist c)
  | TacSpecialize (n,l) -> TacSpecialize (n,intern_constr_with_bindings ist l)
  | TacLApply c -> TacLApply (intern_constr ist c)

  (* Context management *)
  | TacClear (b,l) -> TacClear (b,List.map (intern_hyp_or_metaid ist) l)
  | TacClearBody l -> TacClearBody (List.map (intern_hyp_or_metaid ist) l)
  | TacMove (dep,id1,id2) ->
    TacMove (dep,intern_hyp_or_metaid ist id1,intern_hyp_or_metaid ist id2)
  | TacRename l -> 
      TacRename (List.map (fun (id1,id2) -> 
			     intern_hyp_or_metaid ist id1, 
			     intern_hyp_or_metaid ist id2) l)
	
  (* Constructors *)
  | TacLeft bl -> TacLeft (intern_bindings ist bl)
  | TacRight bl -> TacRight (intern_bindings ist bl)
  | TacSplit (b,bl) -> TacSplit (b,intern_bindings ist bl)
  | TacAnyConstructor t -> TacAnyConstructor (Option.map (intern_tactic ist) t)
  | TacConstructor (n,bl) -> TacConstructor (n, intern_bindings ist bl)

  (* Conversion *)
  | TacReduce (r,cl) ->
      TacReduce (intern_red_expr ist r, clause_app (intern_hyp_location ist) cl)
  | TacChange (occl,c,cl) ->
      TacChange (Option.map (intern_constr_occurrence ist) occl,
        (if occl = None then intern_type ist c else intern_constr ist c),
	clause_app (intern_hyp_location ist) cl)

  (* Equivalence relations *)
  | TacReflexivity -> TacReflexivity
  | TacSymmetry idopt -> 
      TacSymmetry (clause_app (intern_hyp_location ist) idopt)
  | TacTransitivity c -> TacTransitivity (intern_constr ist c)

  (* Equality and inversion *)
  | TacRewrite (ev,l,cl) -> 
      TacRewrite 
	(ev, 
	 List.map (fun (b,c) -> (b,intern_constr_with_bindings ist c)) l,
	 clause_app (intern_hyp_location ist) cl)
  | TacInversion (inv,hyp) ->
      TacInversion (intern_inversion_strength lf ist inv,
        intern_quantified_hypothesis ist hyp)

  (* For extensions *)
  | TacExtend (loc,opn,l) ->
      let _ = lookup_tactic opn in
      TacExtend (adjust_loc loc,opn,List.map (intern_genarg ist) l)
  | TacAlias (loc,s,l,(dir,body)) ->
      let l = List.map (fun (id,a) -> (id,intern_genarg ist a)) l in
      try TacAlias (loc,s,l,(dir,body))
      with e -> raise (locate_error_in_file (string_of_dirpath dir) e)

and intern_tactic ist tac = (snd (intern_tactic_seq ist tac) : glob_tactic_expr)

and intern_tactic_seq ist = function
  | TacAtom (loc,t) ->
      let lf = ref ist.ltacvars in
      let t = intern_atomic lf ist t in
      !lf, TacAtom (adjust_loc loc, t)
  | TacFun tacfun -> ist.ltacvars, TacFun (intern_tactic_fun ist tacfun)
  | TacLetRecIn (lrc,u) ->
      let names = extract_names lrc in
      let (l1,l2) = ist.ltacvars in
      let ist = { ist with ltacvars = (names@l1,l2) } in
      let lrc = List.map (fun (n,b) -> (n,intern_tactic_fun ist b)) lrc in
      ist.ltacvars, TacLetRecIn (lrc,intern_tactic ist u)
  | TacLetIn (l,u) ->
      let l = List.map
        (fun (n,c,b) ->
          (n,Option.map (intern_tactic ist) c, intern_tacarg !strict_check ist b)) l in
      let (l1,l2) = ist.ltacvars in
      let ist' = { ist with ltacvars = ((extract_let_names l)@l1,l2) } in
      ist.ltacvars, TacLetIn (l,intern_tactic ist' u)
  | TacMatchContext (lz,lr,lmr) ->
      ist.ltacvars, TacMatchContext(lz,lr, intern_match_rule ist lmr)
  | TacMatch (lz,c,lmr) ->
      ist.ltacvars, TacMatch (lz,intern_tactic ist c,intern_match_rule ist lmr)
  | TacId l -> ist.ltacvars, TacId (intern_message ist l)
  | TacFail (n,l) -> 
      ist.ltacvars, TacFail (intern_or_var ist n,intern_message ist l)
  | TacProgress tac -> ist.ltacvars, TacProgress (intern_tactic ist tac)
  | TacAbstract (tac,s) -> ist.ltacvars, TacAbstract (intern_tactic ist tac,s)
  | TacThen (t1,[||],t2,[||]) ->
      let lfun', t1 = intern_tactic_seq ist t1 in
      let lfun'', t2 = intern_tactic_seq { ist with ltacvars = lfun' } t2 in
      lfun'', TacThen (t1,[||],t2,[||])
  | TacThen (t1,tf,t2,tl) ->
      let lfun', t1 = intern_tactic_seq ist t1 in
      let ist' = { ist with ltacvars = lfun' } in
      (* Que faire en cas de (tac complexe avec Match et Thens; tac2) ?? *)
      lfun', TacThen (t1,Array.map (intern_tactic ist') tf,intern_tactic ist' t2,
		       Array.map (intern_tactic ist') tl)
  | TacThens (t,tl) ->
      let lfun', t = intern_tactic_seq ist t in
      let ist' = { ist with ltacvars = lfun' } in
      (* Que faire en cas de (tac complexe avec Match et Thens; tac2) ?? *)
      lfun', TacThens (t, List.map (intern_tactic ist') tl)
  | TacDo (n,tac) -> 
      ist.ltacvars, TacDo (intern_or_var ist n,intern_tactic ist tac)
  | TacTry tac -> ist.ltacvars, TacTry (intern_tactic ist tac)
  | TacInfo tac -> ist.ltacvars, TacInfo (intern_tactic ist tac)
  | TacRepeat tac -> ist.ltacvars, TacRepeat (intern_tactic ist tac)
  | TacOrelse (tac1,tac2) ->
      ist.ltacvars, TacOrelse (intern_tactic ist tac1,intern_tactic ist tac2)
  | TacFirst l -> ist.ltacvars, TacFirst (List.map (intern_tactic ist) l)
  | TacSolve l -> ist.ltacvars, TacSolve (List.map (intern_tactic ist) l)
  | TacComplete tac -> ist.ltacvars, TacComplete (intern_tactic ist tac)
  | TacArg a -> ist.ltacvars, TacArg (intern_tacarg true ist a)

and intern_tactic_fun ist (var,body) = 
  let (l1,l2) = ist.ltacvars in
  let lfun' = List.rev_append (Option.List.flatten var) l1 in
  (var,intern_tactic { ist with ltacvars = (lfun',l2) } body)

and intern_tacarg strict ist = function
  | TacVoid -> TacVoid
  | Reference r -> intern_reference strict ist r
  | IntroPattern ipat -> 
      let lf = ref([],[]) in (*How to know what names the intropattern binds?*)
      IntroPattern (intern_intro_pattern lf ist ipat)
  | Integer n -> Integer n
  | ConstrMayEval c -> ConstrMayEval (intern_constr_may_eval ist c)
  | MetaIdArg (loc,s) ->
      (* $id can occur in Grammar tactic... *)
      let id = id_of_string s in
      if find_ltacvar id ist then Reference (ArgVar (adjust_loc loc,id))
      else error_syntactic_metavariables_not_allowed loc
  | TacCall (loc,f,l) ->
      TacCall (loc,
        intern_tactic_reference ist f,
        List.map (intern_tacarg !strict_check ist) l)
  | TacExternal (loc,com,req,la) -> 
      TacExternal (loc,com,req,List.map (intern_tacarg !strict_check ist) la)
  | TacFreshId x -> TacFreshId (List.map (intern_or_var ist) x)
  | Tacexp t -> Tacexp (intern_tactic ist t)
  | TacDynamic(loc,t) as x ->
      (match Dyn.tag t with
	| "tactic" | "value" | "constr" -> x
	| s -> Util.anomaly_loc (loc, "",
                 str "Unknown dynamic: <" ++ str s ++ str ">"))

(* Reads the rules of a Match Context or a Match *)
and intern_match_rule ist = function
  | (All tc)::tl ->
      All (intern_tactic ist tc) :: (intern_match_rule ist tl)
  | (Pat (rl,mp,tc))::tl ->
      let {ltacvars=(lfun,l2); gsigma=sigma; genv=env} = ist in
      let lfun',metas1,hyps = intern_match_context_hyps sigma env lfun rl in
      let ido,metas2,pat = intern_pattern sigma env lfun mp in
      let metas = Util.list_uniquize (metas1@metas2) in
      let ist' = { ist with ltacvars = (metas@(Option.List.cons ido lfun'),l2) } in
      Pat (hyps,pat,intern_tactic ist' tc) :: (intern_match_rule ist tl)
  | [] -> []

and intern_genarg ist x =
  match genarg_tag x with
  | BoolArgType -> in_gen globwit_bool (out_gen rawwit_bool x)
  | IntArgType -> in_gen globwit_int (out_gen rawwit_int x)
  | IntOrVarArgType ->
      in_gen globwit_int_or_var
        (intern_or_var ist (out_gen rawwit_int_or_var x))
  | StringArgType ->
      in_gen globwit_string (out_gen rawwit_string x)
  | PreIdentArgType ->
      in_gen globwit_pre_ident (out_gen rawwit_pre_ident x)
  | IntroPatternArgType ->
      let lf = ref ([],[]) in
      (* how to know which names are bound by the intropattern *)
      in_gen globwit_intro_pattern
        (intern_intro_pattern lf ist (out_gen rawwit_intro_pattern x))
  | IdentArgType ->
      let lf = ref ([],[]) in
      in_gen globwit_ident(intern_ident lf ist (out_gen rawwit_ident x))
  | VarArgType ->
      in_gen globwit_var (intern_hyp ist (out_gen rawwit_var x))
  | RefArgType ->
      in_gen globwit_ref (intern_global_reference ist (out_gen rawwit_ref x))
  | SortArgType ->
      in_gen globwit_sort (out_gen rawwit_sort x)
  | ConstrArgType ->
      in_gen globwit_constr (intern_constr ist (out_gen rawwit_constr x))
  | ConstrMayEvalArgType ->
      in_gen globwit_constr_may_eval 
        (intern_constr_may_eval ist (out_gen rawwit_constr_may_eval x))
  | QuantHypArgType ->
      in_gen globwit_quant_hyp
        (intern_quantified_hypothesis ist (out_gen rawwit_quant_hyp x))
  | RedExprArgType ->
      in_gen globwit_red_expr (intern_red_expr ist (out_gen rawwit_red_expr x))
  | OpenConstrArgType b ->
      in_gen (globwit_open_constr_gen b)
        ((),intern_constr ist (snd (out_gen (rawwit_open_constr_gen b) x)))
  | ConstrWithBindingsArgType ->
      in_gen globwit_constr_with_bindings
        (intern_constr_with_bindings ist (out_gen rawwit_constr_with_bindings x))
  | BindingsArgType ->
      in_gen globwit_bindings
        (intern_bindings ist (out_gen rawwit_bindings x))
  | List0ArgType _ -> app_list0 (intern_genarg ist) x
  | List1ArgType _ -> app_list1 (intern_genarg ist) x
  | OptArgType _ -> app_opt (intern_genarg ist) x
  | PairArgType _ -> app_pair (intern_genarg ist) (intern_genarg ist) x
  | ExtraArgType s ->
      match Pcoq.tactic_genarg_level s with
      | Some n -> 
          (* Special treatment of tactic arguments *)
          in_gen (Pcoq.globwit_tactic n) (intern_tactic ist
	    (out_gen (Pcoq.rawwit_tactic n) x))
      | None ->
	  Util.anomaly "Ltacinterp.intern_genarg: ExtraArgType: todo: None"
          (* arnaud: cette primitive fait appel à un goal sigma dans ses
	     dépendences, je comprends pas bien ce que ça veut dire
	     lookup_genarg_glob s ist x *)





(* arnaud: à nettoyer, mais il faut probablement reporter les commentaires
           d'abord
(* arnaud: commenter il y a deux lignes il faut les piger *)
let find_ident id sign = 
    (* Has the name been introduced by a tactic function, or and intro
       (or similar) tactic. *)
  List.mem id (fst sign.ltacvars) or 
    (* or has it been introduced earlier, like as an hypothesis of the
       current goal (if the tactic is a single_tactic) *)
    (* arnaud: single_tactic changera sûrement de nom *)
  List.mem id (Termops.ids_of_named_context (Environ.named_context sign.genv))

(* arnaud: commenter plus clairement. C'est probablement le seul endroit
   où lf est utilisé, ist aussi peut-être ? Probablement pas pour ist*)
(* Globalize a name introduced by Intro/LetTac/... ; it is allowed to *)
(* be fresh in which case it is binding later on *)
let intern_ident lf ist id =
  (* We use identifier both for variables and new names; thus nothing to do *)
  if not (find_ident id ist) then lf:=(id::fst !lf,id::snd !lf);
  id

(* arnaud: à commenter *)
let rec intern_intro_pattern lf ist = function
  | IntroOrAndPattern l ->
      IntroOrAndPattern (intern_case_intro_pattern lf ist l)
  | IntroIdentifier id ->
      IntroIdentifier (intern_ident lf ist id)
  | IntroWildcard | IntroAnonymous | IntroFresh _ as x -> x

(*arnaud: à commenter *)
and intern_case_intro_pattern lf ist =
  List.map (List.map (intern_intro_pattern lf ist))

(* Globalizes tactics : raw_tactic_expr -> glob_tactic_expr *)
let rec intern_atomic lf ist x =
  match (x:raw_atomic_tactic_expr) with 
  | TacIntroPattern l ->
      TacIntroPattern (List.map (intern_intro_pattern lf ist) l)
  | TacIntroMove _ -> Util.anomaly "Ltacinterp.intern_atomic: todo:TacIntroMove"
  | _ -> Util.anomaly "Ltacinterp.intern_atomic: todo"

(* arnaud: à déplacer et restaurer, pas encore compris ce que c'était ce
   truc strict_check. *)
let adjust_loc loc = loc (*was: if !strict_check then Util.dummy_loc else loc*)

(* arnaud: à commenter *)
let intern_tactic_seq ist = function
  | TacAtom (loc,t) ->
      let lf = ref ist.ltacvars in
      let t = intern_atomic lf ist t in
      !lf, TacAtom (adjust_loc loc, t)
  | _ -> Util.anomaly "Ltacinterp.intern_tactic_seq: todo"

let intern_tactic ist tac = (snd (intern_tactic_seq ist tac) : glob_tactic_expr)

arnaud: /à nettoyer *)









(************* End globalization ************)











(******************)
(* Interpretation *)
(******************)

(* arnaud: déplacer ? *)
(* Displays a value *)
let rec pr_value env = function
  | VVoid -> str "()"
  | VInteger n -> int n
  | VIntroPattern ipat -> pr_intro_pattern ipat
  | VConstr c | VConstr_context c ->
      (match env with Some env -> Printer.pr_lconstr_env env c | _ -> str "a term")
  | (VTactic _ | VFun _ | VRec _) -> str "a tactic"
  | VList [] -> str "an empty list"
  | VList (a::_) ->
      str "a list (first element is " ++ pr_value env a ++ str")"
let error_ltac_variable loc id env v s =
   Util.user_err_loc (loc, "", str "Ltac variable " ++ Ppconstr.pr_id id ++ 
   str " is bound to" ++ spc () ++ pr_value env v ++ spc () ++ 
   str "which cannot be coerced to " ++ str s)

exception CannotCoerceTo of string

(* Raise Not_found if not in interpretation sign *)
let try_interp_ltac_var coerce ist env (loc,id) =
  let v = List.assoc id ist.lfun in
  try coerce v with CannotCoerceTo s -> error_ltac_variable loc id env v s

(* arnaud: commenter ? *)
let coerce_to_intro_pattern env = function
  | VIntroPattern ipat -> ipat
  | VConstr c when Term.isVar c ->
      (* This happens e.g. in definitions like "Tac H = clear H; intro H" *)
      (* but also in "destruct H as (H,H')" *)
      IntroIdentifier (Term.destVar c)
  | v -> raise (CannotCoerceTo "an introduction pattern")

(* arnaud: je comprends pas ce que fait cette fonction... *)
let interp_intro_pattern_var ist env id =
  try try_interp_ltac_var (coerce_to_intro_pattern env) ist (Some env)(Util.dummy_loc,id)
  with Not_found -> IntroIdentifier id

(* arnaud: commenter ces deux fonctions *)
let rec interp_intro_pattern ist = function
  | IntroOrAndPattern l -> IntroOrAndPattern (interp_case_intro_pattern ist l)
  | IntroIdentifier id -> interp_intro_pattern_var ist (Environ.empty_env (* arnaud: corriger ça au plus vite !!!!!!!!!*) ) id
  | IntroWildcard | IntroAnonymous | IntroFresh _ as x -> x

and interp_case_intro_pattern ist =
  List.map (List.map (interp_intro_pattern ist))

(*arnaud: très temporary function *)
let unintro_pattern = function
  | IntroIdentifier id -> id
  | _ -> Util.anomaly "Ltacinterp.TacIntroPattern: pour l'instant on ne sait faire que des intro simples"

(* arnaud: très temporary function *)
let do_intro = function
  [x] -> Logic.interprete_simple_tactic_as_single_tactic (Global.env ()) (* arnaud: changer ça probablement *)
                                                          (Logic.Intro x)
  | _ -> Util.anomaly "Ltacinterp.TacIntroPattern: pour l'instant on ne sait faire que des intro simples (bis)"

let interp_atomic ist = function
  (* Basic tactics *)
  | TacIntroPattern l ->
         Subproof.single_tactic (do_intro (List.map unintro_pattern (List.map (interp_intro_pattern ist) l)))
  | TacIntrosUntil hyp -> Util.anomaly "Ltacinterp.interp_atomic: todo: TacIntrosUntil"
  | TacIntroMove (ido,ido') ->
      match ido with
      | None -> Util.anomaly "Ltacinterp.inter_atomic: todo: TacIntroMove: None"
      | Some id ->
	  Subproof.single_tactic (Logic.interprete_simple_tactic_as_single_tactic (Global.env () (* arnaud: changer ça probablement *)) (Logic.Intro id))
      (* arnaud:
      h_intro_move (Option.map (interp_fresh_ident ist gl) ido)
      (Option.map (interp_hyp ist gl) ido')
      *)
  | _ -> Util.anomaly "Ltacinterp.interp_atomic: todo"

(* arnaud: à déplacer ?*)
(* For tactic_of_value *)
exception NotTactic

(* Gives the tactic corresponding to the tactic value *)
let tactic_of_value vle =
  match vle with
  | VTactic (loc,tac) -> tac (* arnaud:remettre les infos de location ?*)
  | VFun _ -> Util.error "A fully applied tactic is expected"
  | _ -> raise NotTactic

(* arnaud: commenter et renommer *)
let other_eval_tactic ist = function
  | TacAtom (loc,t) -> interp_atomic ist t
  | _ -> Util.anomaly "Ltacinterp.other_eval_tactic: todo"

let rec val_interp ist (tac:glob_tactic_expr) =

  let value_interp ist = match tac with
  (* Immediate evaluation *)
  | TacFun (it,body) -> VFun (ist.lfun,it,body)
  (* arnaud: todo? : TacArg, TacLet(Rec)In*)
  (* Delayed_evaluation *)
  | t -> VTactic (ist.last_loc,other_eval_tactic ist t)
  in
  Util.check_for_interrupt ();
    match ist.debug with
    | Tactic_debug.DebugOn lev -> Util.anomaly "Ltacinterp.tactic_of_value: todo"
	(* arnaud:was: debug_prompt lev gl tac (fun v -> value_interp {ist with debug=v})*)
    | _ -> value_interp ist 

(* arnaud: commenter ? *)
let interp_tactic ist tac  =
  try tactic_of_value (val_interp ist tac) 
  with NotTactic ->
    Util.errorlabstrm "" (str "Must be a command or must give a tactic value")

(* arnaud: commenter/renommer *)
let eval_tactic t =
  interp_tactic { lfun=[]; avoid_ids=[]; debug=get_debug(); last_loc=Util.dummy_loc } t



(* arnaud: fonction très temporaire *)
let hide_interp p t ot =
  let ist = { ltacvars = ([],[]); 
	      ltacrecvars = []; 
              gsigma = Evd.evars_of (Subproof.defs_of (Proof.subproof_of p));
              genv = Global.env () } in
  let te = intern_tactic ist t in
  let t = eval_tactic te in
  match ot with 
  | None -> t
      (* arnaud: was: abstract_tactic_expr (TacArg (Tacexp te)) t*)
  | Some t' -> Util.anomaly "Logic.hide_interp: todo: end tactic"
      (* arnaud: original: abstract_tactic_expr ~dflt:true (TacArg (Tacexp te)) (tclTHEN t t') gl*)