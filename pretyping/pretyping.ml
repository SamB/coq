
(* $Id$ *)

open Pp
open Util
open Names
open Generic
open Sign
open Evd
open Term
open Reduction
open Environ
open Type_errors
open Typeops
open Classops
open List
open Recordops 
open Evarutil
open Pretype_errors
open Rawterm
open Evarconv
open Coercion


(***********************************************************************)
(* This concerns Cases *)
open Inductive
open Instantiate

(* Pour le vieux "match" que Program utilise encore, vieille histoire ... *)

(* Awful special reduction function which skips abstraction on Xtra in
   order to be safe for Program ... *)

let stacklamxtra recfun = 
  let rec lamrec sigma p_0 p_1 = match p_0,p_1 with 
    | (stack, (DOP2(Lambda,DOP1(XTRA "COMMENT",_),DLAM(_,c)) as t)) ->
        recfun stack (substl sigma t)
    | ((h::t), (DOP2(Lambda,_,DLAM(_,c)))) -> lamrec (h::sigma) t c
    | (stack, t) -> recfun stack (substl sigma t)
  in 
  lamrec 

let rec whrec x stack =
  match x with   
    | DOP2(Lambda,DOP1(XTRA "COMMENT",c),DLAM(name,t)) ->
    	let t' = applist (whrec t (List.map (lift 1) stack)) in 
	DOP2(Lambda,DOP1(XTRA "COMMENT",c),DLAM(name,t')),[]
    | DOP2(Lambda,c1,DLAM(name,c2)) ->
    	(match stack with
	   | [] -> (DOP2(Lambda,c1,DLAM(name,whd_betaxtra c2)),[])
	   | a1::rest -> stacklamxtra (fun l x -> whrec x l) [a1] rest c2)
    | DOPN(AppL,cl) -> whrec (array_hd cl) (array_app_tl cl stack)
    | DOP2(Cast,c,_) ->  whrec c stack
    | x -> x,stack

and whd_betaxtra x = applist(whrec x [])

let lift_context n l = 
  let k = List.length l in 
  list_map_i (fun i (name,c) -> (name,liftn n (k-i) c)) 0 l
let prod_create env (a,b) = 
  mkProd (named_hd env a Anonymous) a b
let lambda_name env (n,a,b) = 
  mkLambda (named_hd env a n) a b
let lambda_create env (a,b) = 
  mkLambda (named_hd env a Anonymous) a b
let it_prod_name env = 
  List.fold_left (fun c (n,t) -> prod_name env (n,t,c)) 
let it_lambda_name env = 
  List.fold_left (fun c (n,t) -> lambda_name env (n,t,c))

let transform_rec loc env sigma cl (ct,pt) = 
  let (mI,largs as mind) = find_minductype env sigma ct in
  let p = cl.(0)
  and c = cl.(1)
  and lf = Array.sub cl 2 ((Array.length cl) - 2) in
  let mispec = lookup_mind_specif mI env in 
  let recargs = mis_recarg mispec in
  let expn = Array.length recargs in
  if Array.length lf <> expn then 
    error_number_branches_loc loc CCI env c ct expn;
  if is_recursive [mispec.mis_tyi] recargs then
    let (dep,_) = find_case_dep_nparams env sigma (c,p) mind pt in 
    let ntypes = mis_nconstr mispec 
    and tyi = mispec.mis_tyi 
    and nparams = mis_nparams mispec in
    let depFvec = Array.create ntypes (None : (bool * constr) option) in 
    let _ = Array.set depFvec mispec.mis_tyi (Some(dep,Rel 1)) in 
    let (pargs,realargs) = list_chop nparams largs in
    let vargs = Array.of_list pargs in
    let (_,typeconstrvec) = mis_type_mconstructs mispec in
    (* build now the fixpoint *)
    let realar =
      hnf_prod_appvect env sigma "make_branch" (mis_arity mispec) vargs in
    let lnames,_ = splay_prod env sigma realar in 
    let nar = List.length lnames in
    let branches = 
      array_map3
	(fun f t reca -> 
	   whd_betaxtra
             (Indrec.make_rec_branch_arg env sigma
                ((Array.map (lift (nar+2)) vargs),depFvec,nar+1)
                f t reca))
        (Array.map (lift (nar+2)) lf) typeconstrvec recargs 
    in 
    let deffix = 
      it_lambda_name env
	(lambda_create env
	   (appvect (mI,Array.append (Array.map (lift (nar+1)) vargs)
                       (rel_vect 0 nar)),
            mkMutCaseA (ci_of_mind mI) 
              (lift (nar+2) p) (Rel 1) branches))
        (lift_context 1 lnames) 
    in
    if noccurn 1 deffix then 
      whd_beta env sigma (applist (pop deffix,realargs@[c]))
    else
      let typPfix = 
	it_prod_name env
	  (prod_create env
	     (appvect (mI,(Array.append 
			     (Array.map (lift nar) vargs)
			     (rel_vect 0 nar))),
	      (if dep then 
		 applist (whd_beta_stack env sigma 
			    (lift (nar+1) p) (rel_list 0 (nar+1)))
	       else 
		 applist (whd_beta_stack env sigma 
			    (lift (nar+1) p) (rel_list 1 nar)))))
          lnames 
      in
      let fix = DOPN(Fix([|nar|],0),
		     [|typPfix;
		       DLAMV(Name(id_of_string "F"),[|deffix|])|])
      in 
      applist (fix,realargs@[c])
  else 
    mkMutCaseA (ci_of_mind mI) p c lf

(***********************************************************************)
let ctxt_of_ids ids =
  Array.of_list (List.map (function id -> VAR id) ids)

let mt_evd = Evd.empty

let vect_lift_type = Array.mapi (fun i t -> typed_app (lift i) t)

let j_nf_ise sigma {uj_val=v;uj_type=t;uj_kind=k} =
  {uj_val=nf_ise1 sigma v;uj_type=nf_ise1 sigma t;uj_kind=k}

let jv_nf_ise sigma = Array.map (j_nf_ise sigma)

(* Utilis� pour inf�rer le pr�dicat des Cases *)
(* Semble exag�rement fort *)
(* Faudra pr�f�rer une unification entre les types de toutes les clauses *)
(* et autoriser des ? � rester dans le r�sultat de l'unification *)
let has_ise sigma t = 
  try let _ = whd_ise sigma t in true
  with UserError _ -> false

let evar_type_fixpoint env isevars lna lar vdefj =
  let lt = Array.length vdefj in 
    if Array.length lar = lt then 
      for i = 0 to lt-1 do 
        if not (the_conv_x_leq env isevars
		  (vdefj.(i)).uj_type (lift lt (body_of_type lar.(i)))) then
          error_ill_typed_rec_body CCI env i lna 
	    (jv_nf_ise !isevars vdefj) 
	    (Array.map (typed_app (nf_ise1 !isevars)) lar)
      done


(* Inutile ?
let cast_rel isevars env cj tj =
    if the_conv_x_leq isevars env cj.uj_type tj.uj_val then
        {uj_val=j_val_only cj;
         uj_type=tj.uj_val;
         uj_kind = hnf_constr !isevars tj.uj_type}
   else error_actual_type CCI env (j_nf_ise !isevars cj) (j_nf_ise !isevars tj)

*)
let let_path = make_path ["Core"] (id_of_string "let") CCI

let wrong_number_of_cases_message loc env isevars (c,ct) expn = 
  let c = nf_ise1 !isevars c and ct = nf_ise1 !isevars ct in
  error_number_branches_loc loc CCI env c ct expn

let check_branches_message loc env isevars (c,ct) (explft,lft) = 
  let n = Array.length explft and expn = Array.length lft in
  if n<>expn then wrong_number_of_cases_message loc env isevars (c,ct) expn;
  for i = 0 to n-1 do
    if not (the_conv_x_leq env isevars lft.(i) explft.(i)) then 
      let c = nf_ise1 !isevars c
      and ct = nf_ise1 !isevars ct 
      and lfi = nf_betaiota env !isevars (nf_ise1 !isevars lft.(i)) in
      error_ill_formed_branch_loc loc CCI env c i lfi 
	(nf_betaiota env !isevars explft.(i))
  done

(*
let evar_type_case isevars env ct pt lft p c =
  let (mind,bty,rslty) = type_case_branches env !isevars ct pt p c
  in check_branches_message isevars env (c,ct) (bty,lft); (mind,rslty)
*)

let pretype_var loc env id = 
  try
    match lookup_id id (context env) with
      | RELNAME (n,{body=typ;typ=s}) ->
	  { uj_val  = Rel n;
	    uj_type = lift n typ;
	    uj_kind = DOP0 (Sort s) }
      | GLOBNAME (id,{body=typ;typ=s}) ->
	  { uj_val  = VAR id;
	    uj_type = typ;
	    uj_kind = DOP0 (Sort s) }
    with Not_found ->
      error_var_not_found_loc loc CCI id

(*************************************************************************)
(* Main pretyping function                                               *)

let trad_metamap = ref []
let trad_nocheck = ref false

let pretype_ref loc isevars env = function
| RMeta n ->
    let metaty =
      try List.assoc n !trad_metamap
      with Not_found ->
	user_err_loc 
	  (loc,"pretype",
	   [< 'sTR "Metavariable "; 'iNT n; 'sTR "remains non instanciated" >])
	  in
    (match kind_of_term metaty with
      IsCast (typ,kind) -> {uj_val=DOP0 (Meta n); uj_type=typ; uj_kind=kind}
    | _ ->
        {uj_val=DOP0 (Meta n);
          uj_type=metaty;
          uj_kind=failwith "should be casted"})
	   (* hnf_constr !isevars (exemeta_hack metaty).uj_type}) *)

| RVar id -> pretype_var loc env id

| RConst (sp,ids) ->
    let cstr = mkConst sp (ctxt_of_ids ids) in
    make_judge cstr (type_of_constant env !isevars cstr)

| RAbst sp -> failwith "Pretype: abst doit dispara�tre"
(*
  if sp = let_path then
      (match Array.to_list cl with
       [m;DLAM(na,b)] ->
       let mj = pretype mt_tycon isevars env m in
	 (try 
	    let mj = inh_ass_of_j isevars env mj in
	    let mb = body_of_type mj in
	    let bj =
	     pretype mt_tycon (push_rel (na,mj) env) isevars b in
	   {uj_val = DOPN(Abst sp,[|mb;DLAM(na,bj.uj_val)|]);
            uj_type = sAPP (DLAM(na,bj.uj_type)) mb;
            uj_kind = pop bj.uj_kind }
	 with UserError _ -> 
	   pretype vtcon isevars env (abst_value cstr)) 
      | _ -> errorlabstrm "Trad.constr_of_com" [< 'sTR"Malformed ``let''" >])
   else if evaluable_abst cstr then
     pretype vtcon isevars env (abst_value cstr)
   else error "Cannot typecheck an unevaluable abstraction"
*)
| REVar (sp,ids) -> error " Not able to type terms with dependent subgoals"
(* Not able to type goal existential yet
    let cstr = mkConst sp (ctxt_of_ids ids) in
    make_judge cstr (type_of_existential env !isevars cstr)
*)
| RInd ((sp,i),ids) ->
    let cstr = mkMutInd sp i (ctxt_of_ids ids) in
    make_judge cstr (type_of_inductive env !isevars cstr)
 
| RConstruct (((sp,i),j),ids) ->
    let cstr = mkMutConstruct sp i j (ctxt_of_ids ids) in
    let (typ,kind) = destCast (type_of_constructor env !isevars cstr) in
    {uj_val=cstr; uj_type=typ; uj_kind=kind}

(* pretype vtcon isevars env constr tries to solve the *)
(* existential variables in constr in environment env with the *)
(* constraint vtcon (see Tradevar). *)
(* Invariant : Prod and Lambda types are casted !! *)
let rec pretype vtcon env isevars cstr =
match cstr with   (* O� teste-t-on que le r�sultat doit satisfaire tycon ? *)


| RRef (loc,ref) -> 
    pretype_ref loc isevars env ref

| RHole loc ->
  if !compter then nbimpl:=!nbimpl+1;
  (match vtcon with
    (true,(Some v, _)) ->
      let (valc,typc) = destCast v in
      {uj_val=valc; uj_type=typc; uj_kind=dummy_sort}
  | (false,(None,Some ty)) ->
      let (c,ty) = new_isevar isevars env ty CCI in
      {uj_val=c;uj_type=ty;uj_kind = dummy_sort}
  | (true,(None,None)) ->
      let (c,ty) = new_isevar isevars env (mkCast dummy_sort dummy_sort) CCI in
      {uj_val=c;uj_type=ty;uj_kind = dummy_sort}
  | (false,(None,None)) ->
      (match loc with
	  None -> anomaly "There is an implicit argument I cannot solve"
	| Some loc -> 
	    user_err_loc
	      (loc,"pretype",
	       [< 'sTR "Cannot infer a term for this placeholder" >]))
  | _ -> anomaly "tycon")


| RRec (loc,fixkind,lfi,lar,vdef) ->
  let larj = Array.map (pretype def_vty_con env isevars) lar in
  let lara = Array.map (assumption_of_judgment env !isevars) larj in
  let nbfix = Array.length lfi in
  let lfi = List.map (fun id -> Name id) (Array.to_list lfi) in
  let newenv =
    array_fold_left2 (fun env id ar -> (push_rel (id,ar) env))
      env (Array.of_list (List.rev lfi)) (vect_lift_type lara) in
  let vdefj =
    Array.mapi 
      (fun i def -> (* we lift nbfix times the type in tycon, because of
                     * the nbfix variables pushed to newenv *)
        pretype (mk_tycon (lift nbfix (larj.(i).uj_val))) newenv isevars def)
      vdef in
  (evar_type_fixpoint env isevars lfi lara vdefj;
  match fixkind with
    | RFix(vn,i) ->
      let fix = mkFix vn i lara (List.rev lfi) (Array.map j_val_only vdefj) in
	check_fix env !isevars fix;
	make_judge fix lara.(i)
    | RCofix i -> 
      let cofix = mkCoFix i lara (List.rev lfi) (Array.map j_val_only vdefj) in
	check_cofix env !isevars cofix;
	make_judge cofix lara.(i))

| RSort (loc,RProp c) -> judge_of_prop_contents c

| RSort (loc,RType) -> 
    { uj_val = dummy_sort; uj_type = dummy_sort; uj_kind = dummy_sort }

| RApp (loc,f,args) -> 
    let j = pretype mt_tycon env isevars f in
    let j = inh_app_fun env isevars j in
    let apply_one_arg (tycon,jl) c =
      let cj = pretype (app_dom_tycon env isevars tycon) env isevars c in
      let rtc = app_rng_tycon env isevars cj.uj_val tycon in
      (rtc,cj::jl)  in
    let jl = List.rev (snd (List.fold_left apply_one_arg
			      (mk_tycon j.uj_type,[]) args)) in
    inh_apply_rel_list !trad_nocheck env isevars jl j vtcon

| RBinder(loc,BLambda,name,c1,c2)      ->
    let j = pretype (abs_dom_valcon env isevars vtcon) env isevars c1 in
    let assum = inh_ass_of_j env isevars j in
    let var = (name,assum) in
    let j' =
      pretype (abs_rng_tycon env isevars vtcon) (push_rel var env) isevars c2 
    in 
    fst (abs_rel env !isevars name assum j')

| RBinder(loc,BProd,name,c1,c2)        ->
    let j = pretype def_vty_con env isevars c1 in
    let assum = inh_ass_of_j env isevars j in
    let var = (name,assum) in
    let j' = pretype def_vty_con (push_rel var env) isevars c2 in
    let j'' = inh_tosort env isevars j' in
    fst (gen_rel env !isevars name assum j'')

| ROldCase (loc,isrec,po,c,lf) ->
  let cj = pretype mt_tycon env isevars c in
  let (mind,_) =
    try find_mrectype env !isevars cj.uj_type
    with Induc -> error_case_not_inductive CCI env
	(nf_ise1 !isevars cj.uj_val) (nf_ise1 !isevars cj.uj_type) in
  let pj = match po with
    | Some p -> pretype mt_tycon env isevars p
    | None -> 
	try match vtcon with
	    (_,(_,Some pred)) -> 
	      let (predc,predt) = destCast pred in
	      let predj = {uj_val=predc;uj_type=predt;uj_kind=dummy_sort} in
	      inh_tosort env isevars predj
	  | _ -> error "notype"
	with UserError _ -> (* get type information from type of branches *)
	  let rec findtype i =
	    if i > Array.length lf
	    then error_cant_find_case_type_loc loc env cj.uj_val
	    else
	      try
		let expti = Indrec.branch_scheme env !isevars isrec i cj.uj_type in
		let fj = pretype (mk_tycon expti) env isevars lf.(i-1) in
		let efjt = nf_ise1 !isevars fj.uj_type in 
		let pred = 
		  Indrec.pred_case_ml_onebranch env !isevars isrec 
		    (cj.uj_val,cj.uj_type) (i,fj.uj_val,efjt) in
		if has_ise !isevars pred then findtype (i+1)
		else 
		  let pty = Retyping.get_type_of env !isevars pred in
		  let k = Retyping.get_type_of env !isevars pty in
		    {uj_val=pred;uj_type=pty;uj_kind=k}
	      with UserError _ -> findtype (i+1) in
	    findtype 1 in

  let evalct = nf_ise1 !isevars cj.uj_type
  and evalPt = nf_ise1 !isevars pj.uj_type in

  let (mind,bty,rsty) =
    Indrec.type_rec_branches isrec env !isevars evalct evalPt pj.uj_val cj.uj_val in
  if Array.length bty <> Array.length lf then
    wrong_number_of_cases_message loc env isevars (cj.uj_val,evalct)
      (Array.length bty)
  else
    let lfj =
      array_map2
        (fun tyc f -> pretype (mk_tycon tyc) env isevars f) bty lf in
    let lfv = (Array.map (fun j -> j.uj_val) lfj) in
    let lft = (Array.map (fun j -> j.uj_type) lfj) in
    check_branches_message loc env isevars (cj.uj_val,evalct) (bty,lft);
    let v =
      if isrec
      then 
	let rEC = Array.append [|pj.uj_val; cj.uj_val|] lfv in
	transform_rec loc env !isevars rEC (evalct,evalPt)
      else let ci = ci_of_mind mind in
	mkMutCaseA ci pj.uj_val cj.uj_val (Array.map (fun j-> j.uj_val) lfj) in

       {uj_val = v;
       uj_type = rsty;
       uj_kind = snd (splay_prod env !isevars evalPt)}

| RCases (loc,prinfo,po,tml,eqns) ->
    Cases.compile_multcase
      ((fun vtyc env -> pretype vtyc env isevars),isevars)
      vtcon env (po,tml,eqns)

| RCast(loc,c,t) ->
  let tj = pretype def_vty_con env isevars t in
  let tj = inh_tosort_force env isevars tj in
  let cj =
    pretype (mk_tycon2 vtcon (assumption_of_judgment env !isevars tj).body)
      env isevars c in
  inh_cast_rel env isevars cj tj

(* Maintenant, tout s'ex�cute... 
  | _ -> error_cant_execute CCI env (nf_ise1 env !isevars cstr)
*)


let unsafe_fmachine vtcon nocheck isevars metamap env constr = 
  trad_metamap := metamap;
  trad_nocheck := nocheck;
  reset_problems ();
  pretype vtcon env isevars constr


(* [fail_evar] says how to process unresolved evars:
 *   true -> raise an error message
 *   false -> convert them into new Metas (casted with their type)
 *)
let process_evars fail_evar env sigma =
  (if fail_evar then
     try whd_ise env sigma
     with Uninstantiated_evar n ->
          errorlabstrm "whd_ise"
            [< 'sTR"There is an unknown subterm I cannot solve" >]
   else whd_ise1_metas env sigma)


let j_apply f env sigma j =
  let under_outer_cast f env sigma = function
    | DOP2 (Cast,b,t) -> DOP2 (Cast,f env sigma b,f env sigma t)
    | c -> f env sigma c in
  { uj_val=strong (under_outer_cast f) env sigma j.uj_val;
    uj_type=strong f env sigma j.uj_type;
    uj_kind=strong f env sigma j.uj_kind}

(* TODO: comment faire remonter l'information si le typage a resolu des
       variables du sigma original. il faudrait que la fonction de typage
       retourne aussi le nouveau sigma...
*)
let ise_resolve_casted sigma env typ c =
  let isevars = ref sigma in
  let j = unsafe_fmachine (mk_tycon typ) false isevars [] env c in
  (j_apply (fun _ -> process_evars true) env !isevars j).uj_val

let ise_resolve fail_evar sigma metamap env c =
  let isevars = ref sigma in
  let j = unsafe_fmachine mt_tycon false isevars metamap env c in
  j_apply (fun _ -> process_evars fail_evar) env !isevars j


let ise_resolve_type fail_evar sigma metamap env c =
  let isevars = ref sigma in
  let j = unsafe_fmachine def_vty_con false isevars metamap env c in
  let tj = inh_ass_of_j env isevars j in
  typed_app (strong (fun _ -> process_evars fail_evar) env !isevars) tj


let ise_resolve_nocheck sigma metamap env c =
  let isevars = ref sigma in
  let j = unsafe_fmachine mt_tycon true isevars metamap env c in
  j_apply (fun _ -> process_evars true) env !isevars j


let ise_resolve1 is_ass sigma env c =
  if is_ass then body_of_type (ise_resolve_type true sigma [] env c)
  else (ise_resolve true sigma [] env c).uj_val

(* Keeping universe constraints *)
(*
let fconstruct_type_with_univ_sp sigma sign sp c =
  with_universes
    (Mach.fexecute_type sigma sign) (sp,initial_universes,c) 


let fconstruct_with_univ_sp sigma sign sp c =
  with_universes
    (Mach.fexecute sigma sign) (sp,initial_universes,c) 


let infconstruct_type_with_univ_sp sigma (sign,fsign) sp c =
  with_universes
    (Mach.infexecute_type sigma (sign,fsign)) (sp,initial_universes,c) 


let infconstruct_with_univ_sp sigma (sign,fsign) sp c =
  with_universes
    (Mach.infexecute sigma (sign,fsign)) (sp,initial_universes,c) 
*)
