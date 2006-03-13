(************************************************************************)
(*  v      *   The Coq Proof Assistant  /  The Coq Development Team     *)
(* <O___,, * CNRS-Ecole Polytechnique-INRIA Futurs-Universite Paris Sud *)
(*   \VV/  **************************************************************)
(*    //   *      This file is distributed under the terms of the       *)
(*         *       GNU Lesser General Public License Version 2.1        *)
(************************************************************************)

(* $Id$ *)

open Global
open Pp
open Util
open Names
open Sign
open Evd
open Term
open Termops
open Reductionops
open Environ
open Type_errors
open Typeops
open Libnames
open Classops
open List
open Recordops 
open Evarutil
open Pretype_errors
open Rawterm
open Evarconv
open Pattern
open Dyn
open Pretyping

open Subtac_coercion
open Scoq
open Coqlib
open Printer
open Subtac_errors
open Context
open Eterm

type recursion_info = {
  arg_name: name;
  arg_type: types; (* A *)
  args_after : rel_context;
  wf_relation: constr; (* R : A -> A -> Prop *)
  wf_proof: constr; (* : well_founded R *)
  f_type: types; (* f: A -> Set *)
  f_fulltype: types; (* Type with argument and wf proof product first *)
}

let my_print_rec_info env t = 
  str "Name: " ++ Nameops.pr_name t.arg_name ++ spc () ++
  str "Arg type: " ++ my_print_constr env t.arg_type ++ spc () ++
  str "Wf relation: " ++ my_print_constr env t.wf_relation ++ spc () ++
  str "Wf proof: " ++ my_print_constr env t.wf_proof ++ spc () ++
  str "Abbreviated Type: " ++ my_print_constr env t.f_type ++ spc () ++
  str "Full type: " ++ my_print_constr env t.f_fulltype

(* Taken from pretyping.ml *)
let evd_comb0 f isevars =
  let (evd',x) = f !isevars in
  isevars := evd';
  x
let evd_comb1 f isevars x =
  let (evd',y) = f !isevars x in
  isevars := evd';
  y
let evd_comb2 f isevars x y =
  let (evd',z) = f !isevars x y in
  isevars := evd';
  z
let evd_comb3 f isevars x y z =
  let (evd',t) = f !isevars x y z in
  isevars := evd';
  t

(************************************************************************)
(* This concerns Cases *)
open Declarations
open Inductive
open Inductiveops

(************************************************************************)

let mt_evd = Evd.empty

let vect_lift_type = Array.mapi (fun i t -> type_app (lift i) t)

(* Utilisé pour inférer le prédicat des Cases *)
(* Semble exagérement fort *)
(* Faudra préférer une unification entre les types de toutes les clauses *)
(* et autoriser des ? à rester dans le résultat de l'unification *)

let evar_type_fixpoint loc env isevars lna lar vdefj =
  let lt = Array.length vdefj in 
    if Array.length lar = lt then 
      for i = 0 to lt-1 do 
        if not (e_cumul env isevars (vdefj.(i)).uj_type
		  (lift lt lar.(i))) then
          error_ill_typed_rec_body_loc loc env (evars_of !isevars)
            i lna vdefj lar
      done

let check_branches_message loc env isevars c (explft,lft) = 
  for i = 0 to Array.length explft - 1 do
    if not (e_cumul env isevars lft.(i) explft.(i)) then 
      let sigma = evars_of !isevars in
      error_ill_formed_branch_loc loc env sigma c i lft.(i) explft.(i)
  done

(* coerce to tycon if any *)
let inh_conv_coerce_to_tycon loc env isevars j = function
   | None -> j
   | Some typ -> evd_comb2 (Subtac_coercion.inh_conv_coerce_to loc env) isevars j typ

let push_rels vars env = List.fold_right push_rel vars env

let strip_meta id = (* For Grammar v7 compatibility *)
  let s = string_of_id id in
  if s.[0]='$' then id_of_string (String.sub s 1 (String.length s - 1))
  else id

let pretype_id loc env (lvar,unbndltacvars) id =
  let id = strip_meta id in (* May happen in tactics defined by Grammar *)
  try
    let (n,typ) = lookup_rel_id id (rel_context env) in
    { uj_val  = mkRel n; uj_type = type_app (lift n) typ }
  with Not_found ->
  try
    List.assoc id lvar
  with Not_found ->
  try
    let (_,_,typ) = lookup_named id env in
    { uj_val  = mkVar id; uj_type = typ }
  with Not_found ->
  try (* To build a nicer ltac error message *)
    match List.assoc id unbndltacvars with
      | None -> user_err_loc (loc,"",
	  str (string_of_id id ^ " ist not bound to a term"))
      | Some id0 -> Pretype_errors.error_var_not_found_loc loc id0
  with Not_found ->
    error_var_not_found_loc loc id

(* make a dependent predicate from an undependent one *)

let make_dep_of_undep env (IndType (indf,realargs)) pj =
  let n = List.length realargs in
  let rec decomp n p =
    if n=0 then p else
      match kind_of_term p with
	| Lambda (_,_,c) -> decomp (n-1) c
	| _ -> decomp (n-1) (applist (lift 1 p, [mkRel 1])) 
  in
  let sign,s = decompose_prod_n n pj.uj_type in
  let ind = build_dependent_inductive env indf in
  let s' = mkProd (Anonymous, ind, s) in
  let ccl = lift 1 (decomp n pj.uj_val) in
  let ccl' = mkLambda (Anonymous, ind, ccl) in
  {uj_val=lam_it ccl' sign; uj_type=prod_it s' sign} 

(*************************************************************************)
(* Main pretyping function                                               *)

let pretype_ref isevars env ref = 
  let c = constr_of_global ref in
  make_judge c (Retyping.get_type_of env Evd.empty c)

let pretype_sort = function
  | RProp c -> judge_of_prop_contents c
  | RType _ -> judge_of_new_Type ()

let my_print_tycon env = function
    Some t -> my_print_constr env t
  | None -> str "None"

(* [pretype tycon env isevars lvar lmeta cstr] attempts to type [cstr] *)
(* in environment [env], with existential variables [(evars_of isevars)] and *)
(* the type constraint tycon *)
let rec pretype tycon env isevars lvar c = 
  trace (str "pretype for " ++ (my_print_rawconstr env c) ++
	   str " and tycon "++ my_print_tycon env tycon ++
	   str " in environment: " ++ my_print_env env);
  match c with

  | RRef (loc,ref) ->
      inh_conv_coerce_to_tycon loc env isevars
	(pretype_ref isevars env ref)
	tycon

  | RVar (loc, id) ->
      inh_conv_coerce_to_tycon loc env isevars
	(pretype_id loc env lvar id)
	tycon

  | REvar (loc, ev, instopt) ->
      (* Ne faudrait-il pas s'assurer que hyps est bien un
      sous-contexte du contexte courant, et qu'il n'y a pas de Rel "caché" *)
      let hyps = evar_context (Evd.map (evars_of !isevars) ev) in
      let args = match instopt with
        | None -> instance_from_named_context hyps
        | Some inst -> failwith "Evar subtitutions not implemented" in
      let c = mkEvar (ev, args) in
      let j = (Retyping.get_judgment_of env (evars_of !isevars) c) in
      inh_conv_coerce_to_tycon loc env isevars j tycon

  | RPatVar (loc,(someta,n)) -> 
      anomaly "Found a pattern variable in a rawterm to type"
	   
  | RHole (loc,k) ->
      let ty =
        match tycon with 
          | Some ty -> ty
          | None ->
              e_new_evar isevars env ~src:(loc,InternalHole) (new_Type ()) in
      { uj_val = e_new_evar isevars env ~src:(loc,k) ty; uj_type = ty }

  | RRec (loc,fixkind,names,bl,lar,vdef) ->
      let rec type_bl env ctxt = function
          [] -> ctxt
        | (na,None,ty)::bl ->
            let ty' = pretype_type empty_valcon env isevars lvar ty in
            let dcl = (na,None,ty'.utj_val) in
            type_bl (push_rel dcl env) (add_rel_decl dcl ctxt) bl
        | (na,Some bd,ty)::bl ->
            let ty' = pretype_type empty_valcon env isevars lvar ty in
            let bd' = pretype (mk_tycon ty'.utj_val) env isevars lvar ty in
            let dcl = (na,Some bd'.uj_val,ty'.utj_val) in
            type_bl (push_rel dcl env) (add_rel_decl dcl ctxt) bl in
      let ctxtv = Array.map (type_bl env empty_rel_context) bl in
      let larj =
        array_map2
          (fun e ar ->
            pretype_type empty_valcon (push_rel_context e env) isevars lvar ar)
          ctxtv lar in
      let lara = Array.map (fun a -> a.utj_val) larj in
      let ftys = array_map2 (fun e a -> it_mkProd_or_LetIn a e) ctxtv lara in
      let nbfix = Array.length lar in
      let names = Array.map (fun id -> Name id) names in
      (* Note: bodies are not used by push_rec_types, so [||] is safe *)
      let newenv = push_rec_types (names,ftys,[||]) env in
      let vdefj =
	array_map2_i 
	  (fun i ctxt def ->
            (* we lift nbfix times the type in tycon, because of
	     * the nbfix variables pushed to newenv *)
            let (ctxt,ty) =
              decompose_prod_n_assum (rel_context_length ctxt)
                (lift nbfix ftys.(i)) in
            let nenv = push_rel_context ctxt newenv in
            let j = pretype (mk_tycon ty) nenv isevars lvar def in
            { uj_val = it_mkLambda_or_LetIn j.uj_val ctxt;
              uj_type = it_mkProd_or_LetIn j.uj_type ctxt })
          ctxtv vdef in
      evar_type_fixpoint loc env isevars names ftys vdefj;
      let fixj =
	match fixkind with
	  | RFix (vn,i) ->
	      let fix = ((Array.map fst vn, i),(names,ftys,Array.map j_val vdefj)) in
	      (try check_fix env fix with e -> Stdpp.raise_with_loc loc e);
	      make_judge (mkFix fix) ftys.(i)
	  | RCoFix i -> 
	      let cofix = (i,(names,ftys,Array.map j_val vdefj)) in
	      (try check_cofix env cofix with e -> Stdpp.raise_with_loc loc e);
	      make_judge (mkCoFix cofix) ftys.(i) in
      inh_conv_coerce_to_tycon loc env isevars fixj tycon

  | RSort (loc,s) ->
      inh_conv_coerce_to_tycon loc env isevars (pretype_sort s) tycon

  | RApp (loc,f,args) -> 
      let fj = pretype empty_tycon env isevars lvar f in
      let floc = loc_of_rawconstr f in
      let rec apply_rec env n resj = function
	| [] -> resj
	| c::rest ->
	    let argloc = loc_of_rawconstr c in
	    let resj = evd_comb1 (inh_app_fun env) isevars resj in
            let resty =
              whd_betadeltaiota env (evars_of !isevars) resj.uj_type in
	      match kind_of_term resty with
	      | Prod (na,c1,c2) ->
		  let hj = pretype (mk_tycon c1) env isevars lvar c in
		  let newresj =
      		    { uj_val = applist (j_val resj, [j_val hj]);
		      uj_type = subst1 hj.uj_val c2 } in
		  apply_rec env (n+1) newresj rest

	      | _ ->
		  let hj = pretype empty_tycon env isevars lvar c in
		  error_cant_apply_not_functional_loc 
		    (join_loc floc argloc) env (evars_of !isevars)
	      	    resj [hj]
      in let resj = apply_rec env 1 fj args in
      inh_conv_coerce_to_tycon loc env isevars resj tycon

  | RLambda(loc,name,c1,c2)      ->
      let (name',dom,rng) = evd_comb1 (split_tycon loc env) isevars tycon in
      let dom_valcon = valcon_of_tycon dom in
      let j = pretype_type dom_valcon env isevars lvar c1 in
      let var = (name,None,j.utj_val) in
      let j' = pretype rng (push_rel var env) isevars lvar c2 in 
      judge_of_abstraction env name j j'

  | RProd(loc,name,c1,c2)        ->
      let j = pretype_type empty_valcon env isevars lvar c1 in
      let var = (name,j.utj_val) in
      let env' = push_rel_assum var env in
      let j' = pretype_type empty_valcon env' isevars lvar c2 in
      let resj =
	try judge_of_product env name j j'
	with TypeError _ as e -> Stdpp.raise_with_loc loc e in
      inh_conv_coerce_to_tycon loc env isevars resj tycon
	
  | RLetIn(loc,name,c1,c2)      ->
      let j = pretype empty_tycon env isevars lvar c1 in
      let t = refresh_universes j.uj_type in
      let var = (name,Some j.uj_val,t) in
        let tycon = option_app (lift 1) tycon in
      let j' = pretype tycon (push_rel var env) isevars lvar c2 in
      { uj_val = mkLetIn (name, j.uj_val, t, j'.uj_val) ;
	uj_type = subst1 j.uj_val j'.uj_type }

  | RLetTuple (loc,nal,(na,po),c,d) ->
      let cj = pretype empty_tycon env isevars lvar c in
      let (IndType (indf,realargs)) = 
	try find_rectype env (evars_of !isevars) cj.uj_type
	with Not_found ->
	  let cloc = loc_of_rawconstr c in
	  error_case_not_inductive_loc cloc env (evars_of !isevars) cj 
      in
      let cstrs = get_constructors env indf in
      if Array.length cstrs <> 1 then
        user_err_loc (loc,"",str "Destructing let is only for inductive types with one constructor");
      let cs = cstrs.(0) in
      if List.length nal <> cs.cs_nargs then
        user_err_loc (loc,"", str "Destructing let on this type expects " ++ int cs.cs_nargs ++ str " variables");
      let fsign = List.map2 (fun na (_,c,t) -> (na,c,t))
        (List.rev nal) cs.cs_args in
      let env_f = push_rels fsign env in
      (* Make dependencies from arity signature impossible *)
      let arsgn,_ = get_arity env indf in
      let arsgn = List.map (fun (_,b,t) -> (Anonymous,b,t)) arsgn in
      let psign = (na,None,build_dependent_inductive env indf)::arsgn in
      let nar = List.length arsgn in
      (match po with
	 | Some p ->
             let env_p = push_rels psign env in
             let pj = pretype_type empty_valcon env_p isevars lvar p in
             let ccl = nf_evar (evars_of !isevars) pj.utj_val in
	     let psign = make_arity_signature env true indf in (* with names *)
	     let p = it_mkLambda_or_LetIn ccl psign in
             let inst = 
	       (Array.to_list cs.cs_concl_realargs)
	       @[build_dependent_constructor cs] in
	     let lp = lift cs.cs_nargs p in
             let fty = hnf_lam_applist env (evars_of !isevars) lp inst in
	     let fj = pretype (mk_tycon fty) env_f isevars lvar d in
	     let f = it_mkLambda_or_LetIn fj.uj_val fsign in
	     let v =
	       let mis,_ = dest_ind_family indf in
	       let ci = make_default_case_info env LetStyle mis in
	       mkCase (ci, p, cj.uj_val,[|f|]) in 
	     { uj_val = v; uj_type = substl (realargs@[cj.uj_val]) ccl }

	 | None -> 
             let tycon = option_app (lift cs.cs_nargs) tycon in
	     let fj = pretype tycon env_f isevars lvar d in
	     let f = it_mkLambda_or_LetIn fj.uj_val fsign in
	     let ccl = nf_evar (evars_of !isevars) fj.uj_type in
             let ccl =
               if noccur_between 1 cs.cs_nargs ccl then
                 lift (- cs.cs_nargs) ccl 
               else
                 error_cant_find_case_type_loc loc env (evars_of !isevars) 
                   cj.uj_val in
             let p = it_mkLambda_or_LetIn (lift (nar+1) ccl) psign in
	     let v =
	       let mis,_ = dest_ind_family indf in
	       let ci = make_default_case_info env LetStyle mis in
	       mkCase (ci, p, cj.uj_val,[|f|] ) 
	     in
	     { uj_val = v; uj_type = ccl })

  | RIf (loc,c,(na,po),b1,b2) ->
      let cj = pretype empty_tycon env isevars lvar c in
      let (IndType (indf,realargs)) = 
	try find_rectype env (evars_of !isevars) cj.uj_type
	with Not_found ->
	  let cloc = loc_of_rawconstr c in
	  error_case_not_inductive_loc cloc env (evars_of !isevars) cj in
      let cstrs = get_constructors env indf in 
      if Array.length cstrs <> 2 then
        user_err_loc (loc,"",
	  str "If is only for inductive types with two constructors");

      (* Make dependencies from arity signature possible ! *)
      let arsgn,_ = get_arity env indf in
      let arsgn = List.map (fun (n,b,t) -> 
			      debug 2 (str "If case arg: " ++ Nameops.pr_name n);
			      (n,b,t)) arsgn in
      let nar = List.length arsgn in
      let psign = (na,None,build_dependent_inductive env indf)::arsgn in
      let pred,p = match po with
	| Some p ->
	    let env_p = push_rels psign env in
            let pj = pretype_type empty_valcon env_p isevars lvar p in
            let ccl = nf_evar (evars_of !isevars) pj.utj_val in
	    let pred = it_mkLambda_or_LetIn ccl psign in
	    pred, lift (- nar) (beta_applist (pred,[cj.uj_val]))
	| None -> 
	    let p = match tycon with
	    | Some ty -> ty
	    | None ->
                e_new_evar isevars env ~src:(loc,InternalHole) (new_Type ())
	    in
	    it_mkLambda_or_LetIn (lift (nar+1) p) psign, p in
      let f cs b =
	let n = rel_context_length cs.cs_args in
	let pi = liftn n 2 pred in
	let pi = beta_applist (pi, [build_dependent_constructor cs]) in
	let csgn = 
	  List.map (fun (n,b,t) ->
		      match n with 
			  Name _ -> (n, b, t)
			| Anonymous -> (Name (id_of_string "H"), b, t))
	    cs.cs_args 
	in
	let env_c = push_rels csgn env in 
	let bj = pretype (Some pi) env_c isevars lvar b in
	it_mkLambda_or_LetIn bj.uj_val cs.cs_args in
      let b1 = f cstrs.(0) b1 in
      let b2 = f cstrs.(1) b2 in
      let pred = nf_evar (evars_of !isevars) pred in
      let p = nf_evar (evars_of !isevars) p in
      let v =
	let mis,_ = dest_ind_family indf in
	let ci = make_default_case_info env IfStyle mis in
	mkCase (ci, pred, cj.uj_val, [|b1;b2|])
      in
      { uj_val = v; uj_type = p }

  | RCases (loc,po,tml,eqns) ->
      Cases.compile_cases loc
	((fun vtyc env -> pretype vtyc env isevars lvar),isevars)
	tycon env (* loc *) (po,tml,eqns)
    
  | RCast(loc,c,k,t) ->
      let tj = pretype_type empty_tycon env isevars lvar t in
      let cj = pretype (mk_tycon tj.utj_val) env isevars lvar c in
      (* User Casts are for helping pretyping, experimentally not to be kept*)
      (* ... except for Correctness *)
      let v = mkCast (cj.uj_val, k, tj.utj_val) in
      let cj = { uj_val = v; uj_type = tj.utj_val } in
      inh_conv_coerce_to_tycon loc env isevars cj tycon

  | RDynamic (loc,d) ->
    if (tag d) = "constr" then
      let c = Pretyping.constr_out d in
      let j = (Retyping.get_judgment_of env (evars_of !isevars) c) in
      j
      (*inh_conv_coerce_to_tycon loc env isevars j tycon*)
    else
      user_err_loc (loc,"pretype",(str "Not a constr tagged Dynamic"))

(* [pretype_type valcon env isevars lvar c] coerces [c] into a type *)
and pretype_type valcon env isevars lvar = function
  | RHole loc ->
      (match valcon with
	 | Some v ->
             let s =
               let sigma = evars_of !isevars in
               let t = Retyping.get_type_of env sigma v in
               match kind_of_term (whd_betadeltaiota env sigma t) with
                 | Sort s -> s
                 | Evar v when is_Type (existential_type sigma v) -> 
                     evd_comb1 (define_evar_as_sort) isevars v
                 | _ -> anomaly "Found a type constraint which is not a type"
             in
	     { utj_val = v;
	       utj_type = s }
	 | None ->
	     let s = new_Type_sort () in
	     { utj_val = e_new_evar isevars env ~src:loc (mkSort s);
	       utj_type = s})
  | c ->
      let j = pretype empty_tycon env isevars lvar c in
      let loc = loc_of_rawconstr c in
      let tj = evd_comb1 (inh_coerce_to_sort loc env) isevars j in
      match valcon with
	| None -> tj
	| Some v ->
	    if e_cumul env isevars v tj.utj_val then tj
	    else
	      (debug 2 (str "here we are");
	       error_unexpected_type_loc
                 (loc_of_rawconstr c) env (evars_of !isevars) tj.utj_val v)



let merge_evms x y = 
  Evd.fold (fun ev evi evm -> Evd.add evm ev evi) x y

let interp env isevars c tycon = 
  let j = pretype tycon env isevars ([],[]) c in
    j.uj_val, j.uj_type

let find_with_index x l =
  let rec aux i = function
      (y, _, _) as t :: tl -> if x = y then i, t else aux (succ i) tl
    | [] -> raise Not_found
  in aux 0 l

let list_split_at index l = 
  let rec aux i acc = function
      hd :: tl when i = index -> (List.rev acc), tl
    | hd :: tl -> aux (succ i) (hd :: acc) tl
    | [] -> failwith "list_split_at: Invalid argument"
  in aux 0 [] l

open Vernacexpr

let coqintern evd env : Topconstr.constr_expr -> Rawterm.rawconstr = Constrintern.intern_constr (evars_of evd) env
let coqinterp evd env : Topconstr.constr_expr -> Term.constr = Constrintern.interp_constr (evars_of evd) env

let env_with_binders env isevars l =
  let rec aux ((env, rels) as acc) = function
      Topconstr.LocalRawDef ((loc, name), def) :: tl -> 
	let rawdef = coqintern !isevars env def in
	let coqdef, deftyp = interp env isevars rawdef empty_tycon in
	let reldecl = (name, Some coqdef, deftyp) in
	  aux  (push_rel reldecl env, reldecl :: rels) tl
    | Topconstr.LocalRawAssum (bl, typ) :: tl ->
	let rawtyp = coqintern !isevars env typ in
	let coqtyp, typtyp = interp env isevars rawtyp empty_tycon in
	let acc = 
	  List.fold_left (fun (env, rels) (loc, name) -> 
			    let reldecl = (name, None, coqtyp) in
			      (push_rel reldecl env, 
			       reldecl :: rels))
	    (env, rels) bl
	in aux acc tl
    | [] -> acc
  in aux (env, []) l

let subtac_process env isevars id l c tycon =
  let evars () = evars_of !isevars in
  let _ = trace (str "Creating env with binders") in
  let env_binders, binders_rel = env_with_binders env isevars l in
  let _ = trace (str "New env created:" ++ my_print_context env_binders) in
  let tycon = 
    match tycon with
	None -> empty_tycon
      | Some t -> 
	  let t = coqintern !isevars env_binders t in
	  let _ = trace (str "Internalized specification: " ++ my_print_rawconstr env_binders t) in
	  let coqt, ttyp = interp env_binders isevars t empty_tycon in
	  let _ = trace (str "Interpreted type: " ++ my_print_constr env_binders coqt) in
	    mk_tycon coqt
  in    
  let c = coqintern !isevars env_binders c in
  let _ = trace (str "Internalized term: " ++ my_print_rawconstr env c) in
  let coqc, ctyp = interp env_binders isevars c tycon in
  let _ = trace (str "Interpreted term: " ++ my_print_constr env_binders coqc ++ spc () ++
		 str "Coq type: " ++ my_print_constr env_binders ctyp)
  in
  let _ = trace (str "Original evar map: " ++ Evd.pr_evar_map (evars ())) in
    
  let fullcoqc = it_mkLambda_or_LetIn coqc binders_rel 
  and fullctyp = it_mkProd_or_LetIn ctyp binders_rel
  in
  let fullcoqc = Evarutil.nf_evar (evars_of !isevars) fullcoqc in
  let fullctyp = Evarutil.nf_evar (evars_of !isevars) fullctyp in

  let _ = trace (str "After evar normalization: " ++ spc () ++
		 str "Coq term: " ++ my_print_constr env fullcoqc ++ spc ()
		 ++ str "Coq type: " ++ my_print_constr env fullctyp) 
  in
  let evm = non_instanciated_map env isevars in
  let _ = trace (str "Non instanciated evars map: " ++ Evd.pr_evar_map evm) in
    evm, fullcoqc, fullctyp

let pretype_gen isevars env lvar kind c =
  let c' = match kind with
  | OfType exptyp ->
    let tycon = match exptyp with None -> empty_tycon | Some t -> mk_tycon t in
    (pretype tycon env isevars lvar c).uj_val
  | IsType ->
    (pretype_type empty_valcon env isevars lvar c).utj_val in
  nf_evar (evars_of !isevars) c'

(* [check_evars] fails if some unresolved evar remains *)
(* it assumes that the defined existentials have already been substituted
   (should be done in unsafe_infer and unsafe_infer_type) *)

let check_evars env initial_sigma isevars c =
  let sigma = evars_of !isevars in
  let rec proc_rec c =
    match kind_of_term c with
      | Evar (ev,args) ->
          assert (Evd.in_dom sigma ev);
	  if not (Evd.in_dom initial_sigma ev) then
            let (loc,k) = evar_source ev !isevars in
	    let _ = trace (str "Evar " ++ int ev ++ str " not solved, applied to args : " ++
			   Scoq.print_args env args ++ str " in evar map: " ++
			   Evd.pr_evar_map sigma) 
	    in
	    error_unsolvable_implicit loc env sigma k
      | _ -> iter_constr proc_rec c
  in
  proc_rec c(*;
  let (_,pbs) = get_conv_pbs !isevars (fun _ -> true) in
  if pbs <> [] then begin
    pperrnl
      (str"TYPING OF "++Termops.print_constr_env env c++fnl()++
      prlist_with_sep fnl
        (fun  (pb,c1,c2) ->
          Termops.print_constr c1 ++
          (if pb=Reduction.CUMUL then str " <="++ spc()
           else str" =="++spc()) ++
          Termops.print_constr c2)
        pbs ++ fnl())
  end*)

(* TODO: comment faire remonter l'information si le typage a resolu des
       variables du sigma original. il faudrait que la fonction de typage
       retourne aussi le nouveau sigma...
*)

let understand_judgment isevars env c =
  let j = pretype empty_tycon env isevars ([],[]) c in
  let j = j_nf_evar (evars_of !isevars) j in
  check_evars env (Evd.evars_of !isevars) isevars (mkCast(j.uj_val,DEFAULTcast, j.uj_type));
  j

(* Raw calls to the unsafe inference machine: boolean says if we must
   fail on unresolved evars; the unsafe_judgment list allows us to
   extend env with some bindings *)

let ise_pretype_gen fail_evar isevars env lvar kind c : Evd.open_constr =
  let c = pretype_gen isevars env lvar kind c in
  if fail_evar then check_evars env (Evd.evars_of !isevars) isevars c;
    let c = nf_evar (evars_of !isevars) c in
    let evm = non_instanciated_map env isevars in
      (evm, c)

(** Entry points of the high-level type synthesis algorithm *)

let understand_gen kind isevars env c =
  ise_pretype_gen false isevars env ([],[]) kind c

let understand isevars env ?expected_type:exptyp c =
  ise_pretype_gen false isevars env ([],[]) (OfType exptyp) c

let understand_type isevars env c =
  ise_pretype_gen false isevars env ([],[]) IsType c

let understand_ltac isevars env lvar kind c =
  ise_pretype_gen false isevars env lvar kind c

let understand_tcc isevars env ?expected_type:exptyp c =
  ise_pretype_gen false isevars env ([],[]) (OfType exptyp) c


    
