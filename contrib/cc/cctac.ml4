(***********************************************************************)
(*  v      *   The Coq Proof Assistant  /  The Coq Development Team    *)
(* <O___,, *        INRIA-Rocquencourt  &  LRI-CNRS-Orsay              *)
(*   \VV/  *************************************************************)
(*    //   *      This file is distributed under the terms of the      *)
(*         *       GNU Lesser General Public License Version 2.1       *)
(***********************************************************************)

(*i camlp4deps: "parsing/grammar.cma" i*)

(* $Id$ *)

(* This file is the interface between the c-c algorithm and Coq *)

open Evd
open Proof_type
open Names
open Libnames
open Nameops
open Inductiveops
open Declarations
open Term
open Tacmach
open Tactics
open Tacticals
open Ccalgo
open Tacinterp
open Ccproof
open Pp
open Util
open Format

exception Not_an_eq

let fail()=raise Not_an_eq
    
let constant dir s = lazy (Coqlib.gen_constant "CC" dir s)

let f_equal_theo = constant ["Init";"Logic"] "f_equal"

(* decompose member of equality in an applicative format *)

let rec decompose_term env t=
  match kind_of_term t with
      App (f,args)->
	let tf=decompose_term env f in
	let targs=Array.map (decompose_term env) args in
	  Array.fold_left (fun s t->Appli (s,t)) tf targs
    | Construct c->
	let (_,oib)=Global.lookup_inductive (fst c) in
	let nargs=mis_constructor_nargs_env env c in
	  Constructor (c,nargs,nargs-oib.mind_nparams)
    | _ ->(Symb t)
	
(* decompose equality in members and type *)
	
let eq_type_of_term term=
  match kind_of_term term with
      App (f,args)->
	(try 
	   let ref = reference_of_constr f in
	     if ref=Coqlib.glob_eq && (Array.length args)=3 
	     then (args.(0),args.(1),args.(2)) 
	     else fail()
	 with
	     Not_found -> fail ())
    | _ ->fail ()

(* read an equality *)
	  
let read_eq env term=
  let (_,t1,t2)=eq_type_of_term term in 
    (decompose_term env t1,decompose_term env t2)

(* rebuild a term from applicative format *)
    
let rec make_term=function
    Symb s->s
  | Constructor(c,_,_)->mkConstruct c 
  | Appli (s1,s2)->make_app [(make_term s2)] s1
and make_app l=function
    Symb s->applistc s l
  | Constructor(c,_,_)->applistc (mkConstruct c) l
  | Appli (s1,s2)->make_app ((make_term s2)::l) s1

(* store all equalities from the context *)
	
let rec read_hyps env=function
    []->[]
  | (id,_,e)::hyps->let q=(read_hyps env hyps) in
      try (id,(read_eq env e))::q with Not_an_eq -> q

(* build a problem ( i.e. read the goal as an equality ) *)
	
let make_prb gl=
  let env=pf_env gl in
  let hyps=read_hyps env gl.it.evar_hyps in
    try (hyps,Some (read_eq env gl.it.evar_concl)) with 
	Not_an_eq -> (hyps,None)


(* indhyps builds the array of arrays of constructor hyps for (ind largs) *)

let build_projection (cstr:constructor) nargs argind ttype default atype gls=
  let (h,argv) = destApplication ttype in
  let ind=destInd h in 
  let (mib,mip) = Global.lookup_inductive ind in
  let n = mip.mind_nparams in
    (* assert (n=(Array.length argv));*)
  let lp=Array.length mip.mind_consnames in
  let types=mip.mind_nf_lc in   
  let ci=(snd cstr)-1 in
  let branch i=
    let ti=Term.prod_appvect types.(i) argv in
    let rc=fst (Sign.decompose_prod_assum ti) in
    let head=
      if i=ci then mkRel (1+nargs-argind) else default in  
      Sign.it_mkLambda_or_LetIn head rc in
  let branches=Array.init lp branch in
  let casee=mkRel 1 in
  let pred=mkLambda(Anonymous,ttype,atype) in
  let env=pf_env gls in 
  let case_info=make_default_case_info (pf_env gls) RegularStyle ind in
  let body= mkCase(case_info, pred, casee, branches) in
  let id=pf_get_new_id (id_of_string "t") gls in     
    mkLambda(Name id,ttype,body)

(* generate an adhoc tactic following the proof tree  *)

let rec proof_tac axioms=function
    Ax id->exact_check (mkVar id)
  | SymAx id->tclTHEN symmetry (exact_check (mkVar id))
  | Refl t->reflexivity
  | Trans (p1,p2)->let t=(make_term (snd (type_proof axioms p1))) in
      (tclTHENS (transitivity t) 
	 [(proof_tac axioms p1);(proof_tac axioms p2)])
  | Congr (p1,p2)->
      fun gls->
	let (f1,f2)=(type_proof axioms p1) 
	and (x1,x2)=(type_proof axioms p2) in
        let tf1=make_term f1 and tx1=make_term x1 
	and tf2=make_term f2 and tx2=make_term x2 in
	let typf=pf_type_of gls tf1 and typx=pf_type_of gls tx1
	and typfx=pf_type_of gls (mkApp(tf1,[|tx1|])) in
	let id=pf_get_new_id (id_of_string "f") gls in
	let appx1=mkLambda(Name id,typf,mkApp(mkRel 1,[|tx1|])) in
	let lemma1=
	  mkApp(Lazy.force f_equal_theo,[|typf;typfx;appx1;tf1;tf2|])
	and lemma2=
	  mkApp(Lazy.force f_equal_theo,[|typx;typfx;tf2;tx1;tx2|]) in
	  (tclTHENS (transitivity (mkApp(tf2,[|tx1|])))
	     [tclTHEN (apply lemma1) (proof_tac axioms p1);
  	      tclFIRST
		[tclTHEN (apply lemma2) (proof_tac axioms p2);
		 reflexivity;
		 fun gls ->
		   errorlabstrm  "CC" 
		   (Pp.str 
		      "CC doesn't know how to handle dependent equality.")]]
	     gls)
  | Inject (prf,cstr,nargs,argind)  as gprf->
      (fun gls ->
	 let ti,tj=type_proof axioms prf in
	 let ai,aj=type_proof axioms gprf in
	 let cti=make_term ti in
	 let ctj=make_term tj in
	 let cai=make_term ai in
	 let ttype=pf_type_of gls cti in
	 let atype=pf_type_of gls cai in
	 let proj=build_projection cstr nargs argind ttype cai atype gls in
	 let injt=
	   mkApp (Lazy.force f_equal_theo,[|ttype;atype;proj;cti;ctj|]) in   
	   tclTHEN (apply injt) (proof_tac axioms prf) gls)

(* wrap everything *)
	
let cc_tactic gls=
  Library.check_required_library ["Coq";"Init";"Logic"];
  let prb=
    try make_prb gls with 
	Not_an_eq ->
	  errorlabstrm  "CC" (str "Goal is not an equality") in
    match (cc_proof prb) with
        Prove (p,axioms)-> proof_tac axioms p gls
      | Refute (t1,t2,p,axioms) ->
	  let tt1=make_term t1 and tt2=make_term t2 in
	  let typ=pf_type_of gls tt1 in
	  let id=pf_get_new_id (id_of_string "Heq") gls in     
	  let neweq=
	    mkApp(constr_of_reference Coqlib.glob_eq,[|typ;tt1;tt2|]) in
	    tclTHENS (true_cut (Some id) neweq)
	      [proof_tac axioms p;Equality.discr id] gls

(* Tactic registration *)
      
TACTIC EXTEND CC
 [ "Congruence" ] -> [ cc_tactic ]
END










   
