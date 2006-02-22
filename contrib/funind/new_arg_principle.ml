open Printer
open Util
open Term
open Termops 
open Names 
open Declarations
open Pp
open Entries
open Hiddentac
open Evd
open Tacmach
open Proof_type
open Tacticals
open Tactics
open Indfun_common

(* let msgnl = Pp.msgnl *)

let observe_tac s tac g = 
  if Tacinterp.get_debug () <> Tactic_debug.DebugOff 
  then Recdef.do_observe_tac s tac g
  else tac g



let tclTRYD tac =
  if  !Options.debug  ||  Tacinterp.get_debug () <> Tactic_debug.DebugOff
  then tclTRY tac
  else tac


type rewrite_dir =
  | LR
  | RL

let rew_all ?(rev_order=false) lr : tactic =
  let rew =
    match lr with
      | LR -> Equality.rewriteLR
      | RL ->  Equality.rewriteRL
  in
  let order =
    if rev_order then List.rev else fun x -> x
  in
  fun g ->
    onHyps
      pf_hyps
      (fun l -> tclMAP (fun (id,_,_) ->  tclTRY (rew (mkVar id))) (order l))
      g

      
let test_var args arg_num =
  isVar args.(arg_num)
   


let rewrite_until_var arg_num : tactic =
  let constr_eq =  (Coqlib.build_coq_eq_data ()).Coqlib.eq in
  let replace_if_unify arg (pat,cl,id,lhs)  : tactic =
    fun g ->
      try
	let (evd,matched) =
	  Unification.w_unify_to_subterm
	    (pf_env g) ~mod_delta:false (pat,arg) cl.Clenv.env
	in
	let cl' = {cl with Clenv.env = evd } in
	let c2 = Clenv.clenv_nf_meta cl' lhs in
	(Equality.replace matched c2) g
      with _ -> tclFAIL 0 (str "") g
  in
  let rewrite_on_step equalities : tactic =
    fun g ->
      match kind_of_term (pf_concl g) with
	| App(_,args) when (not (test_var args arg_num)) ->
(* 	    tclFIRST (List.map (fun a -> observe_tac (str "replace_if_unify") (replace_if_unify args.(arg_num) a)) equalities) g *)
	    tclFIRST (List.map (replace_if_unify args.(arg_num)) equalities) g
	| _ ->
	    raise (Util.UserError("", (str "No more rewrite" ++
					 pr_lconstr_env (pf_env g) (pf_concl g))))
  in
  fun g ->
    let equalities =
      List.filter
	(
	  fun (_,_,id_t) ->
	    match kind_of_term id_t with
	      | App(f,_) -> eq_constr f constr_eq
	      | _ -> false
	)
	(pf_hyps g)
    in
    let f (id,_,ctype)  =
      let c = mkVar id in
      let eqclause = Clenv.make_clenv_binding g (c,ctype) Rawterm.NoBindings in
      let clause_type = Clenv.clenv_type eqclause in
      let f,args = decompose_app (clause_type) in
      let rec split_last_two = function
	| [c1;c2] -> (c1, c2)
	| x::y::z ->
	    split_last_two (y::z)
	| _ ->
	    error ("The term provided is not an equivalence")
      in
      let (c1,c2) = split_last_two args in
      (c2,eqclause,id,c1)
    in
    let matching_hyps = List.map f equalities in
    tclTRY (tclREPEAT (tclPROGRESS (rewrite_on_step matching_hyps))) g



let make_refl_eq type_of_t t  =
  let refl_equal_term = Lazy.force refl_equal in
  mkApp(refl_equal_term,[|type_of_t;t|])

let case_eq  tac body term g =
(*   msgnl (str "case_eq on " ++ pr_lconstr_env (pf_env g) term); *)
  let type_of_term = pf_type_of g term in
  let term_eq =
    make_refl_eq type_of_term term
  in
  let ba_fun ba  : tactic =
    fun g ->
      tclTHENSEQ
	[intro_patterns [](* ba.branchnames *);
	 fun g ->
	   let (_,_,new_term_value_eq)  = pf_last_hyp g in
	   let new_term_value =
	     match kind_of_term new_term_value_eq with
	       | App(f,[| _;_;args2 |]) -> args2
	     | _ ->
		 Pp.msgnl (pr_gls g ++ fnl () ++ str "last hyp is" ++
			     pr_lconstr_env (pf_env g) new_term_value_eq
			  );
		 assert false
	   in
	   let fun_body =
	     mkLambda(Anonymous,type_of_term,replace_term term (mkRel 1) body)
	   in
	   let new_body = mkApp(fun_body,[| new_term_value |]) in
	   tac (pf_nf_betaiota g new_body) g
	]
	g
  in
    (
      tclTHENSEQ
	[
	  h_generalize [term_eq];
	  pattern_option [[-1],term] None;
	  case_then_using Genarg.IntroAnonymous (ba_fun) None ([],[]) term
	]
    )
    g



