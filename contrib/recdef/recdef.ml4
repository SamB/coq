(************************************************************************)
(*  v      *   The Coq Proof Assistant  /  The Coq Development Team     *)
(* <O___,, * CNRS-Ecole Polytechnique-INRIA Futurs-Universite Paris Sud *)
(*   \VV/  **************************************************************)
(*    //   *      This file is distributed under the terms of the       *)
(*         *       GNU Lesser General Public License Version 2.1        *)
(************************************************************************)

(*i camlp4deps: "parsing/grammar.cma" i*)

open Term
open Termops
open Environ
open Declarations
open Entries
open Pp
open Names
open Libnames
open Nameops
open Util
open Closure
open RedFlags
open Tacticals
open Typing
open Tacmach
open Tactics
open Nametab
open Declare
open Decl_kinds
open Tacred
open Proof_type
open Vernacinterp
open Pfedit
open Topconstr
open Rawterm
open Pretyping
open Safe_typing
open Constrintern
open Hiddentac

open Equality
open Auto
open Eauto

open Genarg


let h_intros l = 
  tclMAP h_intro l

let do_observe_tac s tac g =
  let goal = begin try (Printer.pr_goal (sig_it g)) with _ -> assert false end in
 try let v = tac g in msgnl (goal ++ fnl () ++ (str s)++(str " ")++(str "finished")); v
 with e ->
   msgnl (str "observation "++str s++str " raised exception " ++ 	Cerrors.explain_exn e ++ str "on goal " ++ goal ); raise e;;


let observe_tac s tac g = tac g


let hyp_ids = List.map id_of_string
    ["x";"v";"k";"def";"p";"h";"n";"h'"; "anonymous"; "teq"; "rec_res";
     "hspec";"heq"; "hrec"; "hex"; "teq"; "pmax";"hle"];;

let rec nthtl = function
    l, 0 -> l  | _::tl, n -> nthtl (tl, n-1) | [], _ -> [];;

let hyp_id n l = List.nth l n;;

let (x_id:identifier) = hyp_id 0 hyp_ids;;
let (v_id:identifier) = hyp_id 1 hyp_ids;;
let (k_id:identifier) = hyp_id 2 hyp_ids;;
let (def_id:identifier) = hyp_id 3 hyp_ids;;
let (p_id:identifier) = hyp_id 4 hyp_ids;;
let (h_id:identifier) = hyp_id 5 hyp_ids;;
let (n_id:identifier) = hyp_id 6 hyp_ids;;
let (h'_id:identifier) = hyp_id 7 hyp_ids;;
let (ano_id:identifier) = hyp_id 8 hyp_ids;;
let (rec_res_id:identifier) = hyp_id 10 hyp_ids;;
let (hspec_id:identifier) = hyp_id 11 hyp_ids;;
let (heq_id:identifier) = hyp_id 12 hyp_ids;;
let (hrec_id:identifier) = hyp_id 13 hyp_ids;;
let (hex_id:identifier) = hyp_id 14 hyp_ids;;
let (teq_id:identifier) = hyp_id 15 hyp_ids;;
let (pmax_id:identifier) = hyp_id 16 hyp_ids;;
let (hle_id:identifier) = hyp_id 17 hyp_ids;;

let message s = if Options.is_verbose () then msgnl(str s);;

let def_of_const t =
   match (kind_of_term t) with
    Const sp -> 
      (try (match (Global.lookup_constant sp) with
             {const_body=Some c} -> Declarations.force c
	     |_ -> assert false)
       with _ -> anomaly ("Cannot find definition of constant "^(string_of_id (id_of_label (con_label sp)))))
    |_ -> assert false

let type_of_const t =
   match (kind_of_term t) with
    Const sp -> 
      (Global.lookup_constant sp).const_type
    |_ -> assert false

let arg_type t =
  match kind_of_term (def_of_const t) with
      Lambda(a,b,c) -> b
    | _ -> assert false;;

let evaluable_of_global_reference r =
  match r with 
      ConstRef sp -> EvalConstRef sp
    | VarRef id -> EvalVarRef id
    | _ -> assert false;;
  
let rec (find_call_occs:
	   constr -> constr -> (constr list ->constr)*(constr  list list)) =
 fun f expr ->
  match (kind_of_term expr) with
    App (g, args) when g = f -> 
      (* For now we suppose that the function takes only one argument. *)
      (fun l -> List.hd l), [Array.to_list args]
  | App (g, args) ->
     let (largs: constr list) = Array.to_list args in
     let rec find_aux = function
	 []    -> (fun x -> []), []
       | a::tl ->
         (match find_aux tl with
          (cf, ((arg1::args) as opt_args)) -> 
           (match find_call_occs f a with
             cf2, (_ :: _ as other_args) ->
	       let len1 = List.length other_args in
                 (fun l ->
                   cf2 l::(cf (nthtl(l,len1)))), other_args@opt_args
           | _, [] -> (fun x -> a::cf x), opt_args)
	 | _, [] ->
	   (match find_call_occs f a with
	     cf, (arg1::args) -> (fun l -> cf l::tl), (arg1::args)
	   | _, [] -> (fun x -> a::tl), [])) in
     begin
       match (find_aux largs) with
	   cf, [] -> (fun l -> mkApp(g, args)), []
	 | cf, args ->
	     (fun l -> mkApp (g, Array.of_list (cf l))), args
     end
  | Rel(_) -> error "find_call_occs : Rel"
  | Var(id) -> (fun l -> expr), []
  | Meta(_) -> error "find_call_occs : Meta"
  | Evar(_) -> error "find_call_occs : Evar"
  | Sort(_)  -> error "find_call_occs : Sort"
  | Cast(_,_,_) -> error "find_call_occs : cast"
  | Prod(_,_,_) -> error "find_call_occs : Prod"
  | Lambda(_,_,_) -> error "find_call_occs : Lambda"
  | LetIn(_,_,_,_) -> error "find_call_occs : let in"
  | Const(_) -> (fun l -> expr), []
  | Ind(_) -> (fun l -> expr), []
  | Construct (_, _) -> (fun l -> expr), []
  | Case(i,t,a,r) ->
      (match find_call_occs f a with
	cf, (arg1::args) -> (fun l -> mkCase(i, t, (cf l), r)),(arg1::args)
      | _ -> (fun l -> mkCase(i, t, a, r)),[])
  | Fix(_) -> error "find_call_occs : Fix"
  | CoFix(_) -> error "find_call_occs : CoFix";;

let coq_constant s =
  Coqlib.gen_constant_in_modules "RecursiveDefinition" 
    (Coqlib.init_modules @ Coqlib.arith_modules) s;;

let constant sl s =
  constr_of_reference
    (locate (make_qualid(Names.make_dirpath 
			   (List.map id_of_string (List.rev sl)))
	       (id_of_string s)));;

let find_reference sl s =
    (locate (make_qualid(Names.make_dirpath 
			   (List.map id_of_string (List.rev sl)))
	       (id_of_string s)));;

let delayed_force f = f ()

let le_lt_SS = function () -> (constant ["Recdef"] "le_lt_SS")
let le_lt_n_Sm = function () -> (coq_constant "le_lt_n_Sm")

let le_trans = function () -> (coq_constant "le_trans")
let le_lt_trans = function () -> (coq_constant "le_lt_trans")
let lt_S_n = function () -> (coq_constant "lt_S_n")
let le_n = function () -> (coq_constant "le_n")
let refl_equal = function () -> (coq_constant "refl_equal")
let eq = function () -> (coq_constant "eq")
let ex = function () -> (coq_constant "ex")
let coq_sig_ref = function () -> (find_reference ["Coq";"Init";"Specif"] "sig")
let coq_sig = function () -> (coq_constant "sig")
let coq_O = function () -> (coq_constant "O")
let coq_S = function () -> (coq_constant "S")

let gt_antirefl = function () -> (coq_constant "gt_irrefl")
let lt_n_O = function () -> (coq_constant "lt_n_O")
let lt_n_Sn = function () -> (coq_constant "lt_n_Sn")

let f_equal = function () -> (coq_constant "f_equal")
let well_founded_induction = function () -> (coq_constant "well_founded_induction")
let well_founded = function () -> (coq_constant "well_founded")
let acc_rel = function () -> (coq_constant "Acc")
let acc_inv_id = function () -> (coq_constant "Acc_inv")
let well_founded_ltof = function () ->  (Coqlib.coq_constant "" ["Arith";"Wf_nat"] "well_founded_ltof")
let iter_ref = function () -> (try find_reference ["Recdef"] "iter" with Not_found -> error "module Recdef not loaded")
let max_ref = function () -> (find_reference ["Recdef"] "max")
let iter = function () -> (constr_of_reference (delayed_force iter_ref))
let max_constr = function () -> (constr_of_reference (delayed_force max_ref))

let ltof_ref = function  () -> (find_reference ["Coq";"Arith";"Wf_nat"] "ltof")

(* These are specific to experiments in nat with lt as well_founded_relation, *)
(*    but this should be made more general. *)
let nat = function () -> (coq_constant "nat")
let lt = function () -> (coq_constant "lt")

let  mkCaseEq a  : tactic =
     (fun g ->
(* commentaire de Yves: on pourra avoir des problemes si
   a n'est pas bien type dans l'environnement du but *)
       let type_of_a = pf_type_of g a in
       (tclTHEN (generalize [mkApp(delayed_force refl_equal, [| type_of_a; a|])])
	  (tclTHEN 
	     (fun g2 ->
		change_in_concl None 
		  (pattern_occs [([2], a)] (pf_env g2) Evd.empty (pf_concl g2))
		  g2)
	     (simplest_case a))) g);;

let rec  mk_intros_and_continue (extra_eqn:bool)
    cont_function (eqs:constr list) (expr:constr) g =
  let ids = pf_ids_of_hyps g in
  match kind_of_term expr with
    | Lambda (n, _, b) -> 
     	let n1 = 
	  match n with
      	      Name x -> x
            | Anonymous -> ano_id
	in
     	let new_n = next_global_ident_away true n1 ids in
	  tclTHEN (h_intro new_n)
	    (mk_intros_and_continue extra_eqn cont_function eqs 
	       (subst1 (mkVar new_n) b)) g
    | _ -> 
 	if extra_eqn then
	  let teq = next_global_ident_away true teq_id ids in
	    tclTHEN (h_intro teq)	
	      (cont_function (mkVar teq::eqs) expr) g
	else
	  cont_function eqs expr g

let const_of_ref = function
    ConstRef kn -> kn
  | _ -> anomaly "ConstRef expected"

let simpl_iter () =
  reduce 
    (Lazy 
       {rBeta=true;rIota=true;rZeta= true; rDelta=false;
        rConst = [ EvalConstRef (const_of_ref (delayed_force iter_ref))]})
    onConcl
    
let tclUSER is_mes l g = 
  let b,l = 
    match l with 
	None -> true,[]
      | Some l -> false,l
  in
  tclTHENSEQ 
    [
      (h_clear b l);
      if is_mes 
      then unfold_in_concl [([], evaluable_of_global_reference (delayed_force ltof_ref))]
      else tclIDTAC
    ]
    g
    
    
let list_rewrite (rev:bool) (eqs: constr list) =
  tclREPEAT
    (List.fold_right
       (fun eq i -> tclORELSE (rewriteLR eq) i)
       (if rev then (List.rev eqs) else eqs) (tclFAIL 0 (mt())));;

let base_leaf_terminate (func:global_reference) eqs expr =
(*  let _ = msgnl (str "entering base_leaf") in *)
  (fun g ->
     let ids = pf_ids_of_hyps g in
     let k' = next_global_ident_away true k_id ids in
     let h = next_global_ident_away true h_id (k'::ids) in
       tclTHENLIST [observe_tac "first split" (split (ImplicitBindings [expr]));
		    observe_tac "second split" (split (ImplicitBindings [delayed_force coq_O]));
		    observe_tac "intro k" (h_intro k');
                    observe_tac "case on k" 
		      (tclTHENS 
			 (simplest_case (mkVar k'))
			 [(tclTHEN (h_intro h) 
		     	     (tclTHEN (simplest_elim 
					 (mkApp (delayed_force gt_antirefl,
						 [| delayed_force coq_O |])))
				default_auto)); tclIDTAC ]);
                    intros;

		    simpl_iter();
		    unfold_constr func;
                    list_rewrite true eqs;
		    default_auto ] g);;

(* La fonction est donnee en premier argument a la 
   fonctionnelle suivie d'autres Lambdas et de Case ...
   Pour recuperer la fonction f a partir de la 
   fonctionnelle *)
let get_f foncl = 
  match (kind_of_term (def_of_const foncl)) with
      Lambda (Name f, _, _) -> f  
    |_ -> error "la fonctionnelle est mal definie";;


let rec compute_le_proofs = function
    [] -> assumption
  | a::tl ->
      tclORELSE assumption 
	(tclTHENS
	   (apply_with_bindings
	      (delayed_force le_trans,
	       ExplicitBindings[dummy_loc,NamedHyp(id_of_string "m"),a]))
	   [compute_le_proofs tl; 
            tclORELSE (apply (delayed_force le_n)) assumption])

let make_lt_proof pmax le_proof =
  tclTHENS
    (apply_with_bindings
       (delayed_force le_lt_trans,
	ExplicitBindings[dummy_loc,NamedHyp(id_of_string "m"), pmax]))
    [compute_le_proofs le_proof; 
     tclTHENLIST[apply (delayed_force lt_S_n); default_full_auto]];;

let rec list_cond_rewrite k def pmax cond_eqs le_proofs =
  match cond_eqs with
    [] -> tclIDTAC
  | eq::eqs ->
      tclTHENS
	(general_rewrite_bindings false
	 (mkVar eq,
	    ExplicitBindings[dummy_loc,   NamedHyp k_id, mkVar k;
			     dummy_loc,   NamedHyp def_id, mkVar def]))
	[list_cond_rewrite k def pmax eqs le_proofs;
         make_lt_proof pmax le_proofs];;


let rec introduce_all_equalities func eqs values specs bound le_proofs 
    cond_eqs =
  match specs with
    [] -> 
      fun g ->
	let ids = pf_ids_of_hyps g in
	let s_max = mkApp(delayed_force coq_S, [|bound|]) in
	let k = next_global_ident_away true k_id ids in
        let ids = k::ids in
	let h' = next_global_ident_away true (h'_id) ids in
        let ids = h'::ids in
	let def = next_global_ident_away true def_id ids in
	tclTHENLIST
	  [observe_tac "introduce_all_equalities_final split" (split (ImplicitBindings [s_max]));
	   observe_tac "introduce_all_equalities_final intro k" (h_intro  k);
	   tclTHENS
	     (observe_tac "introduce_all_equalities_final case k" (simplest_case (mkVar k)))
	     [tclTHENLIST[h_intro h';
			  simplest_elim(mkApp(delayed_force lt_n_O,[|s_max|]));
			  default_full_auto]; tclIDTAC];
	   observe_tac "clearing k " (clear [k]);
	   h_intros [k;h';def];
	   simpl_iter();
	   unfold_in_concl[([1],evaluable_of_global_reference func)];
	   list_rewrite true eqs;
           list_cond_rewrite  k def bound cond_eqs le_proofs;
	   apply (delayed_force refl_equal)] g
  | spec1::specs ->
      fun g ->
	let ids = ids_of_named_context (pf_hyps g) in
	let p = next_global_ident_away true p_id ids in
        let ids = p::ids in
	let pmax = next_global_ident_away true pmax_id ids in
        let ids = pmax::ids in
	let hle1 = next_global_ident_away true hle_id ids in
        let ids = hle1::ids in
	let hle2 = next_global_ident_away true  hle_id ids in
	let ids = hle2::ids in
	let heq = next_global_ident_away true heq_id ids in
	tclTHENLIST
	  [simplest_elim (mkVar spec1);
	   list_rewrite true eqs;
	   h_intros [p; heq];
	   simplest_elim (mkApp(delayed_force max_constr, [| bound; mkVar p|]));
	   h_intros [pmax; hle1; hle2];
	   introduce_all_equalities func eqs values specs 
	     (mkVar pmax) ((mkVar pmax)::le_proofs)
	     (heq::cond_eqs)] g;;
    
let string_match  s =
 try 
  for i = 0 to 3  do
    if String.get s i <> String.get "Acc_" i then failwith ""
  done;
 with Invalid_argument _ -> failwith ""
	  
let retrieve_acc_var g = 
  (* Julien: I don't like this version .... *) 
  let hyps = pf_ids_of_hyps g  in 
  map_succeed 
    (fun id -> 
       try 
	 string_match (string_of_id id);
	 id
       with _ -> failwith "")
    hyps 

let rec introduce_all_values is_mes acc_inv func context_fn
    eqs  hrec args values specs =
    (match args with
    [] -> 
      tclTHENLIST
	[split(ImplicitBindings
		 [context_fn (List.map mkVar (List.rev values))]);
	 observe_tac "introduce_all_equalities" (introduce_all_equalities func eqs
	   (List.rev values) (List.rev specs) (delayed_force coq_O) [] [])]
  | arg::args ->
      (fun g ->
	let ids = ids_of_named_context (pf_hyps g) in
	let rec_res = next_global_ident_away true rec_res_id ids in
        let ids = rec_res::ids in
	let hspec = next_global_ident_away true hspec_id ids in
	let tac = introduce_all_values is_mes acc_inv func context_fn eqs 
	  hrec args
	  (rec_res::values)(hspec::specs) in
	(tclTHENS
	   (simplest_elim (mkApp(mkVar hrec, Array.of_list arg)))
	   [tclTHENLIST [h_intros [rec_res; hspec];
			 tac]; 
	    (tclTHENS
		 (apply (Lazy.force acc_inv))
		 [ h_assumption
		 ;
		   (fun g ->  
		      tclUSER
			is_mes
			(Some (hrec::hspec::(retrieve_acc_var g)@specs))
			g
		   )
		 ]
	    )
	   ]) g)
	
    )
 
	   
let rec_leaf_terminate is_mes acc_inv hrec (func:global_reference) eqs expr =
  match find_call_occs (mkVar (get_f (constr_of_reference func))) expr with
  | context_fn, args ->
      observe_tac "introduce_all_values" 
	(introduce_all_values is_mes acc_inv func context_fn eqs  hrec args  [] [])

(* 
let rec proveterminate is_mes acc_inv (hrec:identifier)  
  (f_constr:constr) (func:global_reference) (eqs:constr list) (expr:constr)  =
try
(*  let _ = msgnl (str "entering proveterminate") in *)
  let v =
  match (kind_of_term expr) with
      Case (_, t, a, l) -> 
	(match find_call_occs f_constr a with
	     _,[] ->
      	       tclTHENS (fun g ->
(* 			   let _ = msgnl(str "entering mkCaseEq") in *)
			   let v = (mkCaseEq a) g in 
(* 			   let _ = msgnl (str "exiting mkCaseEq") in *)
			   v
			)
   	         (List.map (mk_intros_and_continue true
                              (proveterminate is_mes acc_inv hrec f_constr func)
                              eqs)
	            (Array.to_list l))
	   | _, _::_ -> 
	       (
		 match find_call_occs  f_constr expr with
	     	     _,[] -> observe_tac "base_leaf" (base_leaf func eqs expr)
		   | _, _:: _ -> 
		       observe_tac "rec_leaf" (rec_leaf is_mes acc_inv hrec  func eqs expr)
	       )
	)
    | _ ->  (match find_call_occs  f_constr expr with
	     	_,[] -> 
		  (try 
		    observe_tac "base_leaf" (base_leaf func eqs expr)
		   with e -> (msgerrnl (str "failure in base case");raise e ))
	       | _, _::_ -> 
		   observe_tac "rec_leaf" (rec_leaf is_mes acc_inv hrec  func eqs expr)
	 ) in
  (*  let _ = msgnl(str "exiting proveterminate") in *)
  v
with e -> 
  msgerrnl(str "failure in proveterminate"); 
  raise e
*)
let proveterminate is_mes acc_inv (hrec:identifier)  
  (f_constr:constr) (func:global_reference) base_leaf rec_leaf = 
  let rec proveterminate (eqs:constr list) (expr:constr)  =
    try
      (*  let _ = msgnl (str "entering proveterminate") in *)
      let v =
	match (kind_of_term expr) with
	    Case (_, t, a, l) -> 
	      (match find_call_occs f_constr a with
		   _,[] ->
      		     tclTHENS 
		       (fun g ->
			  (* let _ = msgnl(str "entering mkCaseEq") in *)
			  let v = (mkCaseEq a) g in 
			  (* let _ = msgnl (str "exiting mkCaseEq") in *)
			  v
		       )
   	               (List.map 
			  (mk_intros_and_continue true proveterminate eqs)
			  (Array.to_list l)
		       )
		 | _, _::_ -> 
		     (
		       match find_call_occs  f_constr expr with
	     		   _,[] -> observe_tac "base_leaf" (base_leaf func eqs expr)
			 | _, _:: _ -> 
			     observe_tac "rec_leaf" 
			       (rec_leaf is_mes acc_inv hrec  func eqs expr)
		     )
	      )
	  | _ ->  (match find_call_occs  f_constr expr with
	     	       _,[] -> 
			 (try 
			    observe_tac "base_leaf" (base_leaf func eqs expr)
			  with e -> 
			    (msgerrnl (str "failure in base case");raise e ))
		     | _, _::_ -> 
			 observe_tac "rec_leaf" 
			   (rec_leaf is_mes acc_inv hrec  func eqs expr)
		  ) in
      (*  let _ = msgnl(str "exiting proveterminate") in *)
      v
    with e -> 
      msgerrnl(str "failure in proveterminate"); 
      raise e
  in 
  proveterminate 

let hyp_terminates func = 
  let a_arrow_b = arg_type (constr_of_reference func) in 
  let rev_args,b = decompose_prod a_arrow_b in 
  let left = 
    mkApp(delayed_force iter, 
	  Array.of_list 
	    (lift 5 a_arrow_b:: mkRel 3::
	       constr_of_reference func::mkRel 1::
	       List.rev (list_map_i (fun i _ -> mkRel (6+i)) 0 rev_args)
	    )
	 )
  in
  let right = mkRel 5 in 
  let equality = mkApp(delayed_force eq, [|lift 5 b; left; right|]) in
  let result = (mkProd ((Name def_id) , lift 4 a_arrow_b, equality)) in
  let cond = mkApp(delayed_force lt, [|(mkRel 2); (mkRel 1)|]) in
  let nb_iter =
    mkApp(delayed_force ex,
	  [|delayed_force nat;
	    (mkLambda 
	       (Name
		  p_id,
		  delayed_force nat, 
		  (mkProd (Name k_id, delayed_force nat, 
			   mkArrow cond result))))|])in
  let value = mkApp(delayed_force coq_sig, 
		    [|b;
		      (mkLambda (Name v_id, b, nb_iter))|]) in
  compose_prod rev_args value
	     


let tclUSER_if_not_mes is_mes = 
  if is_mes 
  then 
    tclCOMPLETE (h_apply (delayed_force well_founded_ltof,Rawterm.NoBindings))
  else tclUSER is_mes None

let start is_mes input_type ids args_id relation rec_arg_num rec_arg_id tac : tactic = 
  begin 
    fun g -> 
      let nargs = List.length args_id in
      let pre_rec_args = 
	List.rev_map
	  mkVar (fst (list_chop (rec_arg_num - 1) args_id)) 
      in 
      let relation = substl pre_rec_args relation in 
      let input_type = substl pre_rec_args input_type in 
      let wf_thm = next_global_ident_away true (id_of_string ("wf_R")) ids in 
      let wf_rec_arg = 
	next_global_ident_away true 
	  (id_of_string ("Acc_"^(string_of_id rec_arg_id)))
	  (wf_thm::ids) 
      in 
      let hrec = next_global_ident_away true hrec_id (wf_rec_arg::wf_thm::ids) in 
      let acc_inv = 
	  lazy (
	    mkApp (
	      delayed_force acc_inv_id,
	      [|input_type;relation;mkVar rec_arg_id|]
	    )
	  )
      in
      tclTHEN
	(h_intros args_id)
	(tclTHENS
	   (observe_tac 
	      "first assert" 
	      (assert_tac 
		 true (* the assert thm is in first subgoal *)
		 (Name wf_rec_arg) 
		 (mkApp (delayed_force acc_rel,
			 [|input_type;relation;mkVar rec_arg_id|])
		 )
	      )
	   )
	   [
	     (* accesibility proof *) 
	     tclTHENS 
	       (observe_tac 
		  "second assert" 
		  (assert_tac 
		     true 
		     (Name wf_thm)
		     (mkApp (delayed_force well_founded,[|input_type;relation|]))
		  )
	       )
	       [ 
		 (* interactive proof of the well_foundness of the relation *) 
		 tclUSER_if_not_mes is_mes;
		 (* well_foundness -> Acc for any element *)
		 observe_tac 
		   "apply wf_thm" 
		   (h_apply ((mkApp(mkVar wf_thm,
				    [|mkVar rec_arg_id |])),Rawterm.NoBindings)
		   )
	       ]
	     ;
	     (* rest of the proof *)
	     tclTHENSEQ 
	       [observe_tac "generalize" 
		  (onNLastHyps (nargs+1)
		     (fun (id,_,_) -> 
			tclTHEN (generalize [mkVar id]) (h_clear false [id])
		     ))
	       ;
		observe_tac "h_fix" (h_fix (Some hrec) (nargs+1));
		h_intros args_id;
		h_intro wf_rec_arg;
		observe_tac "tac" (tac hrec acc_inv)
	       ]
	   ]
	) g  
  end



let rec instantiate_lambda t l = 
  match l with
  | [] -> t
  | a::l -> 
      let (bound_name, _, body) = destLambda t in
      instantiate_lambda (subst1 a body) l
;;


let whole_start is_mes func input_type relation rec_arg_num  : tactic = 
  begin 
    fun g -> 
      let ids = ids_of_named_context (pf_hyps g) in
      let func_body = (def_of_const (constr_of_reference func)) in
      let (f_name, _, body1) = destLambda func_body in
      let f_id =
	match f_name with
	  | Name f_id -> next_global_ident_away true f_id ids
	  | Anonymous -> assert false 
      in
      let n_names_types,_ = decompose_lam body1 in 
      let n_ids,ids = 
	List.fold_left 
	  (fun (n_ids,ids) (n_name,_) -> 
	     match n_name with 
	       | Name id -> 
		   let n_id = next_global_ident_away true id ids in 
		   n_id::n_ids,n_id::ids
	       | _ -> assert false
	  )
	  ([],(f_id::ids))
	  n_names_types
      in
      let rec_arg_id = List.nth n_ids (rec_arg_num - 1) in
      let expr = instantiate_lambda func_body (mkVar f_id::(List.map mkVar n_ids)) in 
      start 
	is_mes
	input_type
	ids
	n_ids
	relation 
	rec_arg_num
	rec_arg_id
	(fun hrec acc_inv g ->  
           (proveterminate 
	      is_mes
	      acc_inv 
	      hrec
	      (mkVar f_id)
	      func
	      base_leaf_terminate 
	      rec_leaf_terminate
	      []
	      expr
	   )
	     g 
	)
	g 
  end



let com_terminate is_mes fonctional_ref input_type relation rec_arg_num
    thm_name hook =
  let (evmap, env) = Command.get_current_context() in
  start_proof thm_name
    (Global, Proof Lemma) (Environ.named_context_val env)
    (hyp_terminates fonctional_ref) hook;
  by (observe_tac "whole_start" (whole_start is_mes fonctional_ref
	input_type relation rec_arg_num ))
    

let ind_of_ref = function 
  | IndRef (ind,i) -> (ind,i)
  | _ -> anomaly "IndRef expected"

let (value_f:constr list -> global_reference -> constr) =
  fun al fterm ->
    let d0 = dummy_loc in 
    let rev_x_id_l =  
      (
	List.fold_left 
	  (fun x_id_l _ -> 
	     let x_id = next_global_ident_away true x_id x_id_l in 
	     x_id::x_id_l
	  )
	  []
	  al
      )
    in
    let fun_body = 
      RCases
	(d0,None,
	 [RApp(d0, RRef(d0,fterm), List.rev_map (fun x_id -> RVar(d0, x_id)) rev_x_id_l),
	  (Anonymous,None)],
	 [d0, [v_id], [PatCstr(d0,(ind_of_ref 
				     (delayed_force coq_sig_ref),1),
			       [PatVar(d0, Name v_id);
				PatVar(d0, Anonymous)],
			       Anonymous)],
	  RVar(d0,v_id)])
    in
    let value =
      List.fold_left2 
	(fun acc x_id a -> 
	   RLambda
      	     (d0, Name x_id, RDynamic(d0, constr_in a),
	      acc
	     ) 
	)
	fun_body
	rev_x_id_l
	(List.rev al)
    in
    understand Evd.empty (Global.env()) value;;

let (declare_fun : identifier -> logical_kind -> constr -> global_reference) =
  fun f_id kind value ->
    let ce = {const_entry_body = value;
	      const_entry_type = None;
	      const_entry_opaque = false;
              const_entry_boxed = true} in
      ConstRef(declare_constant f_id (DefinitionEntry ce, kind));;

let (declare_f : identifier -> logical_kind -> constr list -> global_reference -> global_reference) =
  fun f_id kind input_type fterm_ref ->
    declare_fun f_id kind (value_f input_type fterm_ref);;

let start_equation (f:global_reference) (term_f:global_reference) 
  (cont_tactic:identifier list -> tactic) g =
  let ids = pf_ids_of_hyps g in
  let terminate_constr = constr_of_reference term_f in 
  let nargs = nb_prod (type_of_const terminate_constr) in 
  let x = 
    let rec f ids n =
      if n = 0 
      then []
      else 
	let x = next_global_ident_away true x_id ids in 
	x::f (x::ids) (n-1)
    in
    f ids nargs
  in
  tclTHENLIST [
    h_intros x;
    unfold_constr f;
    simplest_case (mkApp (terminate_constr, Array.of_list (List.map mkVar x)));
    cont_tactic x] g
;;

let base_leaf_eq func eqs f_id g =
  let ids = pf_ids_of_hyps g in
  let k = next_global_ident_away true k_id ids in
  let p = next_global_ident_away true p_id (k::ids) in
  let v = next_global_ident_away true v_id (p::k::ids) in
  let heq = next_global_ident_away true heq_id (v::p::k::ids) in
  let heq1 = next_global_ident_away true heq_id (heq::v::p::k::ids) in
  let hex = next_global_ident_away true hex_id (heq1::heq::v::p::k::ids) in
    tclTHENLIST [
      h_intros [v; hex]; 
      simplest_elim (mkVar hex);
      h_intros [p;heq1];
      tclTRY
	(rewriteRL 
	   (mkApp(mkVar heq1, 
		  [|mkApp (delayed_force coq_S, [|mkVar p|]);
		    mkApp(delayed_force lt_n_Sn, [|mkVar p|]); f_id|])));
      simpl_iter();
      unfold_in_concl [([1], evaluable_of_global_reference func)];
      list_rewrite true eqs;
      apply (delayed_force refl_equal)] g;;

let f_S t = mkApp(delayed_force coq_S, [|t|]);;

let rec introduce_all_values_eq  cont_tac functional termine 
    f p heq1 pmax bounds le_proofs eqs ids =
  function
      [] ->
	tclTHENLIST
	  [tclTHENS
	     (general_rewrite_bindings false
		(mkVar heq1,
		 ExplicitBindings[dummy_loc,NamedHyp k_id,
				  f_S(f_S(mkVar pmax));
				  dummy_loc,NamedHyp def_id,
				  f]))
	     [tclTHENLIST
		[simpl_iter();
		 unfold_constr (reference_of_constr functional);
		 list_rewrite true eqs; cont_tac pmax le_proofs];
	      tclTHENLIST[apply (delayed_force le_lt_SS);
			compute_le_proofs le_proofs]]]
    | arg::args ->
	let v' = next_global_ident_away true v_id ids in
        let ids = v'::ids in
	let hex' = next_global_ident_away true hex_id ids in
        let ids = hex'::ids in
	let p' = next_global_ident_away true p_id ids in
        let ids = p'::ids in
	let new_pmax = next_global_ident_away true pmax_id ids in
        let ids = pmax::ids in
	let hle1 = next_global_ident_away true hle_id ids in
        let ids = hle1::ids in
	let hle2 = next_global_ident_away true hle_id ids in
        let ids = hle2::ids in
	let heq = next_global_ident_away true heq_id ids in
        let ids = heq::ids in
	let heq2 = next_global_ident_away true heq_id ids in
        let ids = heq2::ids in
	tclTHENLIST
	  [mkCaseEq(mkApp(termine, Array.of_list arg));
	   h_intros [v'; hex'];
	   simplest_elim(mkVar hex');
	   h_intros [p'];
	   simplest_elim(mkApp(delayed_force max_constr, [|mkVar pmax;
							mkVar p'|]));
	   h_intros [new_pmax;hle1;hle2];
           introduce_all_values_eq 
              (fun pmax' le_proofs'->
		tclTHENLIST
		  [cont_tac pmax' le_proofs';
		   h_intros [heq;heq2];
		   rewriteLR (mkVar heq2);
		   tclTHENS
		     (general_rewrite_bindings false
			(mkVar heq,
			 ExplicitBindings
			   [dummy_loc, NamedHyp k_id,
			    f_S(mkVar pmax');
			    dummy_loc, NamedHyp def_id, f]))
		     [tclIDTAC;
		      tclTHENLIST
			[apply (delayed_force le_lt_n_Sm);
			 compute_le_proofs le_proofs']]])
	     functional termine f p heq1 new_pmax
	     (p'::bounds)((mkVar pmax)::le_proofs) eqs
             (heq2::heq::hle2::hle1::new_pmax::p'::hex'::v'::ids) args]
  

let rec_leaf_eq termine f ids functional eqs expr fn args =
  let p = next_global_ident_away true p_id ids in
  let ids = p::ids in
  let v = next_global_ident_away true v_id ids in
  let ids = v::ids in
  let hex = next_global_ident_away true hex_id ids in
  let ids = hex::ids in
  let heq1 = next_global_ident_away true heq_id ids in
  let ids = heq1::ids in
  let hle1 = next_global_ident_away true hle_id ids in
  let ids = hle1::ids in
    tclTHENLIST
      [h_intros [v;hex];
       simplest_elim (mkVar hex);
       h_intros [p;heq1];
       generalize [mkApp(delayed_force le_n,[|mkVar p|])];
       h_intros [hle1];
       introduce_all_values_eq
	 (fun _ _ -> tclIDTAC)
	 functional termine f p heq1 p [] [] eqs ids args;
       apply (delayed_force refl_equal)]

let rec prove_eq  (termine:constr) (f:constr)(functional:global_reference)
    (eqs:constr list)
  (expr:constr) =
  tclTRY
    (match kind_of_term expr with
      Case(_,t,a,l) ->
	(match find_call_occs f a with
	     _,[] -> 
	       tclTHENS(mkCaseEq a)(* (simplest_case a) *)
	  	 (List.map
		    (mk_intros_and_continue true
		       (prove_eq  termine f functional) eqs)
		    (Array.to_list l))
	   | _,_::_ ->
               	(match find_call_occs f expr with
	     _,[] -> base_leaf_eq functional eqs f
	   | fn,args ->
	       fun g ->
		 let ids = ids_of_named_context (pf_hyps g) in
	       rec_leaf_eq termine f ids
		 (constr_of_reference functional)
		 eqs expr fn args g))
       | _ -> 
	   (match find_call_occs f expr with
		_,[] -> base_leaf_eq functional eqs f
	      | fn,args ->
		  fun g ->
		    let ids = ids_of_named_context (pf_hyps g) in
		    rec_leaf_eq  
		      termine f ids (constr_of_reference functional)
		      eqs expr fn args g));;

let (com_eqn : identifier ->
       global_reference -> global_reference -> global_reference
	 -> constr_expr -> unit) =
  fun eq_name functional_ref f_ref terminate_ref eq ->
    let (evmap, env) = Command.get_current_context() in
    let eq_constr = interp_constr evmap env eq in
    let f_constr = (constr_of_reference f_ref) in
    (start_proof eq_name (Global, Proof Lemma)
       (Environ.named_context_val env) eq_constr (fun _ _ -> ());
     by
       (start_equation f_ref terminate_ref
	  (fun x ->
	     prove_eq 
	       (constr_of_reference terminate_ref)
	       f_constr 
	       functional_ref
	       []
	       (instantiate_lambda
	       	  (def_of_const (constr_of_reference functional_ref))
	       	  (f_constr::List.map mkVar x)
	       )
	  )
       );
     Command.save_named true);;


let recursive_definition is_mes f type_of_f r rec_arg_num eq generate_induction_principle =
  let function_type = interp_constr Evd.empty (Global.env()) type_of_f in
  let env = push_rel (Name f,None,function_type) (Global.env()) in
  let res_vars,eq' = decompose_prod (interp_constr Evd.empty env eq) in 
  let res = 
(*     Pp.msgnl (str "res_var :=" ++ Printer.pr_lconstr_env (push_rel_context (List.map (function (x,t) -> (x,None,t)) res_vars) env) eq'); *)
(*     Pp.msgnl (str "rec_arg_num := " ++ str (string_of_int rec_arg_num)); *)
(*     Pp.msgnl (str "eq' := " ++ str (string_of_int rec_arg_num)); *)
    match kind_of_term eq' with 
      | App(e,[|_;_;eq_fix|]) -> 
		  mkLambda (Name f,function_type,compose_lam res_vars eq_fix)
      | _ -> failwith "Recursive Definition (res not eq)"
  in
  let pre_rec_args,function_type_before_rec_arg = decompose_prod_n (rec_arg_num - 1) function_type in 
  let (_, rec_arg_type, _) = destProd function_type_before_rec_arg in
  let arg_types = List.rev_map snd (fst (decompose_prod_n (List.length res_vars) function_type)) in
  let equation_id = add_suffix f "_equation" in
  let functional_id =  add_suffix f "_F" in
  let term_id = add_suffix f "_terminate" in
  let functional_ref = declare_fun functional_id (IsDefinition Definition) res in
(*   let _ = Pp.msgnl (str "res := " ++ Printer.pr_lconstr res) in *)
  let env_with_pre_rec_args = push_rel_context(List.map (function (x,t) -> (x,None,t)) pre_rec_args) env in 
  let relation = 
    interp_constr
      Evd.empty 
      env_with_pre_rec_args
      r
  in 
(*   let _ = Pp.msgnl (str "relation := " ++ Printer.pr_lconstr_env env_with_pre_rec_args relation) in *)
  let hook _ _ =   
    let term_ref = Nametab.locate (make_short_qualid term_id) in
    let f_ref = declare_f f (IsProof Lemma) arg_types term_ref in
(*     let _ = message "start second proof" in *)
    com_eqn equation_id functional_ref f_ref term_ref eq;
    let eq_ref = Nametab.locate (make_short_qualid equation_id ) in
(*     generate_induction_principle *)
(*       functional_ref eq_ref rec_arg_num rec_arg_type (nb_prod res) relation; *)
    ()

  in
  com_terminate is_mes functional_ref rec_arg_type relation rec_arg_num term_id  hook 
;;



(* let observe_tac = do_observe_tac  *)

let base_leaf_princ eq_cst functional_ref eqs expr = 
  tclTHENSEQ 
    [rewriteLR (mkConst eq_cst);
     list_rewrite true eqs;
     gen_eauto(* default_eauto *) false (false,5) [] (Some [])
    ]



let finalize_rec_leaf_princ_with is_mes hrec acc_inv br = 
  tclTHENSEQ [
    Eauto.e_resolve_constr (mkVar br);
    tclFIRST
      [
	e_assumption;
	reflexivity;
	tclTHEN (apply (mkVar hrec))
	  (tclTHENS
	     (* (try *) (observe_tac "applying inversion" (apply (Lazy.force acc_inv))) 
(* 	      with e -> Pp.msgnl (Printer.pr_lconstr (Lazy.force acc_inv));raise e *)
(* 	     ) *)
	     [ h_assumption
	     ;
	       (fun g ->
	       tclUSER
		 is_mes
		 (Some (hrec::(retrieve_acc_var g)))
		 g
	       )
	     ]
	  );
	(fun g -> tclIDTAC_MESSAGE (str "here" ++ Printer.pr_goal (sig_it g)) g)
      ]
  ]
    
let rec_leaf_princ
    eq_cst
    branches_names 
    is_mes
    acc_inv
    hrec
    (functional_ref:global_reference) 
    eqs
    expr
    = 
  
  tclTHENSEQ 
    [ rewriteLR (mkConst eq_cst);
      list_rewrite true eqs;
      tclFIRST 
	(List.map (finalize_rec_leaf_princ_with is_mes hrec acc_inv) branches_names)
    ]


let fresh_id avoid na = 
  let id =  
    match na with 
      | Name id -> id 
      | Anonymous -> h_id 
  in 
  next_global_ident_away true id avoid



let prove_principle is_mes functional_ref 
    eq_ref rec_arg_num rec_arg_type nb_args relation = 
(*  f_ref eq_ref rec_arg_num rec_arg_type nb_args relation *)
  let eq_cst =   
    match eq_ref with 
	ConstRef sp -> sp 
      | _ -> assert false 
  in
  fun g -> 
    let type_of_goal = pf_concl g in 
    let goal_ids = pf_ids_of_hyps g in 
    let goal_elim_infos = compute_elim_sig  (mkRel 0,Rawterm.NoBindings) type_of_goal in 
    let params_names,ids = List.fold_left 
      (fun (params_names,avoid) (na,_,_) -> 
	 let new_id = fresh_id avoid na in 
	 (new_id::params_names,new_id::avoid)
      )
      ([],goal_ids)
      goal_elim_infos.params
    in
    let predicates_names,ids = 
      List.fold_left 
	(fun (predicates_names,avoid) (na,_,_) -> 
	   let new_id = fresh_id avoid na in 
	   (new_id::predicates_names,new_id::avoid)
	)
	([],ids)
	goal_elim_infos.predicates
    in
    let branches_names,ids = 
      List.fold_left 
	(fun (branches_names,avoid) (na,_,_) -> 
	   let new_id = fresh_id avoid na in 
	   (new_id::branches_names,new_id::avoid)
	)
	([],ids)
	goal_elim_infos.branches
    in
    let to_intro = params_names@predicates_names@branches_names in 
    let nparams = List.length params_names in 
    let rec_arg_num = rec_arg_num - nparams in 
    begin 
      tclTHEN 
	(h_intros to_intro)
	(observe_tac (string_of_int (rec_arg_num)) 
	   (fun g -> 
	      let ids = ids_of_named_context (pf_hyps g) in
	      let func_body = (def_of_const (constr_of_reference functional_ref)) in
(* 	      let _ = Pp.msgnl (Printer.pr_lconstr func_body) in  *)
	      let (f_name, _, body1) = destLambda func_body in
	      let f_id =
		match f_name with
		  | Name f_id -> next_global_ident_away true f_id ids
		  | Anonymous -> assert false 
	      in
	      let n_names_types,_ = decompose_lam body1 in 
	      let n_ids,ids = 
		List.fold_left 
		  (fun (n_ids,ids) (n_name,_) -> 
		     match n_name with 
		       | Name id -> 
			   let n_id = next_global_ident_away true id ids in 
			   n_id::n_ids,n_id::ids
		       | _ -> assert false
		  )
		  ([],(f_id::ids))
		  n_names_types
	      in
	      let rec_arg_id = List.nth n_ids (rec_arg_num - 1 ) in
	      let expr = 
		instantiate_lambda func_body
		  (mkVar f_id::(List.map mkVar n_ids)) 
	      in 
	      start 
		is_mes
		rec_arg_type
		ids
		(snd (list_chop nparams n_ids))
		(substl (List.map mkVar params_names) relation)
		(rec_arg_num)
		rec_arg_id
		(fun hrec acc_inv g ->  
		   (proveterminate 
		      is_mes
		      acc_inv 
		      hrec
		      (mkVar f_id)
		      functional_ref
		      (base_leaf_princ eq_cst)
		      (rec_leaf_princ eq_cst branches_names)
		      []
		      expr
		   )
		     g 
		)
		g )
	)
    end
      g



VERNAC COMMAND EXTEND RecursiveDefinition
  [ "Recursive" "Definition" ident(f) constr(type_of_f) constr(r) constr(wf)
     constr(proof) integer_opt(rec_arg_num) constr(eq) ] ->
  [ ignore(proof);ignore(wf);
    let rec_arg_num = 
      match rec_arg_num with 
	| None -> 1
	| Some n -> n 
    in
    recursive_definition false f type_of_f r rec_arg_num eq (fun _ _ _ _ _  _ -> ())]
| [ "Recursive" "Definition" ident(f) constr(type_of_f) constr(r) constr(wf)
     "[" ne_constr_list(proof) "]" constr(eq) ] ->
  [ ignore(proof);ignore(wf);recursive_definition false f type_of_f r 1 eq  (fun  _ _  _ _ _ _ -> ())]
END



