(* Author : Nicolas Ayache and Jean-Christophe Filli�tre *)
(* Goal : Tactics to call decision procedures *)


open Util
open Pp
open Term
open Tacmach
open Tactics
open Tacticals
open Fol
open Names
open Nameops
open Termops
open Coqlib
open Hipattern
open Libnames
open Declarations

let logic_dir = ["Coq";"Logic";"Decidable"]
let coq_modules =
  init_modules @ [logic_dir] @ arith_modules @ zarith_base_modules
    @ [["Coq"; "omega"; "OmegaLemmas"]]

let constant = gen_constant_in_modules "Omega" coq_modules

let coq_Z = lazy (constant "Z")
let coq_Zplus = lazy (constant "Zplus")
let coq_Zmult = lazy (constant "Zmult")
let coq_Zopp = lazy (constant "Zopp")
let coq_Zminus = lazy (constant "Zminus")
let coq_Zdiv = lazy (constant "Zdiv")
let coq_Zs = lazy (constant "Zs")
let coq_Zgt = lazy (constant "Zgt")
let coq_Zle = lazy (constant "Zle")
let coq_Zge = lazy (constant "Zge")
let coq_Zlt = lazy (constant "Zlt")
let coq_Z0 = lazy (constant "Z0")
let coq_Zpos = lazy (constant "Zpos")
let coq_Zneg = lazy (constant "Zneg")
let coq_xH = lazy (constant "xH")
let coq_xI = lazy (constant "xI")
let coq_xO = lazy (constant "xO")

(* not Prop typed expressions *)
exception NotProp

(* not first-order expressions *)
exception NotFO

(* Renaming of Coq globals *)

let global_names = Hashtbl.create 97
let used_names = Hashtbl.create 97

let rename_global r =
  try 
    Hashtbl.find global_names r
  with Not_found ->
    let rec loop id = 
      if Hashtbl.mem used_names id then 
	loop (lift_ident id)
      else begin 
	Hashtbl.add used_names id ();
	let s = string_of_id id in
	Hashtbl.add global_names r s; 
	s
      end
    in
    loop (Nametab.id_of_global r)

let foralls =
  List.fold_right 
    (fun (x,t) p -> Forall (x, t, p))

let fresh_var = function
  | Anonymous -> rename_global (VarRef (id_of_string "x"))
  | Name x -> rename_global (VarRef x)

(* coq_rename_vars env [(x1,t1);...;(xn,tn)] renames the xi outside of 
   env names, and returns the new variables together with the new 
   environment *)
let coq_rename_vars env vars =
  let avoid = ref (ids_of_named_context (Environ.named_context env)) in
  List.fold_right
    (fun (na,t) (newvars, newenv) -> 
       let id = next_name_away na !avoid in
       avoid := id :: !avoid;
       id :: newvars, Environ.push_named (id, None, t) newenv)
    vars ([],env)

let rec eta_expanse t vars env i =
  assert (i >= 0);
  if i = 0 then
    t, vars, env
  else
    match kind_of_term (Typing.type_of env Evd.empty t) with
      | Prod (n, a, b) when not (dependent (mkRel 1) b) ->
	  let avoid = ids_of_named_context (Environ.named_context env) in
	  let id = next_name_away n avoid in
	  let env' = Environ.push_named (id, None, a) env in
	  let t' = mkApp (t, [| mkVar id |]) in
	  eta_expanse t' (id :: vars) env' (pred i)
      | _ -> 
	  assert false

(* Coq global references *)

type global = Gnot_fo | Gfo of Fol.hyp

let globals = ref Refmap.empty
let globals_stack = ref []

(* synchronization *)
let () =
  Summary.declare_summary "Dp globals"
    { Summary.freeze_function = (fun () -> !globals, !globals_stack);
      Summary.unfreeze_function = 
	(fun (g,s) -> globals := g; globals_stack := s);
      Summary.init_function = (fun () -> ());
      Summary.survive_module = false;
      Summary.survive_section = false }

let add_global r d = globals := Refmap.add r d !globals
let mem_global r = Refmap.mem r !globals
let lookup_global r = match Refmap.find r !globals with
  | Gnot_fo -> raise NotFO
  | Gfo d -> d

let locals = Hashtbl.create 97

let lookup_local r =  match Hashtbl.find locals r with
  | Gnot_fo -> raise NotFO
  | Gfo d -> d

let iter_all_constructors i f =  
  let _, oib = Global.lookup_inductive i in
  Array.iteri
    (fun j tj -> f j (mkConstruct (i, j+1)))
    oib.mind_nf_lc