let my_reflexivity : tactic =
  let test_eq =
    lazy (eq_constr (Coqlib.build_coq_eq ()))
  in
  let build_reflexivity  =
    lazy (fun ty t -> mkApp((Coqlib.build_coq_eq_data ()).Coqlib.refl,[|ty;t|]))
  in
  fun g ->
    begin
    match kind_of_term (pf_concl g) with
      | App(eq,[|ty;t1;t2|]) when (Lazy.force test_eq) eq ->
	    if not (Termops.occur_existential t1)
	    then tclTHEN (h_change None (mkApp(eq,[|ty;t1;t1|]))  onConcl ) (apply ((Lazy.force build_reflexivity) ty t1))
	    else if not (Termops.occur_existential t2)
	    then   tclTHEN (h_change None (mkApp(eq,[|ty;t2;t2|])) onConcl ) (apply ((Lazy.force build_reflexivity) ty t2))
	    else tclFAIL 0 (str "")
	      
      | _ -> tclFAIL 0 (str "")
    end g

let exactify_proof rec_pos ptes_to_fix : tactic =
  let not_as_constant = Coqlib.build_coq_not  () in
  let or_as_ind =   Coqlib.build_coq_or () in
  let eq_not = eq_constr not_as_constant in
  let eq_or = eq_constr or_as_ind in
  let tac_res tac: tactic =
    fun g ->
      match kind_of_term (pf_concl g) with
	| Prod _ -> tclTHEN intro tac g
	| App(f,_) ->
	    if eq_not f
	    then tclTHEN (intro_force true) (tclABSTRACT None (Cctac.cc_tactic []))
	      (* Equality.discr_tac None *) g
	    else if eq_or f
	    then
	      tclSOLVE
		[tclTHEN simplest_left tac;
		 tclTHEN simplest_right tac
		] g
	    else
	      begin
		match rec_pos with
		  | Some rec_pos ->
		      begin
			match kind_of_term f with
			  | Var id ->
			      begin
				try
				  let fix_id = Idmap.find id ptes_to_fix in
				  let fix = mkVar (fix_id) in
				  tclTHEN
				    (rewrite_until_var rec_pos)
				    (Eauto.e_resolve_constr fix)
				    g
				with Not_found ->
				  (* 				Pp.msgnl (str "No fix found for "++ *)
				  (* 					    pr_lconstr_env (pf_env g) f); *)
				  tclFAIL 0 (str "No such fix found") g
			      end
			  | _ -> 
			      tclCOMPLETE 
				(Eauto. gen_eauto false (false,5) [] (Some []))
				(* (string_of_pp (pr_lconstr_env (pf_env g) f)) *)
				g
		      end
		  | None -> 
		      tclCOMPLETE (Eauto. gen_eauto false (false,5) [] (Some [])) g
		      
	      end
	| _ -> tclFAIL 0 (str "Not a good term") g
   in
  let rec exactify_proof g =
    tclFIRST
      [
	tclSOLVE [my_reflexivity];
	tclSOLVE [Eauto.e_assumption];
	tclSOLVE [Tactics.reflexivity ];
	tac_res exactify_proof; 
	tclCOMPLETE 
	  (
	    tclREPEAT
	      (
		tclPROGRESS 
		  (tclTHEN 
		     (rew_all LR) 
		     (Eauto. gen_eauto false (false,5) [] (Some []))
		  )
	      )
	  )
      ] g
  in
  observe_tac "exactify_proof with " exactify_proof
    

let reduce_fname fnames : tactic =
  let do_reduce : tactic = reduce
    (Rawterm.Lazy
       { Rawterm.rBeta = true;
	 Rawterm.rIota = true;
	 Rawterm.rZeta = true;
	 Rawterm.rDelta = false;
	 Rawterm.rConst = List.map (fun f -> EvalConstRef f) fnames
       }
    )
    onConcl
  in
  let refold  : tactic =
    reduce
      (Rawterm.Fold (List.map mkConst fnames))
    onConcl
      
  in
  fun  g ->
(*      if Tacinterp.get_debug () <> Tactic_debug.DebugOff  *)
(*      then     msgnl (str "reduce_fname"); *)
    tclTHENSEQ
      [do_reduce;
       refold ;
       (tclREPEAT (tclPROGRESS (rew_all  LR)))
      ]
      g

let h_exact ?(with_rew_all=false) c :tactic =
  observe_tac "h_exact " (exact_check c )
	  
	    
let finalize_proof rec_pos fixes (hyps:identifier list) =
  if Tacinterp.get_debug () <> Tactic_debug.DebugOff
  then
    Pp.msgnl (str "rec hyps are : " ++
		prlist_with_sep spc Ppconstr.pr_id hyps);
  let exactify_proof = exactify_proof rec_pos fixes in
 
  let exactify_proof_with_id id : tactic =
    let do_exactify_proof_with_id =
      fun g ->
	let res  =
	  tclTHEN
	    (Eauto.e_resolve_constr (mkVar id))
	    (tclTRY exactify_proof)
	    
	in
	tclTHEN
	  res
	  ((h_exact (Coqlib.build_coq_I ())))
	  g
    in
    fun g -> observe_tac "exactify_proof_with_id" do_exactify_proof_with_id g
  in
  let apply_one_hyp hyp acc =
    tclORELSE
      ( exactify_proof_with_id hyp)
      acc
  in
  let apply_one_hyp_with_rewall hyp acc =
    tclORELSE
      (tclTHEN
	 (rew_all RL)
	 (exactify_proof_with_id hyp)
      )
      
      acc
  in
  let apply_hyps =
    tclTRYD(
      (List.fold_right
	 apply_one_hyp
	 hyps
	 (List.fold_right
	    apply_one_hyp_with_rewall
	    hyps
	    (tclFAIL 0 (str "No rec hyps found ") )
	 )
      ))
  in
  let finalize_proof fnames t  : tactic =
    let change_tac  tac g =
	match kind_of_term ( pf_concl g) with
	  | App(p,args) ->
	      let nargs = Array.length args in
	      begin
		tclTHENS
		  (try Equality.replace (args.(nargs -1)) t
		   with _ ->
		     tclFAIL 0 (str "")
		  )
		[tac;
		 tclTRY (tclTHEN (reduce_fname fnames) ( (Tactics.reflexivity)))
		]
		  g
	      end
	  | _ -> assert false
    in
  fun g ->
