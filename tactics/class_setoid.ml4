(************************************************************************)
(*  v      *   The Coq Proof Assistant  /  The Coq Development Team     *)
(* <O___,, * CNRS-Ecole Polytechnique-INRIA Futurs-Universite Paris Sud *)
(*   \VV/  **************************************************************)
(*    //   *      This file is distributed under the terms of the       *)
(*         *       GNU Lesser General Public License Version 2.1        *)
(************************************************************************)

(*i camlp4deps: "parsing/grammar.cma" i*)

(* $Id: eauto.ml4 10346 2007-12-05 21:11:19Z aspiwack $ *)

open Pp
open Util
open Names
open Nameops
open Term
open Termops
open Sign
open Reduction
open Proof_type
open Proof_trees
open Declarations
open Tacticals
open Tacmach
open Evar_refiner
open Tactics
open Pattern
open Clenv
open Auto
open Rawterm
open Hiddentac
open Typeclasses
open Typeclasses_errors

let e_give_exact c gl = 
  let t1 = (pf_type_of gl c) and t2 = pf_concl gl in 
  if occur_existential t1 or occur_existential t2 then 
     tclTHEN (Clenvtac.unify t1) (exact_check c) gl
  else exact_check c gl

let assumption id = e_give_exact (mkVar id)

let morphism_class = lazy (class_info (id_of_string "Morphism"))

let get_respect cl = 
  Option.get (List.hd (Recordops.lookup_projections cl.cl_impl))

let respect_proj = lazy (get_respect (Lazy.force morphism_class))

let gen_constant dir s = Coqlib.gen_constant "Class_setoid" dir s
let coq_proj1 = lazy(gen_constant ["Init"; "Logic"] "proj1")
let coq_proj2 = lazy(gen_constant ["Init"; "Logic"] "proj2")
let iff = lazy (gen_constant ["Init"; "Logic"] "iff")
let impl = lazy (gen_constant ["Program"; "Basics"] "impl")
let arrow = lazy (gen_constant ["Program"; "Basics"] "arrow")

let reflexive_type = lazy (gen_constant ["Classes"; "Relations"] "Reflexive")
let reflexive_proof = lazy (gen_constant ["Classes"; "Relations"] "reflexive")

let symmetric_type = lazy (gen_constant ["Classes"; "Relations"] "Symmetric")
let symmetric_proof = lazy (gen_constant ["Classes"; "Relations"] "symmetric")

let transitive_type = lazy (gen_constant ["Classes"; "Relations"] "Transitive")
let transitive_proof = lazy (gen_constant ["Classes"; "Relations"] "transitive")

let inverse = lazy (gen_constant ["Classes"; "Relations"] "inverse")

let respectful_dep = lazy (gen_constant ["Classes"; "Relations"] "respectful_dep")
let respectful = lazy (gen_constant ["Classes"; "Relations"] "respectful")

let iff_equiv = lazy (gen_constant ["Classes"; "Relations"] "iff_equivalence")
let eq_equiv = lazy (gen_constant ["Classes"; "SetoidClass"] "eq_equivalence")

(* let coq_relation = lazy (gen_constant ["Relations";"Relation_Definitions"] "relation") *)
let coq_relation = lazy (gen_constant ["Classes";"Relations"] "relation")
let coq_relationT = lazy (gen_constant ["Classes";"Relations"] "relationT")

let setoid_refl_proj = lazy (gen_constant ["Classes"; "SetoidClass"] "equiv_refl")

let iff_setoid = lazy (gen_constant ["Classes"; "SetoidClass"] "iff_setoid")
let eq_setoid = lazy (gen_constant ["Classes"; "SetoidClass"] "eq_setoid")

let setoid_equiv = lazy (gen_constant ["Classes"; "SetoidClass"] "equiv")
let setoid_morphism = lazy (gen_constant ["Classes"; "SetoidClass"] "setoid_morphism")
let setoid_refl_proj = lazy (gen_constant ["Classes"; "SetoidClass"] "equiv_refl")
  
let arrow_morphism a b = 
  mkLambda (Name (id_of_string "A"), a, 
	   mkLambda (Name (id_of_string "B"), b, 
		    mkProd (Anonymous, mkRel 2, mkRel 2)))
    
let setoid_refl pars x = 
  applistc (Lazy.force setoid_refl_proj) (pars @ [x])
      
let morphism_class = lazy (Lazy.force morphism_class, Lazy.force respect_proj)

exception Found of (constr * constr * (types * types) list * constr * constr array *
		       (constr * (constr * constr * constr * constr)) option array)

let resolve_morphism_evd env evd app = 
  let ev = Evarutil.e_new_evar evd env app in
  let evd' = resolve_typeclasses ~check:false env (Evd.evars_of !evd) !evd in
  let evm' = Evd.evars_of evd' in
    match Evd.evar_body (Evd.find evm' (fst (destEvar ev))) with
	Evd.Evar_empty -> raise Not_found
      | Evd.Evar_defined c -> evd := Evarutil.nf_evar_defs evd'; Evarutil.nf_isevar !evd c

let is_equiv env sigma t = 
  isConst t && Reductionops.is_conv env sigma (Lazy.force setoid_equiv) t

let split_head = function
    hd :: tl -> hd, tl
  | [] -> assert(false)

let build_signature isevars env m cstrs finalcstr =
  let new_evar isevars env t =
    Evarutil.e_new_evar isevars env
      (* ~src:(dummy_loc, ImplicitArg (ConstRef (Lazy.force respectful), (n, Some na))) *) t
  in
  let mk_relty ty obj =
    let relty = mkApp (Lazy.force coq_relation, [| ty |]) in
      match obj with
	| None -> new_evar isevars env relty
	| Some (p, (a, r, oldt, newt)) -> r
  in
  let rec aux t l =
    let t = Reductionops.whd_betadelta env (Evd.evars_of !isevars) t in
    match kind_of_term t, l with
      | Prod (na, ty, b), obj :: cstrs -> 
	  let (arg, evars) = aux b cstrs in
	  let relty = mk_relty ty obj in
	  let arg' = mkApp (Lazy.force respectful, [| ty ; relty ; b ; arg |]) in
	    arg', (ty, relty) :: evars
      | _, _ -> 
	  (match finalcstr with
	      None -> 
		let rel = mk_relty t None in 
		  rel, [t, rel]
	    | Some (t, rel) -> rel, [t, rel])
      | _, _ -> assert false
  in aux m cstrs

let reflexivity_proof env carrier relation x =
  let goal = 
    mkApp (Lazy.force reflexive_type, [| carrier ; relation |])
  in
    try let inst = resolve_one_typeclass env goal in
	  mkApp (Lazy.force reflexive_proof, [| carrier ; relation ; inst ; x |])
    with Not_found ->
      let meta = Evarutil.new_meta() in
	mkCast (mkMeta meta, DEFAULTcast, mkApp (relation, [| x; x |]))
	  
let resolve_morphism env sigma direction oldt m args args' cstr = 
  let (morphism_cl, morphism_proj) = Lazy.force morphism_class in
  let morph_instance, proj, sigargs, m', args, args' = 
(*     if is_equiv env sigma m then  *)
(*       let params, rest = array_chop 3 args in *)
(*       let a, r, s = params.(0), params.(1), params.(2) in *)
(*       let params', rest' = array_chop 3 args' in *)
(*       let inst = mkApp (Lazy.force setoid_morphism, params) in *)
(* 	(* Equiv gives a binary morphism *) *)
(*       let (cl, proj) = Lazy.force class_two in *)
(*       let ctxargs = [ a; r; s; a; r; s; mkProp; Lazy.force iff; Lazy.force iff_setoid; ] in *)
(*       let m' = mkApp (m, [| a; r; s |]) in *)
(* 	inst, proj, ctxargs, m', rest, rest' *)
(*     else *)
    let evars = ref (Evd.create_evar_defs Evd.empty) in
    let pars =
	match Array.length args with
	    1 -> [1]
	  | 2 -> [2;1]
	  | 3 -> [3;2;1]
	  | _ -> [4;3;2;1]
      in
	try 
	  List.iter (fun n ->
	    evars := Evd.create_evar_defs Evd.empty;
	    let morphargs, morphobjs = array_chop (Array.length args - n) args in
	    let morphargs', morphobjs' = array_chop (Array.length args - n) args' in
	    let appm = mkApp(m, morphargs) in
	    let appmtype = Typing.type_of env sigma appm in
	    let signature, sigargs = build_signature evars env appmtype (Array.to_list morphobjs') cstr in
	    let cl_args = [| appmtype ; signature ; appm |] in
	    let app = mkApp (mkInd morphism_cl.cl_impl, cl_args) in
	      try 
		let morph = resolve_morphism_evd env evars app in
		let evm = Evd.evars_of !evars in
		let sigargs = List.map 
		  (fun x, y -> Reductionops.nf_evar evm x, Reductionops.nf_evar evm y) 
		  sigargs 
		in
		let appm = Reductionops.nf_evar evm appm in
		let cl_args = Array.map (Reductionops.nf_evar evm) cl_args in
		let proj = 
		  mkApp (mkConst morphism_proj, 
			Array.append cl_args [|morph|])
		in
		  raise (Found (morph, proj, sigargs, appm, morphobjs, morphobjs'))
	      with Not_found -> ()
		| Reduction.NotConvertible -> ()
		| Stdpp.Exc_located (_, Pretype_errors.PretypeError _) 
		| Pretype_errors.PretypeError _ -> ())
	    pars;
	  raise Not_found
	with Found x -> x
  in 
  let projargs, respars, typeargs = 
    array_fold_left2 
      (fun (acc, sigargs, typeargs') x y -> 
	let (carrier, relation), sigargs = split_head sigargs in
	  match y with
	      None ->
		let refl_proof = reflexivity_proof env carrier relation x in
		  [ refl_proof ; x ; x ] @ acc, sigargs, x :: typeargs'
	    | Some (p, (_, _, _, t')) ->
		[ p ; t'; x ] @ acc, sigargs, t' :: typeargs')
      ([], sigargs, []) args args'
  in
  let proof = applistc proj (List.rev projargs) in
  let newt = applistc m' (List.rev typeargs) in
    match respars with
	[ a, r ] -> (proof, (a, r, oldt, newt))
      | _ -> assert(false)

let build_new gl env sigma direction occs origt newt hyp hypinfo concl cstr =
  let is_occ occ = occs = [] || List.mem occ occs in
  let rec aux t occ cstr =
    match kind_of_term t with
      | _ when eq_constr t origt -> 
	  if is_occ occ then
	    Some (hyp, hypinfo), succ occ
	  else None, succ occ

      | App (m, args) ->
	  let args', occ = 
	    Array.fold_left 
	      (fun (acc, occ) arg -> let res, occ = aux arg occ None in (res :: acc, occ))
	      ([], occ) args
	  in
	  let res =
	    if List.for_all (fun x -> x = None) args' then None
	    else 
	      let args' = Array.of_list (List.rev args') in
		(try Some (resolve_morphism env sigma direction t m args args' cstr)
		  with Not_found -> None)
	  in res, occ

      | Prod (_, x, b) -> 
	  let x', occ = aux x occ None in
	  let b', occ = aux b occ None in
	  let res = 
	    if x' = None && b' = None then None
	    else 
	      (try Some (resolve_morphism env sigma direction t
			    (arrow_morphism (pf_type_of gl x) (pf_type_of gl b)) [| x ; b |] [| x' ; b' |]
			    cstr)
		with Not_found -> None)
	  in res, occ

      | _ -> None, occ
  in aux concl 1 cstr

let decompose_setoid_eqhyp gl env sigma c left2right t = 
  let (c, (car, rel, x, y) as res) =
    match kind_of_term t with
	(*     | App (equiv, [| a; r; s; x; y |]) -> *)
	(* 	if dir then (c, (a, r, s, x, y)) *)
	(* 	else (c, (a, r, s, y, x)) *)
      | App (r, args) when Array.length args >= 2 -> 
	  let relargs, args = array_chop (Array.length args - 2) args in
	  let rel = mkApp (r, relargs) in
	  let typ = pf_type_of gl rel in
	    (match kind_of_term typ with
	      | App (relation, [| carrier |]) when eq_constr relation (Lazy.force coq_relation) 
		    || eq_constr relation (Lazy.force coq_relationT) ->
		  (c, (carrier, rel, args.(0), args.(1)))
	      | _ when isArity typ ->
		  let (ctx, ar) = destArity typ in
		    (match ctx with
			[ (_, None, sx) ; (_, None, sy) ] when eq_constr sx sy -> 
			  (c, (sx, rel, args.(0), args.(1)))
		      | _ -> error "Only binary relations are supported")
	      | _ -> error "Not a relation")
      | _ -> error "Not a relation"
  in
    if left2right then res
    else (c, (car, mkApp (Lazy.force inverse, [| car ; rel |]), y, x))

let cl_rewrite_clause c left2right occs clause gl =
  let env = pf_env gl in
  let sigma = project gl in
  let hyp = pf_type_of gl c in
  let hypt, (typ, rel, origt, newt as hypinfo) = decompose_setoid_eqhyp gl env sigma c left2right hyp in
  let concl, is_hyp = 
    match clause with
	Some ((_, id), _) -> pf_get_hyp_typ gl id, Some id
      | None -> pf_concl gl, None
  in
  let cstr = 
    match is_hyp with
	None -> (mkProp, mkApp (Lazy.force inverse, [| mkProp; Lazy.force impl |]))
      | Some _ -> (mkProp, Lazy.force impl)
  in
  let eq, _ = build_new gl env sigma left2right occs origt newt hypt hypinfo concl (Some cstr) in
    match eq with  
	Some (p, (_, _, oldt, newt)) -> 
	  (match is_hyp with
	    | Some id -> Tactics.apply_in true id [p,NoBindings]
	    | None -> 
		let meta = Evarutil.new_meta() in
		let term = mkApp (p, [| mkCast (mkMeta meta, DEFAULTcast, newt) |]) in
		  refine term) gl
      | None -> tclIDTAC gl
	  
open Extraargs



TACTIC EXTEND class_rewrite
| [ "clrewrite" orient(o) constr(c) "at" occurences(occ) "in" hyp(id) ] -> [ cl_rewrite_clause c o occ (Some (([],id), [])) ]
| [ "clrewrite" orient(o) constr(c) "in" hyp(id) ] -> [ cl_rewrite_clause c o [] (Some (([],id), [])) ]
| [ "clrewrite" orient(o) constr(c) "at" occurences(occ) ] -> [ cl_rewrite_clause c o occ None ]
| [ "clrewrite" orient(o) constr(c) ] -> [ cl_rewrite_clause c o [] None ]
END

let clsubstitute o c =
  let is_tac id = match kind_of_term c with Var id' when id' = id -> true | _ -> false in
    Tacticals.onAllClauses 
      (fun cl -> 
	match cl with
	  | Some ((_,id),_) when is_tac id -> tclIDTAC
	  | _ -> cl_rewrite_clause c o [] cl)

TACTIC EXTEND map_tac
| [ "clsubstitute" orient(o) constr(c) ] -> [ clsubstitute o c ]
END


(* 
	  let proj = 
	    if left2right then 
	      let proj = if is_hyp <> None then coq_proj1 else coq_proj2 in
		applistc (Lazy.force proj)
		  [ mkProd (Anonymous, concl, t) ; mkProd (Anonymous, t, concl) ; p ] 
	    else 
	      let proj = if is_hyp <> None then coq_proj2 else coq_proj1 in
		applistc (Lazy.force proj)
		  [ mkProd (Anonymous, t, concl) ; mkProd (Anonymous, concl, t) ; p ] 
	  in
*)