(* injection c [t1,...,tn] adds the injection axiom
     forall x1:t1,...,xn:tn,y1:t1,...,yn:tn. 
       c(x1,...,xn)=c(y1,...,yn) -> x1=y1 /\ ... /\ xn=yn *)

let injection c l =
  let i = ref 0 in
  let var s = incr i; id_of_string (s ^ string_of_int !i) in
  let xl = List.map (fun t -> rename_global (VarRef (var "x")), t) l in
  i := 0;
  let yl = List.map (fun t -> rename_global (VarRef (var "y")), t) l in
  let f = 
    List.fold_right2 
      (fun (x,_) (y,_) p -> And (Fatom (Eq (App (x,[]),App (y,[]))), p))
      xl yl True
  in
  let vars = List.map (fun (x,_) -> App(x,[])) in
  let f = Imp (Fatom (Eq (App (c, vars xl), App (c, vars yl))), f) in
  let foralls = List.fold_right (fun (x,t) p -> Forall (x, t, p)) in
  let f = foralls xl (foralls yl f) in
  let ax = Assert ("injection_" ^ c, f) in
  globals_stack := ax :: !globals_stack

(* rec_names_for c [|n1;...;nk|] builds the list of constant names for 
   identifiers n1...nk with the same path as c, if they exist; otherwise
   raises Not_found *)