(*     if Tacinterp.get_debug () <> Tactic_debug.DebugOff  *)
(*     then  *)
(*       msgnl (str "finalize with body "++ Printer.pr_lconstr t ++  *)
(* 	       str " on goal "++ Printer.pr_goal (sig_it g)); *)
    (change_tac apply_hyps) g
  in
  finalize_proof

let do_prove_princ_for_struct
    (rec_pos:int option)  (fnames:constant list)
    (ptes:identifier list) (fixes:identifier Idmap.t) (hyps: identifier list)
      (term:constr) : tactic =
  let finalize_proof term =
    finalize_proof rec_pos fixes hyps fnames term
  in
  let rec do_prove_princ_for_struct do_finalize term g =
(*      if Tacinterp.get_debug () <> Tactic_debug.DebugOff  *)
(*      then msgnl (str "Proving with body : " ++ pr_lconstr_env (pf_env g) term); *)
    let tac =
      fun g ->
	match kind_of_term term with
	  | Case(_,_,t,_) ->
	      observe_tac "case_eq" 
	      (case_eq (do_prove_princ_for_struct do_finalize) term t) g
	  | Lambda(n,t,b) ->
	      begin
		match kind_of_term( pf_concl g) with
		  | Prod _ ->
		      tclTHEN
			intro
			(fun g' ->
			   let (id,_,_) = pf_last_hyp g' in
			   let new_term = pf_nf_betaiota g' (mkApp(term,[|mkVar id|])) in
			   do_prove_princ_for_struct do_finalize new_term g'
			) g
		  | _ ->
		      do_finalize term g
	      end
	  | Cast(t,_,_) -> do_prove_princ_for_struct do_finalize t g
	  | Const _ | Var _ | Meta _ | Evar _ | Sort _ | Construct _ | Ind _ ->
	      do_finalize term g
	  | App(_,_) ->
	      let f,args = decompose_app term in
	      begin
		match kind_of_term f with
		  | Var _ | Construct _ | Rel _ | Evar _ | Meta _  | Ind _ ->
		      do_prove_princ_for_struct_args do_finalize f args g
		  | Const c when not (List.mem c fnames) ->
		      do_prove_princ_for_struct_args do_finalize f args g
		  | Const _ ->
		      do_finalize  term g
		  | _ ->
		      warning "Applied binders not yet implemented";
		      tclFAIL 0 (str "TODO") g
	      end
	  | Fix _ | CoFix _ ->
	      error ( "Anonymous local (co)fixpoints are not handled yet")
	  | Prod _ -> assert false
	  | LetIn (Name id,v,t,b) ->
	      do_prove_princ_for_struct do_finalize (subst1 v b) g
	  | LetIn(Anonymous,_,_,b) ->
	      do_prove_princ_for_struct do_finalize (pop  b) g
	  | _ ->
	      errorlabstrm "" (str "in do_prove_princ_for_struct found : "(* ++ *)
(* 				 pr_lconstr_env (pf_env g) term *)
			      )

      in
       tac g
  and do_prove_princ_for_struct_args do_finalize f_args' args :tactic =
    fun g ->
