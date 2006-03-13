(************************************************************************)
(*  v      *   The Coq Proof Assistant  /  The Coq Development Team     *)
(* <O___,, * CNRS-Ecole Polytechnique-INRIA Futurs-Universite Paris Sud *)
(*   \VV/  **************************************************************)
(*    //   *      This file is distributed under the terms of the       *)
(*         *       GNU Lesser General Public License Version 2.1        *)
(************************************************************************)

(* $Id$ *)

open Pp
open Util
open Univ
open Names
open Term
open Declarations
open Inductive
open Inductiveops
open Environ
open Sign
open Rawterm
open Nameops
open Termops
open Libnames
open Nametab
open Evd
open Mod_subst

let dl = dummy_loc

(****************************************************************************)
(* Tools for printing of Cases                                              *)

let encode_inductive qid =
  let indsp = global_inductive qid in
  let constr_lengths = mis_constr_nargs indsp in
  (indsp,constr_lengths)

(* Parameterization of the translation from constr to ast      *)

(* Tables for Cases printing under a "if" form, a "let" form,  *)

let has_two_constructors lc =
  Array.length lc = 2 (* & lc.(0) = 0 & lc.(1) = 0 *)

let isomorphic_to_tuple lc = (Array.length lc = 1)

let encode_bool r =
  let (_,lc as x) = encode_inductive r in
  if not (has_two_constructors lc) then
    user_err_loc (loc_of_reference r,"encode_if",
      str "This type has not exactly two constructors");
  x

let encode_tuple r =
  let (_,lc as x) = encode_inductive r in
  if not (isomorphic_to_tuple lc) then
    user_err_loc (loc_of_reference r,"encode_tuple",
      str "This type cannot be seen as a tuple type");
  x

module PrintingCasesMake =
  functor (Test : sig 
     val encode : reference -> inductive * int array
     val member_message : std_ppcmds -> bool -> std_ppcmds
     val field : string
     val title : string
  end) ->
  struct
    type t = inductive * int array
    let encode = Test.encode
    let subst subst ((kn,i), ints as obj) =
      let kn' = subst_kn subst kn in
	if kn' == kn then obj else
	  (kn',i), ints
    let printer (ind,_) = pr_global_env Idset.empty (IndRef ind)
    let key = Goptions.SecondaryTable ("Printing",Test.field)
    let title = Test.title
    let member_message x = Test.member_message (printer x)
    let synchronous = true
  end

module PrintingCasesIf =
  PrintingCasesMake (struct 
    let encode = encode_bool
    let field = "If"
    let title = "Types leading to pretty-printing of Cases using a `if' form: "
    let member_message s b =
      str "Cases on elements of " ++ s ++ 
      str
	(if b then " are printed using a `if' form"
         else " are not printed using a `if' form")
  end)

module PrintingCasesLet =
  PrintingCasesMake (struct 
    let encode = encode_tuple
    let field = "Let"
    let title = 
      "Types leading to a pretty-printing of Cases using a `let' form:"
    let member_message s b =
      str "Cases on elements of " ++ s ++
      str
	(if b then " are printed using a `let' form"
         else " are not printed using a `let' form")
  end)

module PrintingIf  = Goptions.MakeRefTable(PrintingCasesIf)
module PrintingLet = Goptions.MakeRefTable(PrintingCasesLet)

let force_let ci =
  let indsp = ci.ci_ind in
  let lc = mis_constr_nargs indsp in PrintingLet.active (indsp,lc)
let force_if ci =
  let indsp = ci.ci_ind in
  let lc = mis_constr_nargs indsp in PrintingIf.active (indsp,lc)

(* Options for printing or not wildcard and synthetisable types *)

open Goptions

let wildcard_value = ref true
let force_wildcard () = !wildcard_value

let _ = declare_bool_option 
	  { optsync  = true;
	    optname  = "forced wildcard";
	    optkey   = SecondaryTable ("Printing","Wildcard");
	    optread  = force_wildcard;
	    optwrite = (:=) wildcard_value }

let synth_type_value = ref true
let synthetize_type () = !synth_type_value

let _ = declare_bool_option 
	  { optsync  = true;
	    optname  = "pattern matching return type synthesizability";
	    optkey   = SecondaryTable ("Printing","Synth");
	    optread  = synthetize_type;
	    optwrite = (:=) synth_type_value }

let reverse_matching_value = ref true
let reverse_matching () = !reverse_matching_value

let _ = declare_bool_option 
	  { optsync  = true;
	    optname  = "pattern-matching reversibility";
	    optkey   = SecondaryTable ("Printing","Matching");
	    optread  = reverse_matching;
	    optwrite = (:=) reverse_matching_value }

(* Auxiliary function for MutCase printing *)
(* [computable] tries to tell if the predicate typing the result is inferable*)

let computable p k =
    (* We first remove as many lambda as the arity, then we look
       if it remains a lambda for a dependent elimination. This function
       works for normal eta-expanded term. For non eta-expanded or
       non-normal terms, it may affirm the pred is synthetisable
       because of an undetected ultimate dependent variable in the second
       clause, or else, it may affirms the pred non synthetisable
       because of a non normal term in the fourth clause.
       A solution could be to store, in the MutCase, the eta-expanded
       normal form of pred to decide if it depends on its variables

       Lorsque le pr�dicat est d�pendant de mani�re certaine, on
       ne d�clare pas le pr�dicat synth�tisable (m�me si la
       variable d�pendante ne l'est pas effectivement) parce que
       sinon on perd la r�ciprocit� de la synth�se (qui, lui,
       engendrera un pr�dicat non d�pendant) *)

  (nb_lam p = k+1)
  &&
  let _,ccl = decompose_lam p in 
  noccur_between 1 (k+1) ccl


let lookup_name_as_renamed env t s =
  let rec lookup avoid env_names n c = match kind_of_term c with
    | Prod (name,_,c') ->
	(match concrete_name true avoid env_names name c' with
           | (Name id,avoid') -> 
	       if id=s then (Some n) 
	       else lookup avoid' (add_name (Name id) env_names) (n+1) c'
	   | (Anonymous,avoid')    -> lookup avoid' env_names (n+1) (pop c'))
    | LetIn (name,_,_,c') ->
	(match concrete_name true avoid env_names name c' with
           | (Name id,avoid') -> 
	       if id=s then (Some n) 
	       else lookup avoid' (add_name (Name id) env_names) (n+1) c'
	   | (Anonymous,avoid')    -> lookup avoid' env_names (n+1) (pop c'))
    | Cast (c,_,_) -> lookup avoid env_names n c
    | _ -> None
  in lookup (ids_of_named_context (named_context env)) empty_names_context 1 t

let lookup_index_as_renamed env t n =
  let rec lookup n d c = match kind_of_term c with
    | Prod (name,_,c') ->
	  (match concrete_name true [] empty_names_context name c' with
               (Name _,_) -> lookup n (d+1) c'
             | (Anonymous,_) -> if n=1 then Some d else lookup (n-1) (d+1) c')
    | LetIn (name,_,_,c') ->
	  (match concrete_name true [] empty_names_context name c' with
             | (Name _,_) -> lookup n (d+1) c'
             | (Anonymous,_) -> if n=1 then Some d else lookup (n-1) (d+1) c')
    | Cast (c,_,_) -> lookup n d c
    | _ -> None
  in lookup n 1 t

(**********************************************************************)
(* Fragile algorithm to reverse pattern-matching compilation          *)

let update_name na ((_,e),c) =
  match na with
  | Name _ when force_wildcard () & noccurn (list_index na e) c ->
      Anonymous
  | _ ->
      na

let rec decomp_branch n nal b (avoid,env as e) c =
  if n=0 then (List.rev nal,(e,c))
  else
    let na,c,f =
      match kind_of_term (strip_outer_cast c) with
	| Lambda (na,_,c) -> na,c,concrete_let_name
	| LetIn (na,_,_,c) -> na,c,concrete_name
	| _ -> 
	    Name (id_of_string "x"),(applist (lift 1 c, [mkRel 1])), 
	    concrete_name in
    let na',avoid' = f b avoid env na c in
    decomp_branch (n-1) (na'::nal) b (avoid',add_name na' env) c

let rec build_tree na isgoal e ci cl =
  let mkpat n rhs pl = PatCstr(dl,(ci.ci_ind,n+1),pl,update_name na rhs) in
  let cnl = ci.ci_cstr_nargs in
  List.flatten
    (list_tabulate (fun i -> contract_branch isgoal e (cnl.(i),mkpat i,cl.(i)))
       (Array.length cl))

and align_tree nal isgoal (e,c as rhs) = match nal with
  | [] -> [[],rhs]
  | na::nal ->
    match kind_of_term c with
    | Case (ci,_,c,cl) when c = mkRel (list_index na (snd e)) ->
	let clauses = build_tree na isgoal e ci cl in
	List.flatten
          (List.map (fun (pat,rhs) ->
	      let lines = align_tree nal isgoal rhs in
	      List.map (fun (hd,rest) -> pat::hd,rest) lines) 
	    clauses)
    | _ ->
	let pat = PatVar(dl,update_name na rhs) in
	let mat = align_tree nal isgoal rhs in
	List.map (fun (hd,rest) -> pat::hd,rest) mat

and contract_branch isgoal e (cn,mkpat,b) =
  let nal,rhs = decomp_branch cn [] isgoal e b in
  let mat = align_tree nal isgoal rhs in
  List.map (fun (hd,rhs) -> (mkpat rhs hd,rhs)) mat

(**********************************************************************)
(* Transform internal representation of pattern-matching into list of *)
(* clauses                                                            *)

let is_nondep_branch c n =
  try
    let _,ccl = decompose_lam_n_assum n c in
    noccur_between 1 n ccl
  with _ -> (* Not eta-expanded or not reduced *)
    false

let extract_nondep_branches test c b n =
  let rec strip n r = if n=0 then r else
    match r with
      | RLambda (_,_,_,t) -> strip (n-1) t
      | RLetIn (_,_,_,t) -> strip (n-1) t
      | _ -> assert false in
  if test c n then Some (strip n b) else None

let detype_case computable detype detype_eqns testdep avoid data p c bl =
  let (indsp,st,nparams,consnargsl,k) = data in
  let synth_type = synthetize_type () in
  let tomatch = detype c in
  let alias, aliastyp, pred= 
    if (not !Options.raw_print) & synth_type & computable & Array.length bl<>0 
    then 
      Anonymous, None, None
    else
      match option_app detype p with
        | None -> Anonymous, None, None
        | Some p ->
            let decompose_lam k c =
              let rec lamdec_rec l avoid k c =
                if k = 0 then List.rev l,c else match c with
                  | RLambda (_,x,t,c) -> 
                      lamdec_rec (x::l) (name_cons x avoid) (k-1) c
                  | c -> 
                      let x = next_ident_away (id_of_string "x") avoid in
                      lamdec_rec ((Name x)::l) (x::avoid) (k-1)
                        (let a = RVar (dl,x) in
                          match c with
                          | RApp (loc,p,l) -> RApp (loc,p,l@[a])
                          | _ -> (RApp (dl,c,[a])))
              in 
              lamdec_rec [] [] k c in
            let nl,typ = decompose_lam k p in
	    let n,typ = match typ with 
              | RLambda (_,x,t,c) -> x, c
	      | _ -> Anonymous, typ in
	    let aliastyp =
	      if List.for_all ((=) Anonymous) nl then None
	      else 
		let pars = list_tabulate (fun _ -> Anonymous) nparams in
		Some (dl,indsp,pars@nl) in
            n, aliastyp, Some typ
  in
  let constructs = Array.init (Array.length bl) (fun i -> (indsp,i+1)) in
  let eqnl = detype_eqns constructs consnargsl bl in
  let tag =
    try 
      if !Options.raw_print then
        RegularStyle
      else if PrintingLet.active (indsp,consnargsl) then
	LetStyle
      else if PrintingIf.active (indsp,consnargsl) then 
	IfStyle
      else 
	st
    with Not_found -> st
  in
  match tag with
  | LetStyle when aliastyp = None -> 
      let bl' = Array.map detype bl in
      let rec decomp_lam_force n avoid l p =
	if n = 0 then (List.rev l,p) else
          match p with
            | RLambda (_,na,_,c) -> 
		decomp_lam_force (n-1) (name_cons na avoid) (na::l) c
            | RLetIn (_,na,_,c) -> 
		decomp_lam_force (n-1) (name_cons na avoid) (na::l) c
            | _ ->
		let x = Nameops.next_ident_away (id_of_string "x") avoid in
		decomp_lam_force (n-1) (x::avoid) (Name x :: l) 
                  (* eta-expansion *)
                  (let a = RVar (dl,x) in
                  match p with
                    | RApp (loc,p,l) -> RApp (loc,p,l@[a])
                    | _ -> (RApp (dl,p,[a]))) in
      let (nal,d) = decomp_lam_force consnargsl.(0) avoid [] bl'.(0) in
      RLetTuple (dl,nal,(alias,pred),tomatch,d)
  | IfStyle when aliastyp = None ->
      let bl' = Array.map detype bl in
      let nondepbrs =
	array_map3 (extract_nondep_branches testdep) bl bl' consnargsl in
      if array_for_all ((<>) None) nondepbrs then
	RIf (dl,tomatch,(alias,pred),
             out_some nondepbrs.(0),out_some nondepbrs.(1))
      else
	RCases (dl,pred,[tomatch,(alias,aliastyp)],eqnl)
  | _ ->
      RCases (dl,pred,[tomatch,(alias,aliastyp)],eqnl)

(**********************************************************************)
(* Main detyping function                                             *)

let rec detype isgoal avoid env t =
  match kind_of_term (collapse_appl t) with
    | Rel n ->
      (try match lookup_name_of_rel n env with
	 | Name id   -> RVar (dl, id)
	 | Anonymous -> anomaly "detype: index to an anonymous variable"
       with Not_found ->
	 let s = "_UNBOUND_REL_"^(string_of_int n)
	 in RVar (dl, id_of_string s))
    | Meta n ->
	(* Meta in constr are not user-parsable and are mapped to Evar *)
	REvar (dl, n, None)
    | Var id ->
	(try
	  let _ = Global.lookup_named id in RRef (dl, VarRef id)
	 with _ ->
	  RVar (dl, id))
    | Sort (Prop c) -> RSort (dl,RProp c)
    | Sort (Type u) -> RSort (dl,RType (Some u))
    | Cast (c1,k,c2) ->
	RCast(dl,detype isgoal avoid env c1, k,
              detype isgoal avoid env c2)
    | Prod (na,ty,c) -> detype_binder isgoal BProd avoid env na ty c
    | Lambda (na,ty,c) -> detype_binder isgoal BLambda avoid env na ty c
    | LetIn (na,b,_,c) -> detype_binder isgoal BLetIn avoid env na b c
    | App (f,args) ->
	RApp (dl,detype isgoal avoid env f,
              array_map_to_list (detype isgoal avoid env) args)
    | Const sp -> RRef (dl, ConstRef sp)
    | Evar (ev,cl) ->
        REvar (dl, ev, 
               Some (List.map (detype isgoal avoid env) (Array.to_list cl)))
    | Ind ind_sp ->
	RRef (dl, IndRef ind_sp)
    | Construct cstr_sp ->
	RRef (dl, ConstructRef cstr_sp)
    | Case (ci,p,c,bl) ->
	let comp = computable p (ci.ci_pp_info.ind_nargs) in
	detype_case comp (detype isgoal avoid env)
	  (detype_eqns isgoal avoid env ci comp)
	  is_nondep_branch avoid 
	  (ci.ci_ind,ci.ci_pp_info.style,ci.ci_npar,
	   ci.ci_cstr_nargs,ci.ci_pp_info.ind_nargs)
	  (Some p) c bl
    | Fix (nvn,recdef) -> detype_fix isgoal avoid env nvn recdef
    | CoFix (n,recdef) -> detype_cofix isgoal avoid env n recdef

and detype_fix isgoal avoid env (vn,_ as nvn) (names,tys,bodies) =
  let def_avoid, def_env, lfi =
    Array.fold_left
      (fun (avoid, env, l) na ->
	 let id = next_name_away na avoid in 
	 (id::avoid, add_name (Name id) env, id::l))
      (avoid, env, []) names in
  let n = Array.length tys in
  let v = array_map3
    (fun c t i -> share_names isgoal (i+1) [] def_avoid def_env c (lift n t))
    bodies tys vn in
  RRec(dl,RFix (Array.map (fun i -> i, RStructRec) (fst nvn), snd nvn),Array.of_list (List.rev lfi),
       Array.map (fun (bl,_,_) -> bl) v,
       Array.map (fun (_,_,ty) -> ty) v,
       Array.map (fun (_,bd,_) -> bd) v)

and detype_cofix isgoal avoid env n (names,tys,bodies) =
  let def_avoid, def_env, lfi =
    Array.fold_left
      (fun (avoid, env, l) na ->
	 let id = next_name_away na avoid in 
	 (id::avoid, add_name (Name id) env, id::l))
      (avoid, env, []) names in
  let ntys = Array.length tys in
  let v = array_map2
    (fun c t -> share_names isgoal 0 [] def_avoid def_env c (lift ntys t))
    bodies tys in
  RRec(dl,RCoFix n,Array.of_list (List.rev lfi),
       Array.map (fun (bl,_,_) -> bl) v,
       Array.map (fun (_,_,ty) -> ty) v,
       Array.map (fun (_,bd,_) -> bd) v)

and share_names isgoal n l avoid env c t =
  match kind_of_term c, kind_of_term t with
    (* factorize even when not necessary to have better presentation *)
    | Lambda (na,t,c), Prod (na',t',c') ->
        let na = match (na,na') with
            Name _, _ -> na
          | _, Name _ -> na'
          | _ -> na in 
        let t = detype isgoal avoid env t in
	let id = next_name_away na avoid in 
        let avoid = id::avoid and env = add_name (Name id) env in
        share_names isgoal (n-1) ((Name id,None,t)::l) avoid env c c'
    (* May occur for fix built interactively *)
    | LetIn (na,b,t',c), _ when n > 0 ->
        let t' = detype isgoal avoid env t' in
        let b = detype isgoal avoid env b in
	let id = next_name_away na avoid in 
        let avoid = id::avoid and env = add_name (Name id) env in
        share_names isgoal n ((Name id,Some b,t')::l) avoid env c t
    (* Only if built with the f/n notation or w/o let-expansion in types *)
    | _, LetIn (_,b,_,t) when n > 0 ->
	share_names isgoal n l avoid env c (subst1 b t)
    (* If it is an open proof: we cheat and eta-expand *)
    | _, Prod (na',t',c') when n > 0 ->
        let t' = detype isgoal avoid env t' in
	let id = next_name_away na' avoid in 
        let avoid = id::avoid and env = add_name (Name id) env in
        let appc = mkApp (lift 1 c,[|mkRel 1|]) in
        share_names isgoal (n-1) ((Name id,None,t')::l) avoid env appc c'
    (* If built with the f/n notation: we renounce to share names *)
    | _ ->
        if n>0 then warning "Detyping.detype: cannot factorize fix enough";
        let c = detype isgoal avoid env c in
        let t = detype isgoal avoid env t in
        (List.rev l,c,t)

and detype_eqns isgoal avoid env ci computable constructs consnargsl bl =
  try
    if !Options.raw_print or not (reverse_matching ()) then raise Exit;
    let mat = build_tree Anonymous isgoal (avoid,env) ci bl in
    List.map (fun (pat,((avoid,env),c)) -> (dl,[],[pat],detype isgoal avoid env c))
      mat
  with _ ->
    Array.to_list
      (array_map3 (detype_eqn isgoal avoid env) constructs consnargsl bl)

and detype_eqn isgoal avoid env constr construct_nargs branch =
  let make_pat x avoid env b ids =
    if force_wildcard () & noccurn 1 b then
      PatVar (dl,Anonymous),avoid,(add_name Anonymous env),ids
    else 
      let id = next_name_away_with_default "x" x avoid in
      PatVar (dl,Name id),id::avoid,(add_name (Name id) env),id::ids
  in
  let rec buildrec ids patlist avoid env n b =
    if n=0 then
      (dl, ids, 
       [PatCstr(dl, constr, List.rev patlist,Anonymous)],
       detype isgoal avoid env b)
    else
      match kind_of_term b with
	| Lambda (x,_,b) -> 
	    let pat,new_avoid,new_env,new_ids = make_pat x avoid env b ids in
            buildrec new_ids (pat::patlist) new_avoid new_env (n-1) b

	| LetIn (x,_,_,b) -> 
	    let pat,new_avoid,new_env,new_ids = make_pat x avoid env b ids in
            buildrec new_ids (pat::patlist) new_avoid new_env (n-1) b

	| Cast (c,_,_) ->    (* Oui, il y a parfois des cast *)
	    buildrec ids patlist avoid env n c

	| _ -> (* eta-expansion : n'arrivera plus lorsque tous les
                  termes seront construits � partir de la syntaxe Cases *)
            (* nommage de la nouvelle variable *)
	    let new_b = applist (lift 1 b, [mkRel 1]) in
            let pat,new_avoid,new_env,new_ids =
	      make_pat Anonymous avoid env new_b ids in
	    buildrec new_ids (pat::patlist) new_avoid new_env (n-1) new_b
	  
  in 
  buildrec [] [] avoid env construct_nargs branch

and detype_binder isgoal bk avoid env na ty c =
  let na',avoid' =
    if bk = BLetIn then
      concrete_let_name isgoal avoid env na c
    else
      concrete_name isgoal avoid env na c in
  let r =  detype isgoal avoid' (add_name na' env) c in
  match bk with
  | BProd -> RProd (dl, na',detype isgoal avoid env ty, r)
  | BLambda -> RLambda (dl, na',detype isgoal avoid env ty, r)
  | BLetIn -> RLetIn (dl, na',detype isgoal avoid env ty, r)

(**********************************************************************)
(* Module substitution: relies on detyping                            *)

let rec subst_cases_pattern subst pat = 
  match pat with
  | PatVar _ -> pat
  | PatCstr (loc,((kn,i),j),cpl,n) -> 
      let kn' = subst_kn subst kn 
      and cpl' = list_smartmap (subst_cases_pattern subst) cpl in
	if kn' == kn && cpl' == cpl then pat else
	  PatCstr (loc,((kn',i),j),cpl',n)

let rec subst_rawconstr subst raw = 
  match raw with
  | RRef (loc,ref) -> 
      let ref',t = subst_global subst ref in 
	if ref' == ref then raw else
         detype false [] [] t

  | RVar _ -> raw
  | REvar _ -> raw
  | RPatVar _ -> raw

  | RApp (loc,r,rl) -> 
      let r' = subst_rawconstr subst r 
      and rl' = list_smartmap (subst_rawconstr subst) rl in
	if r' == r && rl' == rl then raw else
	  RApp(loc,r',rl')

  | RLambda (loc,n,r1,r2) -> 
      let r1' = subst_rawconstr subst r1 and r2' = subst_rawconstr subst r2 in
	if r1' == r1 && r2' == r2 then raw else
	  RLambda (loc,n,r1',r2')

  | RProd (loc,n,r1,r2) -> 
      let r1' = subst_rawconstr subst r1 and r2' = subst_rawconstr subst r2 in
	if r1' == r1 && r2' == r2 then raw else
	  RProd (loc,n,r1',r2')

  | RLetIn (loc,n,r1,r2) -> 
      let r1' = subst_rawconstr subst r1 and r2' = subst_rawconstr subst r2 in
	if r1' == r1 && r2' == r2 then raw else
	  RLetIn (loc,n,r1',r2')

  | RCases (loc,rtno,rl,branches) -> 
      let rtno' = option_smartmap (subst_rawconstr subst) rtno
      and rl' = list_smartmap (fun (a,x as y) ->
        let a' = subst_rawconstr subst a in
        let (n,topt) = x in 
        let topt' = option_smartmap
          (fun (loc,(sp,i),x as t) ->
            let sp' = subst_kn subst sp in
            if sp == sp' then t else (loc,(sp',i),x)) topt in
        if a == a' && topt == topt' then y else (a',(n,topt'))) rl
      and branches' = list_smartmap 
			(fun (loc,idl,cpl,r as branch) ->
			   let cpl' =
			     list_smartmap (subst_cases_pattern subst) cpl
			   and r' = subst_rawconstr subst r in
			     if cpl' == cpl && r' == r then branch else
			       (loc,idl,cpl',r'))
			branches
      in
	if rtno' == rtno && rl' == rl && branches' == branches then raw else
	  RCases (loc,rtno',rl',branches')

  | RLetTuple (loc,nal,(na,po),b,c) ->
      let po' = option_smartmap (subst_rawconstr subst) po
      and b' = subst_rawconstr subst b 
      and c' = subst_rawconstr subst c in
	if po' == po && b' == b && c' == c then raw else
          RLetTuple (loc,nal,(na,po'),b',c')
      
  | RIf (loc,c,(na,po),b1,b2) ->
      let po' = option_smartmap (subst_rawconstr subst) po
      and b1' = subst_rawconstr subst b1 
      and b2' = subst_rawconstr subst b2 
      and c' = subst_rawconstr subst c in
	if c' == c & po' == po && b1' == b1 && b2' == b2 then raw else
          RIf (loc,c',(na,po'),b1',b2')

  | RRec (loc,fix,ida,bl,ra1,ra2) -> 
      let ra1' = array_smartmap (subst_rawconstr subst) ra1
      and ra2' = array_smartmap (subst_rawconstr subst) ra2 in
      let bl' = array_smartmap
        (list_smartmap (fun (na,obd,ty as dcl) ->
          let ty' = subst_rawconstr subst ty in
          let obd' = option_smartmap (subst_rawconstr subst) obd in
          if ty'==ty & obd'==obd then dcl else (na,obd',ty')))
        bl in
	if ra1' == ra1 && ra2' == ra2 && bl'==bl then raw else
	  RRec (loc,fix,ida,bl',ra1',ra2')

  | RSort _ -> raw

  | RHole (loc,ImplicitArg (ref,i)) ->
      let ref',_ = subst_global subst ref in 
	if ref' == ref then raw else
	  RHole (loc,InternalHole)
  | RHole (loc, (BinderType _ | QuestionMark | CasesType |
      InternalHole | TomatchTypeParameter _)) -> raw

  | RCast (loc,r1,k,r2) -> 
      let r1' = subst_rawconstr subst r1 and r2' = subst_rawconstr subst r2 in
	if r1' == r1 && r2' == r2 then raw else
	  RCast (loc,r1',k,r2')

  | RDynamic _ -> raw
