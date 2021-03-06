(* -*- compile-command: "make -C .. bin/coqtop.byte" -*- *)
(************************************************************************)
(*  v      *   The Coq Proof Assistant  /  The Coq Development Team     *)
(* <O___,, * CNRS-Ecole Polytechnique-INRIA Futurs-Universite Paris Sud *)
(*   \VV/  **************************************************************)
(*    //   *      This file is distributed under the terms of the       *)
(*         *       GNU Lesser General Public License Version 2.1        *)
(************************************************************************)

(*i $Id$ i*)

(*i*)
open Names
open Decl_kinds
open Term
open Termops
open Sign
open Entries
open Evd
open Environ
open Nametab
open Mod_subst
open Util
open Typeclasses_errors
open Typeclasses
open Libnames
open Constrintern
open Rawterm
open Topconstr
(*i*)

open Decl_kinds
open Entries

let hint_db = "typeclass_instances"

let qualid_of_con c = 
  Qualid (dummy_loc, shortest_qualid_of_global Idset.empty (ConstRef c))

let _ =
  Typeclasses.register_add_instance_hint 
    (fun inst pri ->
      Flags.silently (fun () ->      
	Auto.add_hints false [hint_db] 
	  (Vernacexpr.HintsResolve 
	      [pri, CAppExpl (dummy_loc, (None, qualid_of_con inst), [])])) ())

let declare_instance_cst glob con =
  let instance = Typeops.type_of_constant (Global.env ()) con in
  let _, r = decompose_prod_assum instance in
    match class_of_constr r with
      | Some tc -> add_instance (new_instance tc None glob con)
      | None -> error "Constant does not build instances of a declared type class"

let declare_instance glob idl =
  let con = 
    try (match global (Ident idl) with
      | ConstRef x -> x
      | _ -> raise Not_found)
    with _ -> error "Instance definition not found"
  in declare_instance_cst glob con
	  
let mismatched_params env n m = mismatched_ctx_inst env Parameters n m
let mismatched_props env n m = mismatched_ctx_inst env Properties n m

type binder_list = (identifier located * bool * constr_expr) list

(* Calls to interpretation functions. *)

let interp_binders_evars isevars env avoid l =
  List.fold_left
    (fun (env, ids, params) ((loc, i), t) -> 
      let n = Name i in
      let t' = interp_binder_evars isevars env n t in
      let d = (i,None,t') in
	(push_named d env, i :: ids, d::params))
    (env, avoid, []) l

let interp_typeclass_context_evars isevars env avoid l =
  List.fold_left
    (fun (env, ids, params) (iid, bk, l) -> 
      let t' = interp_binder_evars isevars env (snd iid) l in
      let i = match snd iid with
	| Anonymous -> Nameops.next_name_away (Termops.named_hd env t' Anonymous) ids
	| Name id -> id
      in
      let d = (i,None,t') in
	(push_named d env, i :: ids, d::params))
    (env, avoid, []) l

let interp_type_evars evdref env ?(impls=([],[])) typ =
  let typ' = intern_gen true ~impls (Evd.evars_of !evdref) env typ in
  let imps = Implicit_quantifiers.implicits_of_rawterm typ' in
    imps, Pretyping.Default.understand_tcc_evars evdref env Pretyping.IsType typ'

let mk_interning_data env na impls typ =
  let impl = Impargs.compute_implicits_with_manual env typ (Impargs.is_implicit_args()) impls
  in (na, ([], impl, Notation.compute_arguments_scope typ))
    
let interp_fields_evars isevars env avoid l =
  List.fold_left
    (fun (env, uimpls, ids, params, impls) ((loc, i), _, t) -> 
      let impl, t' = interp_type_evars isevars env ~impls t in
      let data = mk_interning_data env i impl t' in
      let d = (Name i,None,t') in
	(push_rel d env, impl :: uimpls, Idset.add i ids, d::params, ([], data :: snd impls)))
    (env, [], avoid, [], ([], [])) l    

(* Declare everything in the parameters as implicit, and the class instance as well *)

open Topconstr

let declare_implicit_proj c proj imps sub =
  let len = List.length c.cl_context in
  let (ctx, _) = decompose_prod_n (len + 1) (Typeops.type_of_constant (Global.env()) (snd proj)) in
  let expls =
    let rec aux i expls = function
	[] -> expls
      | (Name n, _) :: tl -> 
	  let impl = ExplByPos (i, Some n), (true, true) in
	    aux (succ i) (impl :: List.remove_assoc (ExplByName n) expls) tl
      | (Anonymous,_) :: _ -> assert(false)
    in
      aux 1 [] (List.rev ctx)
  in 
  let expls = expls @ List.map (function (ExplByPos (i, n), f) -> (ExplByPos (succ len + i, n)), f | _ -> assert(false)) imps in
    if sub then 
      declare_instance_cst true (snd proj);
    Impargs.declare_manual_implicits false (ConstRef (snd proj)) true expls
      
let declare_implicits impls subs cl =
  Util.list_iter3 (fun p imps sub -> declare_implicit_proj cl p imps sub)
    cl.cl_projs impls subs;
  let len = List.length cl.cl_context in
  let indimps = 
    list_fold_left_i 
      (fun i acc (is, (na, b, t)) -> 
	if len - i <= cl.cl_params then acc
	else 
	  match is with
	      None | Some (_, false) -> (ExplByPos (i, Some (Nameops.out_name na)), (false, true)) :: acc
	    | _ -> acc)
      1 [] (List.rev cl.cl_context)
  in
    Impargs.declare_manual_implicits false cl.cl_impl false indimps
      
let degenerate_decl (na,b,t) =
  let id = match na with
    | Name id -> id
    | Anonymous -> anomaly "Unnamed record variable" in 
  match b with
    | None -> (id, Entries.LocalAssum t)
    | Some b -> (id, Entries.LocalDef b)

let declare_structure env id idbuild params arity fields =
  let nparams = List.length params and nfields = List.length fields in
  let args = extended_rel_list nfields params in
  let ind = applist (mkRel (1+nparams+nfields), args) in
  let type_constructor = it_mkProd_or_LetIn ind fields in
  let mie_ind =
    { mind_entry_typename = id;
      mind_entry_arity = arity;
      mind_entry_consnames = [idbuild];
      mind_entry_lc = [type_constructor] } in
  let mie =
    { mind_entry_params = List.map degenerate_decl params;
      mind_entry_record = true;
      mind_entry_finite = true;
      mind_entry_inds = [mie_ind] } in
  let kn = Command.declare_mutual_with_eliminations true mie [] in
  let rsp = (kn,0) in (* This is ind path of idstruc *)
  let id = Nameops.next_ident_away id (ids_of_context (Global.env())) in
  let kinds,sp_projs = Record.declare_projections rsp ~kind:Method ~name:id (List.map (fun _ -> false) fields) fields in
  let _build = ConstructRef (rsp,1) in
    Recordops.declare_structure(rsp,idbuild,List.rev kinds,List.rev sp_projs);
    rsp

let name_typeclass_binder avoid = function
  | LocalRawAssum ([loc, Anonymous], bk, c) ->
      let name = 
	let id = 
	match c with
	    CApp (_, (_, CRef (Ident (loc,id))), _) -> id
	  | _ -> id_of_string "assum"
	in Implicit_quantifiers.make_fresh avoid (Global.env ()) id
      in LocalRawAssum ([loc, Name name], bk, c), Idset.add name avoid
  | x -> x, avoid

let name_typeclass_binders avoid l = 
  let l', avoid = 
    List.fold_left 
      (fun (binders, avoid) b -> let b', avoid = name_typeclass_binder avoid b in
				   b' :: binders, avoid)
      ([], avoid) l
  in List.rev l', avoid
      
let new_class id par ar sup props =
  let env0 = Global.env() in
  let isevars = ref (Evd.create_evar_defs Evd.empty) in
  let bound = Implicit_quantifiers.ids_of_list (Termops.ids_of_context env0) in
  let bound, ids = Implicit_quantifiers.free_vars_of_binders ~bound [] (sup @ par) in
  let bound = Idset.union bound (Implicit_quantifiers.ids_of_list ids) in
  let sup, bound = name_typeclass_binders bound sup in
  let supnames = 
    List.fold_left (fun acc b -> 
      match b with
	  LocalRawAssum (nl, _, _) -> nl @ acc
	| LocalRawDef _ -> assert(false))
      [] sup
  in

  (* Interpret the arity *)
  let arity_imps, fullarity = 
    let ar = 
      match ar with
	Some ar -> ar | None -> (dummy_loc, Rawterm.RType None)
    in
    let arity = CSort (fst ar, snd ar) in
    let term = prod_constr_expr (prod_constr_expr arity par) sup in
      interp_type_evars isevars env0 term      
  in
  let ctx_params, arity = decompose_prod_assum fullarity in
  let env_params = push_rel_context ctx_params env0 in
    
  (* Interpret the definitions and propositions *)
  let env_props, prop_impls, bound, ctx_props, _ = 
    interp_fields_evars isevars env_params bound props 
  in
  let subs = List.map (fun ((loc, id), b, _) -> b) props in
  (* Instantiate evars and check all are resolved *)
  let isevars,_ = Evarconv.consider_remaining_unif_problems env_props !isevars in
  let isevars = Typeclasses.resolve_typeclasses env_props isevars in
  let sigma = Evd.evars_of isevars in
  let ctx_params = Evarutil.nf_rel_context_evar sigma ctx_params in
  let ctx_props = Evarutil.nf_rel_context_evar sigma ctx_props in
  let arity = Reductionops.nf_evar sigma arity in
  let ce t = Evarutil.check_evars env0 Evd.empty isevars t in
  let impl, projs = 
    let params = ctx_params and fields = ctx_props in
      List.iter (fun (_,c,t) -> ce t; match c with Some c -> ce c | None -> ()) (params @ fields);
      match fields with
	  [(Name proj_name, _, field)] ->
	    let class_body = it_mkLambda_or_LetIn field params in
	    let class_type = 
	      match ar with
		  Some _ -> Some (it_mkProd_or_LetIn arity params)
		| None -> None
	    in
	    let class_entry = 
	      { const_entry_body = class_body;
		const_entry_type = class_type;
		const_entry_opaque = false;
		const_entry_boxed = false }
	    in
	    let cst = Declare.declare_constant (snd id)
	      (DefinitionEntry class_entry, IsDefinition Definition) 
	    in
	    let inst_type = appvectc (mkConst cst) (rel_vect 0 (List.length params)) in
	    let proj_type = it_mkProd_or_LetIn (mkProd(Name (snd id), inst_type, lift 1 field)) params in
	    let proj_body = it_mkLambda_or_LetIn (mkLambda (Name (snd id), inst_type, mkRel 1)) params in
	    let proj_entry = 
	      { const_entry_body = proj_body;
		const_entry_type = Some proj_type;
		const_entry_opaque = false;
		const_entry_boxed = false }
	    in
	    let proj_cst = Declare.declare_constant proj_name
	      (DefinitionEntry proj_entry, IsDefinition Definition) 
	    in
	      ConstRef cst, [proj_name, proj_cst]
	| _ ->
	    let idb = id_of_string ("Build_" ^ (string_of_id (snd id))) in
	    let kn = declare_structure env0 (snd id) idb params arity fields in
	      IndRef kn, (List.map2 (fun (id, _, _) y -> Nameops.out_name id, Option.get y)
			     fields (Recordops.lookup_projections kn))
  in
  let ctx_context =
    List.map (fun ((na, b, t) as d) -> 
      match Typeclasses.class_of_constr t with
      | Some cl -> (Some (cl.cl_impl, List.exists (fun (_, n) -> n = na) supnames), d)
      | None -> (None, d))
      ctx_params
  in
  let k =
    { cl_impl = impl;
      cl_params = List.length par;
      cl_context = ctx_context;
      cl_props = ctx_props;
      cl_projs = projs }
  in
    declare_implicits (List.rev prop_impls) subs k;
    add_class k
    
type binder_def_list = (identifier located * identifier located list * constr_expr) list

let binders_of_lidents l =
  List.map (fun (loc, id) -> LocalRawAssum ([loc, Name id], Default Rawterm.Implicit, CHole (loc, None))) l

let type_ctx_instance isevars env ctx inst subst =
  List.fold_left2
    (fun (subst, instctx) (na, _, t) ce ->
      let t' = substl subst t in
      let c = interp_casted_constr_evars isevars env ce t' in
      let d = na, Some c, t' in
	c :: subst, d :: instctx)
    (subst, []) (List.rev ctx) inst

let refine_ref = ref (fun _ -> assert(false))

let id_of_class cl =
  match cl.cl_impl with
    | ConstRef kn -> let _,_,l = repr_con kn in id_of_label l
    | IndRef (kn,i) -> 
	let mip = (Environ.lookup_mind kn (Global.env ())).Declarations.mind_packets in
	  mip.(0).Declarations.mind_typename
    | _ -> assert false
	
open Pp

let ($$) g f = fun x -> g (f x)

let default_on_free_vars =
  Flags.if_verbose
    (fun fvs ->
      match fvs with
	  [] -> ()
	| l -> msgnl (str"Implicitly generalizing " ++ 
			 prlist_with_sep (fun () -> str", ") Nameops.pr_id l ++ str"."))

let fail_on_free_vars = function
    [] -> ()
  | [fv] ->
      errorlabstrm "Classes" 
	(str"Unbound variable " ++ Nameops.pr_id fv ++ str".")
  | fvs -> errorlabstrm "Classes" 
      (str"Unbound variables " ++
	  prlist_with_sep (fun () -> str", ") Nameops.pr_id fvs ++ str".")
	
let instance_hook k pri global imps ?hook cst = 
  let inst = Typeclasses.new_instance k pri global cst in
    Impargs.maybe_declare_manual_implicits false (ConstRef cst) false imps;
    Typeclasses.add_instance inst;
    (match hook with Some h -> h cst | None -> ())

let declare_instance_constant k pri global imps ?hook id term termtype =
  let cdecl = 
    let kind = IsDefinition Instance in
    let entry = 
      { const_entry_body   = term;
	const_entry_type   = Some termtype;
	const_entry_opaque = false;
	const_entry_boxed  = false }
    in DefinitionEntry entry, kind
  in
  let kn = Declare.declare_constant id cdecl in
    Flags.if_verbose Command.definition_message id;
    instance_hook k pri global imps ?hook kn;
    id

let new_instance ?(global=false) ctx (instid, bk, cl) props ?(on_free_vars=default_on_free_vars) 
    ?(tac:Proof_type.tactic option) ?(hook:(Names.constant -> unit) option) pri =
  let env = Global.env() in
  let isevars = ref (Evd.create_evar_defs Evd.empty) in
  let bound = Implicit_quantifiers.ids_of_list (Termops.ids_of_context env) in
  let bound, fvs = Implicit_quantifiers.free_vars_of_binders ~bound [] ctx in
  let tclass = 
    match bk with
      | Implicit ->
	  let loc, id, par = Implicit_quantifiers.destClassAppExpl cl in
	  let k = class_info (Nametab.global id) in
	  let applen = List.fold_left (fun acc (x, y) -> if y = None then succ acc else acc) 0 par in
	  let needlen = List.fold_left (fun acc (x, y) -> if x = None then succ acc else acc) 0 k.cl_context in
	    if needlen <> applen then 
	      mismatched_params env (List.map fst par) (List.map snd k.cl_context);
	    let pars, _ = Implicit_quantifiers.combine_params Idset.empty (* need no avoid *)
	      (fun avoid (clname, (id, _, t)) -> 
		match clname with 
		    Some (cl, b) -> 
		      let t = 
			if b then 
			  let _k = class_info cl in
			    CHole (Util.dummy_loc, Some (Evd.ImplicitArg (k.cl_impl, (1, None))))
			else CHole (Util.dummy_loc, None)
		      in t, avoid
		  | None -> failwith ("new instance: under-applied typeclass"))
	      par (List.rev k.cl_context)
	    in Topconstr.CAppExpl (loc, (None, id), pars)

      | Explicit -> cl
  in
  let ctx_bound = Idset.union bound (Implicit_quantifiers.ids_of_list fvs) in
  let gen_ids = Implicit_quantifiers.free_vars_of_constr_expr ~bound:ctx_bound tclass [] in
  on_free_vars (List.rev fvs @ List.rev gen_ids);
  let gen_idset = Implicit_quantifiers.ids_of_list gen_ids in
  let bound = Idset.union gen_idset ctx_bound in
  let gen_ctx = Implicit_quantifiers.binder_list_of_ids gen_ids in
  let ctx, avoid = name_typeclass_binders bound ctx in
  let ctx = List.append ctx (List.rev gen_ctx) in
  let k, ctx', imps, subst = 
    let c = Command.generalize_constr_expr tclass ctx in
    let imps, c' = interp_type_evars isevars env c in
    let ctx, c = decompose_prod_assum c' in
    let cl, args = Typeclasses.dest_class_app c in
      cl, ctx, imps, List.rev (Array.to_list args)
  in
  let id = 
    match snd instid with
	Name id -> 
	  let sp = Lib.make_path id in
	    if Nametab.exists_cci sp then
	      errorlabstrm "new_instance" (Nameops.pr_id id ++ Pp.str " already exists");
	    id
      | Anonymous -> 
	  let i = Nameops.add_suffix (id_of_class k) "_instance_0" in
	    Termops.next_global_ident_away false i (Termops.ids_of_context env)
  in
  let env' = push_rel_context ctx' env in
  isevars := Evarutil.nf_evar_defs !isevars;
  isevars := resolve_typeclasses env !isevars;
  let sigma = Evd.evars_of !isevars in
  let substctx = List.map (Evarutil.nf_evar sigma) subst in
    if Lib.is_modtype () then
      begin
	let _, ty_constr = instance_constructor k (List.rev subst) in
	let termtype = 
	  let t = it_mkProd_or_LetIn ty_constr ctx' in
	    Evarutil.nf_isevar !isevars t
	in
	Evarutil.check_evars env Evd.empty !isevars termtype;
	let cst = Declare.declare_internal_constant id
	  (Entries.ParameterEntry (termtype,false), Decl_kinds.IsAssumption Decl_kinds.Logical)
	in instance_hook k None false imps ?hook cst; id
      end
    else
      begin
	let subst, _propsctx = 
	  let props = 
	    List.map (fun (x, l, d) -> 
	      x, Topconstr.abstract_constr_expr d (binders_of_lidents l))
	      props
	  in
	    if List.length props > List.length k.cl_props then 
	      mismatched_props env' (List.map snd props) k.cl_props;
	    let props, rest = 
	      List.fold_left
		(fun (props, rest) (id,_,_) -> 
		  try 
		    let ((loc, mid), c) = List.find (fun ((_,id'), c) -> Name id' = id) rest in
		    let rest' = List.filter (fun ((_,id'), c) -> Name id' <> id) rest in
		      Dumpglob.add_glob loc (ConstRef (List.assoc mid k.cl_projs));
		      c :: props, rest'
		  with Not_found -> (CHole (Util.dummy_loc, None) :: props), rest)
		([], props) k.cl_props
	    in
	      if rest <> [] then 
		unbound_method env' k.cl_impl (fst (List.hd rest))
	      else
		type_ctx_instance isevars env' k.cl_props props substctx
	in
	let app, ty_constr = instance_constructor k (List.rev subst) in
	let termtype = 
	  let t = it_mkProd_or_LetIn ty_constr ctx' in
	    Evarutil.nf_isevar !isevars t
	in
	let term = Termops.it_mkLambda_or_LetIn app ctx' in
	isevars := Evarutil.nf_evar_defs !isevars;
	let term = Evarutil.nf_isevar !isevars term in
	let evm = Evd.evars_of (undefined_evars !isevars) in
	Evarutil.check_evars env Evd.empty !isevars termtype;
	  if evm = Evd.empty then
	    declare_instance_constant k pri global imps ?hook id term termtype
	  else begin
	    isevars := Typeclasses.resolve_typeclasses ~onlyargs:true ~fail:true env !isevars;
	    let kind = Decl_kinds.Global, Decl_kinds.DefinitionBody Decl_kinds.Instance in
	      Flags.silently (fun () ->
		Command.start_proof id kind termtype 
		  (fun _ -> function ConstRef cst -> instance_hook k pri global imps ?hook cst
		    | _ -> assert false);
		if props <> [] then 
		  Pfedit.by (* (Refiner.tclTHEN (Refiner.tclEVARS (Evd.evars_of !isevars)) *)
		    (!refine_ref (evm, term));
		(match tac with Some tac -> Pfedit.by tac | None -> ())) ();
	      Flags.if_verbose (msg $$ Printer.pr_open_subgoals) ();
	      id
	  end
      end

let context ?(hook=fun _ -> ()) l =
  let env = Global.env() in
  let isevars = ref (Evd.create_evar_defs Evd.empty) in
  let avoid = Termops.ids_of_context env in
  let ctx, l = Implicit_quantifiers.resolve_class_binders (vars_of_env env) l in
  let env', avoid, ctx = interp_binders_evars isevars env avoid ctx in
  let env', avoid, l = interp_typeclass_context_evars isevars env' avoid l in
  isevars := Evarutil.nf_evar_defs !isevars;
  let sigma = Evd.evars_of !isevars in
  let fullctx = Evarutil.nf_named_context_evar sigma (l @ ctx) in
    List.iter (function (id,_,t) -> 
      if Lib.is_modtype () then 
	let cst = Declare.declare_internal_constant id
	  (ParameterEntry (t,false), IsAssumption Logical)
	in
	  match class_of_constr t with
	    | Some tc ->
		add_instance (Typeclasses.new_instance tc None false cst);
		hook (ConstRef cst)
	    | None -> ()
      else
	(Command.declare_one_assumption false (Local (* global *), Definitional) t
	    [] true (* implicit *) true (* always kept *) false (* inline *) (dummy_loc, id);
	 match class_of_constr t with
	     None -> ()
	   | Some tc -> hook (VarRef id)))
      (List.rev fullctx)