let rec_names_for c =
  let mp,dp,_ = Names.repr_con c in
  array_map_to_list
    (function 
       | Name id -> 
	   let c' = Names.make_con mp dp (label_of_id id) in
	   ignore (Global.lookup_constant c');
	   msgnl (Ppconstrnew.pr_term (mkConst c'));
	   c'
       | Anonymous ->
	   raise Not_found)

(* abstraction tables *)

let term_abstractions = Hashtbl.create 97

let new_abstraction = 
  let r = ref 0 in fun () -> incr r; "abstraction_" ^ string_of_int !r

(* assumption : p:Z *)
let rec fol_term_of_positive env p =
  match kind_of_term p with
    | Term.Construct _ when p = Lazy.force coq_xH ->
	Cst 1
    | Term.App (f, [|a|]) when f = Lazy.force coq_xI ->
	Plus (Mult (Cst 2, (fol_term_of_positive env a)), Cst 1)
    | Term.App (f, [|a|]) when f = Lazy.force coq_xO ->
	Mult (Cst 2, (fol_term_of_positive env a))
    | Var id ->
	Fol.App (string_of_id id, [])
    | _ ->
	tr_term [] env p

(* assumption: t:Set or Type *)
and tr_type env ty =
  if ty = Lazy.force coq_Z then [], "INT"
  else if is_Prop ty then [], "BOOLEAN"
  else if is_Set ty then [], "TYPE"
  else if is_imp_term ty then 
    begin match match_with_imp_term ty with
      | Some (t1, t2) -> begin match tr_type env t1, tr_type env t2 with
	  | ([], t1'), (l2, t2') -> t1' :: l2, t2'
	  | _ -> raise NotFO
	end
      | _ -> assert false
    end
  else
    try let r = global_of_constr ty in
    (try
       begin match lookup_global r with
	 | DeclType id -> [], id
	 | _ -> assert false (* assumption: t:Set *)
       end
     with Not_found ->
       begin match r with
	 | IndRef i ->
	     let id = rename_global r in
	     let d = DeclType id in
	     add_global r (Gfo d);
	     globals_stack := d :: !globals_stack;
	     iter_all_constructors i
	       (fun _ c ->
		  let rc = global_of_constr c in
		  try
		    begin match tr_global env rc with
		      | DeclVar (idc, [], _) -> ()
		      | DeclVar (idc, al, _) -> injection idc al
		      | _ -> assert false
		    end
		  with NotFO ->
		    ());
	     [], id
	 | _ -> 
	     let id = rename_global r in
	     let d = DeclType id in
	     add_global r (Gfo d);
	     globals_stack := d :: !globals_stack;
	     [], id
	     (* TODO: constant type definition *)
       end)
    with Not_found -> raise NotFO

and make_term_abstraction env c =
  let ty = Typing.type_of env Evd.empty c in
  let tl,t = tr_type env ty in
  try
    Hashtbl.find term_abstractions c
  with Not_found ->
    let id = new_abstraction () in
    Hashtbl.add term_abstractions c id;
    globals_stack := (DeclVar (id, tl, t)) :: !globals_stack;
    id

and tr_global_type env id ty =
  if is_Prop ty then
    DeclPred (id, [])
  else if is_Set ty then
    DeclType id
  else 
    let s = Typing.type_of env Evd.empty ty in
    if is_Prop s then
      Assert (id, tr_formula [] env ty)
    else
      let l, t = tr_type env ty in
      if is_Set s then DeclVar(id, l, t)
      else if t = "BOOLEAN" then
	DeclPred(id, l)
      else raise NotFO

and tr_global env r = match r with
  | VarRef id ->
      lookup_local id
  | r ->
      try
	lookup_global r
      with Not_found ->
	try
	  let ty = Global.type_of_global r in
	  let id = rename_global r in
	  let d = tr_global_type env id ty in
	  (* r can be already declared if it is a constructor *)
	  if not (mem_global r) then begin 
	    add_global r (Gfo d);
	    globals_stack := d :: !globals_stack
	  end;
	  begin try axiomatize_body env r id d with NotFO -> () end;
	  d
	with NotFO ->
	  add_global r Gnot_fo;
	  raise NotFO

and axiomatize_body env r id d = match r with
  | VarRef _ -> 
      assert false
  | ConstRef c ->
      begin match (Global.lookup_constant c).const_body with
	| Some b ->
	    let b = force b in
	    let axioms =
	      (match d with
		 | DeclPred (id, []) ->
		     let value = tr_formula [] env b in
		     [id, And (Imp (Fatom (Pred (id, [])), value),
			       Imp (value, Fatom (Pred (id, []))))]
		 | DeclVar (id, [], _) ->
		     let value = tr_term [] env b in
		     [id, Fatom (Eq (Fol.App (id, []), value))]
		 | DeclVar (id, l, _) | DeclPred (id, l) ->
		     let b = match kind_of_term b with
		       (* a single recursive function *)
		       | Fix (_, (_,_,[|b|])) -> 
			   subst1 (mkConst c) b
                       (* mutually recursive functions *)
		       | Fix ((_,i), (names,_,bodies)) ->
                           (* we only deal with named functions *)
			   begin try
			     let l = rec_names_for c names in
			     substl (List.rev_map mkConst l) bodies.(i)
			   with Not_found ->
			     b
			   end
		       | _ -> 
			   b
		     in
		     let vars, t = decompose_lam b in
		     let n = List.length l in
		     let k = List.length vars in
		     assert (k <= n);
		     let vars, env = coq_rename_vars env vars in
		     let t = substl (List.map mkVar vars) t in
		     let t, vars, env = eta_expanse t vars env (n-k) in
		     let vars = List.rev vars in
		     let bv = vars in
		     let vars = List.map (fun x -> string_of_id x) vars in
		     let fol_var x =
		       Fol.App (x, []) in
		     let fol_vars = List.map fol_var vars in
		     let vars = List.combine vars l in
		     begin match d with
		       | DeclVar _ ->
			   begin match kind_of_term t with
			     | Case (ci, _, e, br) ->
				 equations_for_case env id vars bv ci e br
			     | _ -> 
				 let p = 
				   Fatom (Eq (App (id, fol_vars), 
					      tr_term bv env t)) 
				 in
				 [id, foralls vars p]
			   end
		       | DeclPred _ ->
			   let value = tr_formula bv env t in
			   let p = 
			     And (Imp (Fatom (Pred (id, fol_vars)), value),
				  Imp (value, Fatom (Pred (id, fol_vars))))
			   in
			   [id, foralls vars p]
		       | _ ->
			   assert false
		     end
		 | DeclType _ ->
		     raise NotFO
		 | Assert _ -> assert false)
	    in
	    let axioms = List.map (fun (id,ax) -> Assert (id, ax)) axioms in
	    globals_stack := axioms @ !globals_stack
	| None -> 
	    () (* Coq axiom *)
      end
  | IndRef i ->
      (*iter_all_constructors i
        (let rc = reference_of_constr c in
match tr_global c with
  | DeclVar(idc, l, _) ->
      (fun _ c -> List.map (fun co -> ) (liste des constructeurs � partir de c non compris));*)
      begin match d with
	| DeclPred _ ->
	    iter_all_constructors i
	      (fun _ c ->
		 let rc = reference_of_constr c in
		 try
		   begin match tr_global env rc with
		     | Assert _ -> ()
		     | _ -> assert false
		   end
		 with NotFO ->
		   ());
	| DeclType _ -> raise NotFO
	| _ -> assert false
      end
  | _ -> ()

and equations_for_case env id vars bv ci e br = match kind_of_term e with
  | Var x when List.exists (fun (y, _) -> string_of_id x = y) vars ->
      let eqs = ref [] in
      iter_all_constructors ci.ci_ind
	(fun j cj ->
	   try
	     let cjr = reference_of_constr cj in
	     begin match tr_global env cjr with
	       | DeclVar (idc, l, _) ->
		   let b = br.(j) in
		   let rec_vars, b = decompose_lam b in
		   let rec_vars, env = coq_rename_vars env rec_vars in
		   let b = substl (List.map mkVar rec_vars) b in
		   let rec_vars = List.rev rec_vars in
		   let bv = bv @ rec_vars in
		   let rec_vars = List.map string_of_id rec_vars in
		   let fol_var x =
		     Fol.App (x, []) in
		   let fol_rec_vars = List.map fol_var rec_vars in
		   let fol_rec_term = App (idc, fol_rec_vars) in
		   let rec_vars = List.combine rec_vars l in
		   let fol_vars = List.map fst vars in
		   let fol_vars = List.map fol_var fol_vars in
		   let fol_vars = List.map (fun y -> match y with
					      | App (id, _) ->
						  if id = string_of_id x
						  then fol_rec_term
						  else y
					      | _ -> y)
				    fol_vars in
		   let vars = vars @ rec_vars in
		   let rec remove l e = match l with
		     | [] -> []
		     | (y, t)::l' -> if y = string_of_id e then l'
		       else (y, t)::(remove l' e) in
		   let vars = remove vars x in
		   let p = 
		     Fatom (Eq (App (id, fol_vars), 
				tr_term bv env b))
		   in
		   eqs := (id ^ "_" ^ idc, foralls vars p) :: !eqs
	       | _ -> 
		   assert false end
	   with NotFO ->
	     ());
      !eqs
  | _ ->
      raise NotFO


(* assumption: t:T:Set *)
and tr_term bv env t =
  match kind_of_term t with
    | Term.App (f, [|a;b|]) when f = Lazy.force coq_Zplus -> 
	Plus (tr_term bv env a, tr_term bv env b)
    | Term.App (f, [|a;b|]) when f = Lazy.force coq_Zminus -> 
	Moins (tr_term bv env a, tr_term bv env b)
    | Term.App (f, [|a;b|]) when f = Lazy.force coq_Zmult -> 
	Mult (tr_term bv env a, tr_term bv env b)
    | Term.App (f, [|a;b|]) when f = Lazy.force coq_Zdiv -> 
	Div (tr_term bv env a, tr_term bv env b)
    | Term.Construct _ when t = Lazy.force coq_Z0 ->
	Cst 0
    | Term.App (f, [|a|]) when f = Lazy.force coq_Zpos ->
	fol_term_of_positive env a
    | Term.App (f, [|a|]) when f = Lazy.force coq_Zneg ->
	Moins (Cst 0, (fol_term_of_positive env a))
    | Term.Var id when List.mem id bv ->
	App (string_of_id id, [])
    | _ ->
	let f, cl = decompose_app t in
	begin try
	  let r = global_of_constr f in
	  match tr_global env r with
	    | DeclVar (s, _, _) -> 
		Fol.App (s, List.map (tr_term bv env) cl)
	    | _ -> 
		raise NotFO
	with 
	  | Not_found ->
	      raise NotFO
	  | NotFO -> (* we need to abstract some part of (f cl) *)
	      let rec abstract app = function
		| [] ->
		    Fol.App (make_term_abstraction env app, [])
		| x :: l as args ->
		    begin try
		      let s = make_term_abstraction env app in
		      Fol.App (s, List.map (tr_term bv env) args)
		    with NotFO ->
		      abstract (applist (app, [x])) l
		    end
	      in
	      let app,l = match cl with 
		| x :: l -> applist (f, [x]), l | _ -> raise NotFO
	      in
	      abstract app l
	end

and quantifiers n a b bv env =
  let vars, env = coq_rename_vars env [n,a] in
  let id = match vars with [x] -> x | _ -> assert false in
  let b = subst1 (mkVar id) b in
  let t = match tr_type env a with
    | [], t -> t
    | _ -> raise NotFO
  in
  let bv = id :: bv in
  id, t, bv, env, b

(* assumption: f is of type Prop *)
and tr_formula bv env f =
  let c, args = decompose_app f in
  match kind_of_term c, args with
    | Var id, [] -> 
	Fatom (Pred (rename_global (VarRef id), []))
    | _, [t;a;b] when c = build_coq_eq () ->
	let ty = Typing.type_of env Evd.empty t in
	if is_Set ty then
	  begin match tr_type env t with
	    | [], _ ->
		Fatom (Eq (tr_term bv env a, tr_term bv env b))
	    | _ -> raise NotFO
	  end
	else raise NotFO
    | _, [a;b] when c = Lazy.force coq_Zle ->
	Fatom (Le (tr_term bv env a, tr_term bv env b))
    | _, [a;b] when c = Lazy.force coq_Zlt ->
	Fatom (Lt (tr_term bv env a, tr_term bv env b))
    | _, [a;b] when c = Lazy.force coq_Zge ->
	Fatom (Ge (tr_term bv env a, tr_term bv env b))
    | _, [a;b] when c = Lazy.force coq_Zgt ->
	Fatom (Gt (tr_term bv env a, tr_term bv env b))
    | _, [] when c = build_coq_False () ->
	False
    | _, [] when c = build_coq_True () ->
	True
    | _, [a] when c = build_coq_not () ->
	Not (tr_formula bv env a)
    | _, [a;b] when c = build_coq_and () ->
	And (tr_formula bv env a, tr_formula bv env b)
    | _, [a;b] when c = build_coq_or () ->
	Or (tr_formula bv env a, tr_formula bv env b)
    | Prod (n, a, b), _ ->
	if is_imp_term f then
	  Imp (tr_formula bv env a, tr_formula bv env b)
	else
	  let id, t, bv, env, b = quantifiers n a b bv env in
	  Forall (string_of_id id, t, tr_formula bv env b)
    | _, [_; a] when c = build_coq_ex () ->
	begin match kind_of_term a with
	  | Lambda(n, a, b) ->
	      let id, t, bv, env, b = quantifiers n a b bv env in
	      Exists (string_of_id id, t, tr_formula bv env b)
	  | _ -> assert false
		(* a must be a Lambda since we are in the ex case *) end
    | _ ->
	begin try
	  let r = global_of_constr c in
	  match tr_global env r with
	    | DeclPred (s, _) -> 
		Fatom (Pred (s, List.map (tr_term bv env) args))
	    | _ -> 
		raise NotFO
	with Not_found ->
	  raise NotFO
	end


let tr_goal gl =
  Hashtbl.clear locals;
  let tr_one_hyp (id, ty) = 
    try
      let s = rename_global (VarRef id) in
      let d = tr_global_type (pf_env gl) s ty in
      Hashtbl.add locals id (Gfo d);
      d
    with NotFO ->
      Hashtbl.add locals id Gnot_fo;
      raise NotFO
  in
  let hyps =
    List.fold_right 
      (fun h acc -> try tr_one_hyp h :: acc with NotFO -> acc)
      (pf_hyps_types gl) []
  in
  let c = tr_formula [] (pf_env gl) (pf_concl gl) in
  let hyps = List.rev_append !globals_stack (List.rev hyps) in
  hyps, c


type prover = Simplify | CVCLite | Harvey | Zenon

let call_prover prover q = match prover with
  | Simplify -> Dp_simplify.call (Dp_sorts.query q)
  | CVCLite -> Dp_cvcl.call q
  | Harvey -> error "haRVey not yet interfaced"
  | Zenon -> Dp_zenon.call (Dp_sorts.query q)
  
let dp prover gl =
  let concl_type = pf_type_of gl (pf_concl gl) in
  if not (is_Prop concl_type) then error "Conclusion is not a Prop";
  try 
    let q = tr_goal gl in
    begin match call_prover prover q with
      | Valid -> Tactics.admit_as_an_axiom gl
      | Invalid -> error "Invalid"
      | DontKnow -> error "Don't know"
      | Timeout -> error "Timeout"
    end
  with NotFO ->
    error "Not a first order goal"
  

let simplify = tclTHEN intros (dp Simplify)
let cvc_lite = tclTHEN intros (dp CVCLite)
let harvey = dp Harvey
let zenon = tclTHEN intros (dp Zenon)

let dp_hint l =
  let env = Global.env () in
  let one_hint (qid,r) = 
    if not (mem_global r) then begin
      let ty = Global.type_of_global r in
      let s = Typing.type_of env Evd.empty ty in
      if is_Prop s then
	try
	  let id = rename_global r in
	  let d = Assert (id, tr_formula [] env ty) in
	  add_global r (Gfo d);
	  globals_stack := d :: !globals_stack
	with NotFO ->
	  add_global r Gnot_fo;
	  msg_warning
	    (pr_reference qid ++ 
	     str " ignored (not a first order proposition)")
	else begin
	  add_global r Gnot_fo;
	  msg_warning
	    (pr_reference qid ++ str " ignored (not a proposition)")
	end
    end
  in
  List.iter one_hint (List.map (fun qid -> qid, Nametab.global qid) l)