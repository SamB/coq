(************************************************************************)
(*  v      *   The Coq Proof Assistant  /  The Coq Development Team     *)
(* <O___,, * CNRS-Ecole Polytechnique-INRIA Futurs-Universite Paris Sud *)
(*   \VV/  **************************************************************)
(*    //   *      This file is distributed under the terms of the       *)
(*         *       GNU Lesser General Public License Version 2.1        *)
(************************************************************************)

(* $Id$ *)

open Names
open Util
open Sign
open Term
open Entries
open Declarations
open Cooking

(********************************)
(* Discharging mutual inductive *)

let detype_param = function
  | (Name id,None,p) -> id, Entries.LocalAssum p
  | (Name id,Some p,_) -> id, Entries.LocalDef p
  | (Anonymous,_,_) -> anomaly"Unnamed inductive local variable"

(* Replace

     Var(y1)..Var(yq):C1..Cq |- Ij:Bj
     Var(y1)..Var(yq):C1..Cq; I1..Ip:B1..Bp |- ci : Ti

   by

     |- Ij: (y1..yq:C1..Cq)Bj
     I1..Ip:(B1 y1..yq)..(Bp y1..yq) |- ci : (y1..yq:C1..Cq)Ti[Ij:=(Ij y1..yq)]
*)

let abstract_inductive hyps inds =
  let ntyp = List.length inds in 
  let nhyp = named_context_length hyps in
  let args = instance_from_named_context (List.rev hyps) in
  let subs = list_tabulate (fun k -> lift nhyp (mkApp(mkRel (k+1),args))) ntyp in
  let inds' =
    List.map
      (function (np,tname,arity,cnames,lc) -> 
	let lc' = List.map (substl subs) lc in
	let lc'' = List.map (fun b -> Termops.it_mkNamedProd_wo_LetIn b hyps) lc' in
	let arity' = Termops.it_mkNamedProd_wo_LetIn arity hyps in
        (np,tname,arity',cnames,lc''))
      	inds in
  List.map 
    (fun (nparams,a,arity,c,lc) ->
      let nparams' = nparams + Array.length args in
      let params, short_arity = decompose_prod_n_assum nparams' arity in
      let shortlc =
	List.map (fun c -> snd (decompose_prod_n_assum nparams' c))lc in
      let params' = List.map detype_param params in
      { mind_entry_params = params';
        mind_entry_typename = a;
	mind_entry_arity = short_arity;
	mind_entry_consnames = c;
	mind_entry_lc = shortlc })
    inds'

let process_inductive sechyps modlist mib =
  let inds = 
    array_map_to_list
      (fun mip ->
	 let nparams = mip.mind_nparams in
	 let arity = expmod_constr modlist mip.mind_user_arity in
	 let lc = Array.map (expmod_constr modlist) mip.mind_user_lc in
	 (nparams,
	  mip.mind_typename,
	  arity,
	  Array.to_list mip.mind_consnames,
	  Array.to_list lc))
      mib.mind_packets in
  let sechyps' = map_named_context (expmod_constr modlist) sechyps in
  let inds' = abstract_inductive sechyps' inds in
  { mind_entry_record = mib.mind_record;
    mind_entry_finite = mib.mind_finite;
    mind_entry_inds = inds' }