(*      if Tacinterp.get_debug () <> Tactic_debug.DebugOff  *)
(*      then msgnl (str "do_prove_princ_for_struct_args with "  ++  *)
(* 		   pr_lconstr_env (pf_env g) f_args' *)
(* 		); *)
      let tac =
	match args with
	  | []  ->
	      do_finalize f_args'
	  | arg::args ->
	      let do_finalize new_arg =
		tclTRYD
		  (do_prove_princ_for_struct_args
		     do_finalize
		     (mkApp(f_args',[|new_arg|]))
		     args
		  )
	      in
	      do_prove_princ_for_struct do_finalize arg
      in
      tclTRYD(tac) g
	
  in
  do_prove_princ_for_struct
    (finalize_proof)
    term

let is_pte_type t =
  isSort (snd (decompose_prod t))
    
let is_pte (_,_,t) = is_pte_type t

let prove_princ_for_struct fun_num f_names  nparams : tactic =
  let fnames_as_constr = Array.to_list (Array.map mkConst f_names) in
  let fbody =
    match (Global.lookup_constant f_names.(fun_num)).const_body with
      | Some b ->
	  let body = force b in
	  Tacred.cbv_norm_flags
	    (Closure.RedFlags.mkflags [Closure.RedFlags.fZETA])
	    (Global.env ())
	    (Evd.empty)
	    body
      | None -> error ( "Cannot define a principle over an axiom ")
  in
  let rec_arg_num,fbody =
    match kind_of_term fbody with
      | Fix((idxs,fix_num),(_,_,ca)) ->
	  begin Some (idxs.(fix_num) - nparams),substl (List.rev fnames_as_constr) ca.(fix_num) end
      | b -> None,fbody
  in
  let f_real_args = nb_lam fbody - nparams in
  let test_goal_for_hyps g =
    let goal_nb_prod = nb_prod (pf_concl g) in
    goal_nb_prod = f_real_args
  in
  let test_goal_for_args g =
    let goal_nb_prod = nb_prod (pf_concl g) in
    goal_nb_prod < 1
  in
  let rec intro_params tac params n : tactic =
    if n = 0
    then tac params
    else
      tclTHEN
	(intro)
	(fun g ->
	   let (id,_,_) = pf_last_hyp g in
	   intro_params tac (id::params) (n-1) g
	)
  in
  let rec intro_pte tac ptes : tactic =
    tclTHEN
      intro
      (fun g ->
	 let (id,_,_) as pte = pf_last_hyp g in
	 if is_pte pte
	 then intro_pte tac (id::ptes) g
	 else
	   tclTHENSEQ
	     [ h_generalize [(mkVar id)];
	       clear  [id];
	       tac ptes
	     ]
	     g
      )
  in
  let rec intro_hyps tac hyps : tactic =
    fun g ->
      if test_goal_for_hyps g
      then tac hyps g
      else
	tclTHEN
	  intro
	  (fun g' ->
	     let (id,_,_) = pf_last_hyp g' in
	     intro_hyps tac (id::hyps) g'
	  )
	  g
  in
  let do_fix ptes tac  : tactic =
    match rec_arg_num with
      | None -> tac (Idmap.empty)
      | Some fix_arg_num ->
	  fun g ->
	  let this_fix_id = (fresh_id (pf_ids_of_hyps g) "fix___") in
	  let ptes_to_fix =
	    List.fold_left2
	      (fun acc pte fix ->
		 Idmap.add pte fix acc
	      )
	      Idmap.empty
	      ptes
	      [this_fix_id]
	  in
	  tclTHEN
	    (h_mutual_fix  this_fix_id (fix_arg_num  +1) [])
	    (tac ptes_to_fix)
	    g
  in
  let rec intro_args tac args : tactic =
    fun g ->
      if test_goal_for_args g
      then tac args g
      else
	tclTHEN
	  intro
	  (fun g' ->
	     let (id,_,_) = pf_last_hyp g' in
	     intro_args tac (id::args) g'
	  )
	  g
  in
  let intro_tacs tac : tactic =
    fun g ->
(*       msgnl (str "introducing params"); *)
      intro_params
	(fun params ->
(* 	   msgnl (str "introducing properties"); *)
	   intro_pte
	     (fun ptes ->
(* 		msgnl (str "introducing rec hyps"); *)
		intro_hyps
		  (fun hyps ->
(* 		     msgnl (str "creating fixes"); *)
		     do_fix ptes
		       (fun ptes_to_fix ->
(* 			  msgnl (str "introducing args"); *)
			  intro_args
			    (fun args ->
(* 			       tclTHEN  *)
(* 				 (reduce_fname (Array.to_list f_names)) *)
				 (tac params ptes ptes_to_fix hyps args))
			    []
		       )
		  )
		  []
	     )
	     []
	)
	[]
	nparams
	g
  in
  let apply_fbody g params args  =
(*     msgnl (str "applying fbody"); *)
    let args' = List.rev_map mkVar args in
    let f_args =
      List.fold_left (fun acc p -> (mkVar p)::acc) args' params
    in
    let app_f = applist(subst1 (mkConst f_names.(fun_num)) fbody,f_args) in
(*     Pp.msgnl (pr_lconstr_env (pf_env g) app_f); *)
    pf_nf_betaiota g app_f
  in
  let prepare_goal_tac tac : tactic =
    intro_tacs
      (fun  params ptes ptes_to_fix hyps args g ->
	 let app_f = apply_fbody g params args in
(* 	 msgnl (str "proving"); *)
	 match rec_arg_num with
	     Some rec_arg_num ->
	       let actual_args =
		 List.fold_left (fun  y x -> x::y)
		   (List.rev args)
		   params
	       in
	       let to_replace =
	       applist(mkConst f_names.(fun_num),List.map mkVar actual_args) in
	       
	       tclTHENS
		 (Equality.replace
		    to_replace
		    app_f
		 )
		 [
		   tac (Array.to_list f_names) ptes ptes_to_fix hyps app_f;
		   let id = List.nth (List.rev args) (rec_arg_num ) in
		   (tclTHENSEQ
		      [(h_simplest_case (mkVar id));
		       tclTRY Tactics.intros_reflexivity
		      ]
		   )
(* 		     Tactics.reflexivity) *)
		 ]
		 g
	   | None ->
	       tclTHEN
		 (reduce_fname (Array.to_list f_names))
		 (tac (Array.to_list f_names) ptes ptes_to_fix hyps app_f)
		 g

(* 	 tac (Array.to_list f_names) ptes ptes_to_fix hyps app_f g *)
      )
  in
  prepare_goal_tac (fun g -> do_prove_princ_for_struct rec_arg_num g)



(* let case_eq term : tactic =  *)
(*   fun g ->  *)
(*     let type_of_term = pf_type_of g term in  *)
(*     let eq_proof_term =  *)
(*       let refl_equal_term = Lazy.force refl_equal in *)
(*       mkApp(refl_equal_term,[|type_of_t;t|]) *)
(*     in  *)
(*     let ba_fun ba =  *)
(*       tclDO ba.nassums h_intro *)
(*     in  *)
(*     tclTHENSEQ  *)
(*       [ *)
(* 	h_generalize [eq_proof_term];  *)
(* 	pattern_option [[-1],term] None; *)
(* 	case_then_using  Genarg.IntroAnonymous ba_fun term None ([],[]) term *)
(*       ] *)
(*       g *)
    

(* let heq_id = id_of_string "Heq" *)

(* let do_prove_princ_for_struct  *)
(*     predicates_ids ptes_to_fix branches_ids params_ids args_ids rec_arg_num =  *)
(*   let rec do_prove_princ_for_struct  eqs_id term =  *)
(*     match kind_of_term term with  *)
(*       | Case(_,_,t,_) ->  *)
(* 	  tclTHEN  *)
(* 	    (case_eq t) *)
(* 	    (fun g ->  *)
(* 	       let heq = fresh_id (pf_ids_of_hyps g) heq in  *)
(* 	       tclTHEN  *)
(* 		 (h_intro heq)  *)
(* 		 (fun g' ->  *)
(* 		    let new_t_value =  *)
(* 		      match kind_of_term (pf_type_of g' (mkVar heq)) with  *)
(* 			| App(_,[|_;_;value|]) -> value  *)
(* 			| _ -> anomaly "should have been an equality" *)
(* 		    in *)
(* 		    let type_of_t = pf_type_of g' t in *)
(* 		    let term_as_fun =  *)
(* 		      mkLambda(Anonymous,type_of_t, *)
(* 			       replace_term term (mkRel 1) term *)
(* 			      ) *)
(* 		    in *)
(* 		    let new_term =  *)
(* 		      pf_nf_betaiota g' (mkApp(term_as_fun,new_t_value)) *)
(* 		    in do_prove_princ_for_struct (heq::eqs_id) new_term g' *)
(* 		 ) *)
(* 	    )  *)
(*       | Lambda(n,t,b) -> *)
(* 	  begin *)
(* 	    match kind_of_term( pf_concl g) with *)
(* 	      | Prod _ -> *)
(* 		  tclTHEN *)
(* 		    intro *)
(* 		    (fun g' -> *)
(* 		       let (id,_,_) = pf_last_hyp g' in *)
(* 		       let new_term = pf_nf_betaiota g' (mkApp(term,[|mkVar id|]))  *)
(* 		       in *)
(* 		       do_prove_princ_for_struct do_finalize eqs_id new_term g' *)
(* 		    ) *)
(* 	      | _ -> *)
(* 		  do_finalize eqs_id term  *)
(* 	  end *)
(*       | Cast(t,_,_) -> do_prove_princ_for_struct do_finalize eqs_id t  *)
(*       | Fix _ | CoFix _ -> *)
(* 	  error ( "Anonymous local (co)fixpoints are not handled yet") *)
(*       | LetIn (Name id,v,t,b) -> *)
(* 	  do_prove_princ_for_struct do_finalize (subst1 v b) g *)
(*       | LetIn(Anonymous,_,_,b) -> *)
(* 	  do_prove_princ_for_struct do_finalize (pop  b) g *)
(*       | Prod _ -> assert false *)
(*       |  *)
(*   in  *)
(*   do_prove_princ_for_struct []  *)


    
  
(* let fresh_id_from_name avoid na =  *)
(*   match get_name avoid na with  *)
(*     | Name id -> id  *)
(*     | _ -> assert false  *)

  
(* let fresh_ids (acces_fun: 'a -> name) (l: 'a list)(avoid : identifier list)  =  *)
(*   let rev_ids,avoid =  *)
(*     List.fold_left  *)
(*       (fun (rev_ids,avoid) e ->  *)
(* 	 let old_name = acces_fun e in  *)
(* 	 let new_id = fresh_id_from_name avoid old_name in  *)
(* 	 new_id::rev_ids,new_id::avoid  *)
(*       ) *)
(*       ([],avoid)  *)
(*       l  *)
(*   in  *)
(*   List.rev rev_ids,avoid *)
		      
(* let fst' (x,_,_) = x  *)

(* let prove_princ_for_struct fun_num f_names  nparams : tactic =  *)
(*   fun g ->  *)
(*       let fnames_as_constr = Array.to_list (Array.map mkConst f_names) in *)
(*       let fbody = *)
(* 	match (Global.lookup_constant f_names.(fun_num)).const_body with *)
(* 	  | Some b -> *)
(* 	      let body = force b in *)
(* 	      Tacred.cbv_norm_flags *)
(* 		(Closure.RedFlags.mkflags [Closure.RedFlags.fZETA]) *)
(* 		(Global.env ()) *)
(* 		(Evd.empty) *)
(* 		body *)
(* 	  | None -> error ( "Cannot define a principle over an axiom ") *)
(*       in *)
(*   let rec_arg_num,fbody = *)
(*     match kind_of_term fbody with *)
(*       | Fix((idxs,fix_num),(_,_,ca)) -> *)
(* 	  begin Some (idxs.(fix_num) - nparams),substl (List.rev fnames_as_constr) ca.(fix_num) end *)
(*       | b -> None,fbody *)
(*   in *)
(*   let goal_info = compute_elim_sig (mkRel 0,Rawterm.NoBindings) (pf_concl g) in  *)
(*   let params_ids,to_avoid = fresh_ids fst' goal_info.Tactics.params [] in  *)
(*   let predicates_ids,to_avoid = fresh_ids fst' goal_info.predicates to_avoid in  *)
(*   let branches_ids,to_avoid = fresh_ids fst' goal_info.branches to_avoid in  *)
(*   let first_intros : tactic =  *)
(*     tclMAP h_intro (params_ids@predicates_ids@branches_ids)  *)
(*   in  *)
(*   let fix_id,to_avoid,fix_tac =  *)
(*     match rec_arg_num with *)
(*       | None -> None,to_avoid,first_intros *)
(*       | Some fix_arg_num -> *)
(* 	  let this_fix_id = (fresh_id to_avoid "fix___") in *)
(* 	  Some this_fix_id,this_fix_id::to_avoid, *)
(* 	  tclTHEN  *)
(* 	    first_intros  *)
(* 	    (h_mutual_fix  this_fix_id (fix_arg_num  +1) []) *)
(*   in *)
(*   let ptes_to_fix = *)
(*     List.fold_left2 *)
(*       (fun acc pte fix -> *)
(* 	 Idmap.add pte fix acc *)
(*       ) *)
(*       Idmap.empty *)
(*       predicates_ids *)
(*       [fix_id] *)
(*   in *)
(*   let args_ids,to_avoid = fresh_ids fst' goal_info.args to_avoid in  *)
(*   let (tac_replace,term : tactic*constr) =  *)
(*     let eqs_rhs =   *)
(*       let fbody_with_funs =  *)
(* 	substl (List.rev_map mkConst (Array.to_list f_names)) fbody  *)
(*       in *)
(*       applist (fbody_with_funs, (List.map mkVar (params_ids@args_ids))) *)
(*     in *)
(*     match rec_arg_num with  *)
(*       | Some rec_arg_num ->  *)
(* 	  let eqs_lhs =  *)
(* 	    applist(mkConst f_names.(fun_num),List.map mkVar args_ids)  *)
(* 	  in *)
(* 	  tclTHENS  *)
(* 	    (Equality.replace eqs_lhs eqs_rhs) *)
(* 	    [ *)
(* 	      tclIDTAC (\* The proof continue in this branche *\) *)
(* 	      ; *)
(* 	      (\* Not in this one *\) *)
(* 	      let id = List.nth (List.rev args_ids) (rec_arg_num ) in  *)
(* 	      tclCOMPLETE *)
(* 		(tclTHENSEQ *)
(* 		   [(h_simplest_case (mkVar id)); *)
(* 		    Tactics.intros_reflexivity *)
(* 		   ]) *)
(* 	    ],eqs_rhs *)
(*       | None ->  *)
(* 	  unfold_in_concl  *)
(* 	    (Array.to_list (Array.map (fun x -> [],EvalConstRef x) f_names)),  *)
(* 	  eqs_rhs  *)
(*   in *)
(*   tclTHENSEQ *)
(*     [ *)
(*       fix_tac;  *)
(*       tclMAP h_intro args_ids;  *)
(*       tac_replace;  *)
(*       do_prove_princ_for_struct  *)
(* 	predicates_ids *)
(* 	ptes_to_fix *)
(* 	branches_ids *)
(* 	params_ids *)
(* 	args_ids *)
(* 	rec_arg_num *)
(* 	term *)
(*     ] *)
   






















      
exception Toberemoved_with_rel of int*constr
exception Toberemoved
  
let prov_pte_prefix = "_____PTE"
  
  

let is_pte_id =
  let pref_length = String.length prov_pte_prefix in
  function  id ->
    String.sub (string_of_id id) 0 pref_length = prov_pte_prefix

let compute_new_princ_type_from_rel  replace
    (rel_as_kn:mutual_inductive)  =
  let is_dom c =
    match kind_of_term c with
      | Ind((u,_)) -> u = rel_as_kn
      | Construct((u,_),_) -> u = rel_as_kn
      | _ -> false
  in
  let get_fun_num c =
    match kind_of_term c with
      | Ind(_,num) -> num
      | Construct((_,num),_) -> num
      | _ -> assert false
  in
  let dummy_var = mkVar (id_of_string "________") in
  let mk_replacement i args =
    mkApp(replace.(i),Array.map pop (array_get_start args))
  in
  let rec has_dummy_var t  =
    fold_constr
      (fun b t -> b || (eq_constr t dummy_var) || (has_dummy_var t))
      false
      t
  in
  let rec compute_new_princ_type env pre_princ : types*(constr list) =
(*     let _tim1 = Sys.time() in *)
    let (new_princ_type,_) as res =
      match kind_of_term pre_princ with
	| Rel n ->
	    begin
	      match Environ.lookup_rel n env with
		| _,_,t when is_dom t -> raise Toberemoved
	      | _ -> pre_princ,[]
	    end
	| Prod(x,t,b) ->
	    compute_new_princ_type_for_binder mkProd env x t b
	| Lambda(x,t,b) ->
	    compute_new_princ_type_for_binder mkLambda env x t b
	| Ind _ | Construct _ when is_dom pre_princ -> raise Toberemoved
	| App(f,args) when is_dom f ->
	    let var_to_be_removed = destRel (array_last args) in
	    let num = get_fun_num f in
	    raise (Toberemoved_with_rel (var_to_be_removed,mk_replacement num args))
	| App(f,args) ->
	    let new_args,binders_to_remove =
	      Array.fold_right (compute_new_princ_type_with_acc env)
		args
		([],[])
	    in
	    let new_f,binders_to_remove_from_f = compute_new_princ_type env f in
	    mkApp(new_f,Array.of_list new_args),
	    list_union_eq eq_constr binders_to_remove_from_f binders_to_remove
	| LetIn(x,v,t,b) ->
	    compute_new_princ_type_for_letin env x v t b
	| _ -> pre_princ,[]
    in
(*     if Tacinterp.get_debug () <> Tactic_debug.DebugOff *)
(*     then *)
(*       msgnl (str "compute_new_princ_type for "++ *)
(* 	       pr_lconstr_env env pre_princ ++ *)
(* 	       str" is "++ *)
(* 	       pr_lconstr_env env new_princ_type); *)
      res
	
  and compute_new_princ_type_for_binder bind_fun env x t b =
    begin
      try
	let new_t,binders_to_remove_from_t = compute_new_princ_type env t in
	let new_x : name = get_name (ids_of_context env) x in
	let new_env = Environ.push_rel (x,None,t) env in
	let new_b,binders_to_remove_from_b = compute_new_princ_type new_env b in
	if List.exists (eq_constr (mkRel 1)) binders_to_remove_from_b
	then (pop new_b),filter_map (eq_constr (mkRel 1)) pop binders_to_remove_from_b
	else
	  (
	    bind_fun(new_x,new_t,new_b),
	    list_union_eq
	      eq_constr
	      binders_to_remove_from_t
	      (List.map pop binders_to_remove_from_b)
	  )
	
      with
	| Toberemoved ->
(* 	    msgnl (str "Decl of "++Ppconstr.pr_name x ++ str " is removed "); *)
	    let new_b,binders_to_remove_from_b = compute_new_princ_type  env (substnl [dummy_var] 1 b)  in
	    new_b, List.map pop binders_to_remove_from_b
	| Toberemoved_with_rel (n,c) ->
(* 	    msgnl (str "Decl of "++Ppconstr.pr_name x ++ str " is removed "); *)
	    let new_b,binders_to_remove_from_b = compute_new_princ_type  env (substnl [c] n b)  in
	    new_b, list_add_set_eq eq_constr (mkRel n) (List.map pop binders_to_remove_from_b)
    end
  and compute_new_princ_type_for_letin env x v t b =
    begin
      try
	let new_t,binders_to_remove_from_t = compute_new_princ_type env t in
	let new_v,binders_to_remove_from_v = compute_new_princ_type env v in
	let new_x : name = get_name (ids_of_context env) x in
	let new_env = Environ.push_rel (x,Some v,t) env in
	let new_b,binders_to_remove_from_b = compute_new_princ_type new_env b in
	if List.exists (eq_constr (mkRel 1)) binders_to_remove_from_b
	then (pop new_b),filter_map (eq_constr (mkRel 1)) pop binders_to_remove_from_b
	else
	  (
	    mkLetIn(new_x,new_v,new_t,new_b),
	    list_union_eq
	      eq_constr
	      (list_union_eq eq_constr binders_to_remove_from_t binders_to_remove_from_v)
	      (List.map pop binders_to_remove_from_b)
	  )
	
      with
	| Toberemoved ->
(* 	    msgnl (str "Decl of "++Ppconstr.pr_name x ++ str " is removed "); *)
	    let new_b,binders_to_remove_from_b = compute_new_princ_type  env (substnl [dummy_var] 1 b)  in
	    new_b, List.map pop binders_to_remove_from_b
	| Toberemoved_with_rel (n,c) ->
(* 	    msgnl (str "Decl of "++Ppconstr.pr_name x ++ str " is removed "); *)
	    let new_b,binders_to_remove_from_b = compute_new_princ_type  env (substnl [c] n b)  in
	    new_b, list_add_set_eq eq_constr (mkRel n) (List.map pop binders_to_remove_from_b)
    end
  and  compute_new_princ_type_with_acc env e (c_acc,to_remove_acc)  =
	      let new_e,to_remove_from_e = compute_new_princ_type env e
	      in
	      new_e::c_acc,list_union_eq eq_constr to_remove_from_e to_remove_acc
  in
  compute_new_princ_type

let change_property_sort nparam toSort princ princName =
  let params,concl = decompose_prod_n nparam princ in 
  let hyps,_ = decompose_prod concl in
  let rec f l = 
    match l with
	[] -> assert false
      | (nme,typ)::l' -> 
	  if is_pte_type typ then (nme,typ)::(f l')
	  else [] in
  let args' = List.rev (f (List.rev hyps)) in
  let args  = 
    List.map
      (function nme,typ -> 
	let arg,_ = decompose_prod typ in
	nme, compose_prod arg (mkSort toSort)
      ) args' 
  in
  let nargs = List.length args + nparam in
  let princName' = 
    Nametab.locate_constant 
      (snd (Libnames.qualid_of_reference (Libnames.Ident (Util.dummy_loc,princName))))
  in
  let res = 
    compose_lam 
      params
      (compose_lam args 
	(mkApp (mkConst princName',Array.init nargs
	  (fun i -> mkRel (nargs -i)))))
  in 
  res

let prov_pte_prefix = "_____PTE"

let generate_new_structural_principle 
    interactive_proof
    old_princ new_princ_name funs i proof_tac 
    = 
  let type_sort = (Termops.new_sort_in_family InType) in 
  let f = funs.(i) in 
  (* First we get the type of the old graph principle *)
  let old_princ_type =  (Global.lookup_constant old_princ).const_type
  in
  (* We split it into arguments and conclusion *)
  let old_princ_hyps,old_princ_concl = decompose_prod old_princ_type in 
  (* We split the conclusion which must looks like 
     P x1 .... xn 
  *)
  let p,pargs = decompose_app old_princ_concl in 
  if pargs = [] 
  then errorlabstrm "" (pr_con old_princ ++ str ": Not a valid inductive scheme");
  (* The principle must as least have P as an argument *)
  if old_princ_hyps = [] 
  then errorlabstrm "" (pr_con old_princ ++ str ": Not a valid inductive scheme");
  (* The last argument of old_princ looks like:
     (R_f x1 ... xn)
  *)
  let (_,r_app) = List.hd old_princ_hyps in 
  let rel,rel_args = decompose_app r_app in 
  if rel_args = [] || not (isInd rel) 
  then errorlabstrm "" (pr_con old_princ ++ str ": Not a valid inductive scheme");
  let (mutr_as_kn,r_num) = destInd rel in 
  (* we can the compute the new_principle type *) 
  let mutr_def = Global.lookup_mind mutr_as_kn in 
  let mutr_nparams = mutr_def.mind_nparams in 
  let mutr_params,old_princ_type' = 
    decompose_prod_n mutr_nparams old_princ_type  
  in
  let env_with_param = 
    Environ.push_rel_context 
      (List.map (fun (n,t) -> (n,None,t)) mutr_params) 
      (Global.env ())
  in
  let pte_context,pte_prod,old_princ_type'' =  
    let rec f (acc_context,acc_prod) avoid c =  
      try 
	let (n,t,c') = destProd c  
	in
	if is_pte_type t 
	then 
	  let t' = 
	    let args,concl = decompose_prod t in compose_prod args (mkSort type_sort)
	  in
	  let pte_id = fresh_id avoid prov_pte_prefix in 
	  f ((Name pte_id,None,t)::acc_context,(n,t')::acc_prod) (pte_id::avoid) c'
	else acc_context,acc_prod,c
      with Invalid_argument _ -> acc_context,acc_prod,c
    in
    f ([],[]) (ids_of_context env_with_param) old_princ_type'
  in
  let env_with_ptes = Environ.push_rel_context pte_context env_with_param in
(*   let tim1 = Sys.time ()  in *)
  let new_principle_type,_ = 
    compute_new_princ_type_from_rel 
      (Array.map mkConst funs)
      mutr_as_kn
      env_with_ptes
      old_princ_type''
  in 
(*   let tim2 = Sys.time ()  in *)
(*   Pp.msgnl (str ("Time to compute type: ") ++ str (string_of_float (tim2 -. tim1))) ; *)
  let new_principle_type = 
    compose_prod mutr_params 
      (compose_prod pte_prod new_principle_type)
  in
(*   msgnl (str "new principle type :"++ pr_lconstr  new_principle_type); *)
  let new_princ_name = 
    match new_princ_name with 
      | Some (id) -> id
      | None -> 
	  let id_of_f = id_of_label (con_label f) in
	  Indrec.make_elimination_ident id_of_f (family_of_sort type_sort)
  in
  let hook _ _  = 
    let id_of_f = id_of_label (con_label f) in
    let register_with_sort fam_sort = 
      let s = Termops.new_sort_in_family  fam_sort in 
      let name = Indrec.make_elimination_ident id_of_f fam_sort in 
      let value = 
	change_property_sort mutr_nparams s new_principle_type new_princ_name 
      in 
      let ce = 
	{ const_entry_body = value;
	  const_entry_type = None;
	  const_entry_opaque = false;
	  const_entry_boxed = Options.boxed_definitions() 
	}
      in
      ignore(
	Declare.declare_constant 
	  name 
	  (Entries.DefinitionEntry ce, 
	   Decl_kinds.IsDefinition (Decl_kinds.Scheme)
	  )
      )
    in
    register_with_sort InProp;
    register_with_sort InSet
  in
  begin
    Command.start_proof 
      new_princ_name
      (Decl_kinds.Global,(Decl_kinds.Proof Decl_kinds.Theorem)) 
      new_principle_type
      hook
    ;
    try 
(*       let tim1 = Sys.time ()  in *)
      Pfedit.by  (proof_tac mutr_nparams);
(*       let tim2 = Sys.time ()  in *)
(* Pp.msgnl (str ("Time to compute proof: ") ++ str (string_of_float (tim2 -. tim1))); *)

      if Tacinterp.get_debug () = Tactic_debug.DebugOff && not interactive_proof 
      then
	Options.silently Command.save_named false;


(*       let tim3 = Sys.time ()  in *)
(* Pp.msgnl (str ("Time to save proof: ") ++ str (string_of_float (tim3 -. tim2))); *)

    with
      | e ->
	  if Tacinterp.get_debug () = Tactic_debug.DebugOff 
	  then  begin Vernacentries.interp (Vernacexpr.VernacAbort None);raise e end
	  else 	 
	    msg_warning
	      (
		Cerrors.explain_exn e
	      )

  end





