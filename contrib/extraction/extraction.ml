
(*i $Id$ i*)

open Pp
open Util
open Names
open Term
open Declarations
open Environ
open Reduction
open Inductive
open Instantiate
open Miniml
open Mlimport

(*s Extraction results. *)

(* The [signature] type is used to know how many arguments a CIC
   object expects, and what these arguments will become in the ML
   object. *)
   
(* The flag [type_var] gives us information about an identifier
   coming from a Lambda or a Product:
   \begin{itemize}
   \item [Varity] denotes identifiers of type an arity of sort $Set$
     or $Type$, that is $(x_1:X_1)\ldots(x_n:X_n)s$ with $s = Set$ or $Type$ 
   \item [Vprop] denotes identifiers of type an arity of sort $Prop$, 
     or of type of type $Prop$ 
   \item [Vdefault] represents the other cases 
   \end{itemize} *)

type type_var = Varity | Vprop | Vdefault

type signature = (type_var * identifier) list

(* The [type_extraction_result] is the result of the [extract_type] function
   that extracts a CIC object into an ML type. It is either: 
   \begin{itemize}
   \item a real ML type, followed by its signature and its list of dummy fresh 
     type variables (called flexible variables)
   \item a CIC arity, without counterpart in ML
   \item a non-informative type, which will receive special treatment
   \end{itemize} *)

type type_extraction_result =
  | Tmltype of ml_type * signature * identifier list
  | Tarity
  | Tprop

(* When dealing with CIC contexts, we maintain corresponding contexts 
   made of [type_extraction_result] *)

type extraction_context = (type_extraction_result * identifier) list

(* The [extraction_result] is the result of the [extract_constr]
   function that extracts an CIC object. It is either a ML type, a ML
   object or something non-informative. *)

type extraction_result =
  | Emltype of ml_type * signature * identifier list
  | Emlterm of ml_ast
  | Eprop

(*s Utility functions. *)

(* Translation between [Type_extraction_result] and [type_var]. *)

let v_of_t = function
  | Tprop -> Vprop
  | Tarity -> Varity
  | Tmltype _ -> Vdefault

(* Constructs ML arrow types *)

let ml_arrow = function
  | Tmltype (t,_,_), Tmltype (d,_,_) -> Tarr (t,d)
  | _, Tmltype (d,_,_) -> d
  | _ -> assert false

(* Collects new flexible variables list *)

let accum_flex t fl = match t with 
  | Tmltype (_,_,flt)-> flt 
  | _ -> fl

(* FIXME: to be moved somewhere else *)
let array_foldi f a =
  let n = Array.length a in
  let rec fold i v = if i = n then v else fold (succ i) (f i a.(i) v) in
  fold 0

let flexible_name = id_of_string "flex"

let id_of_name = function
  | Anonymous -> id_of_string "_"
  | Name id   -> id

(* This function [params_of_sign] extracts the type parameters ('a in Caml)
   from a signature. *)

let params_of_sign = 
  List.fold_left (fun l v -> match v with Varity,id -> id :: l | _ -> l) []

(* [get_arity c] returns [Some s] if [c] is an arity of sort [s], 
   and [None] otherwise. *)
(* FIXME: to be moved ? *)
let rec get_arity env c =
  match kind_of_term (whd_betadeltaiota env Evd.empty c) with
    | IsProd (x,t,c0) -> get_arity (push_rel_assum (x,t) env) c0
    | IsCast (t,_) -> get_arity env t
    | IsSort s -> Some s
    | _ -> None

(* The next function transforms an arity into a signature. It is used 
   for example with the types of inductive definitions, which are known
   to be already in arity form. *)

let signature_of_arity = 
  let rec sign_of acc env c = match kind_of_term c with
    | IsProd (n, t, c') ->
	let env' = push_rel (n,None,t) env in
	let id = id_of_name n in
	sign_of 
	  (((match get_arity env t with
	       | Some (Prop Null) -> Vprop
	       | Some _ -> Varity 
	       | _ -> Vdefault), id) :: acc)
	  env' c'
    | IsSort _ -> 
	acc
    | _ ->
	assert false
  in
  sign_of []

(* [list_of_ml_arrows] applied to the ML type [a->b->]\dots[z->t]
   returns the list [[a;b;...;z]]. It is used when making the ML types
   of inductive definitions. *)

let rec list_of_ml_arrows = function
  | Tarr (a, b) -> a :: list_of_ml_arrows b
  | t -> []

(* [renum_db] gives the new de Bruijn indices for variables in an ML term.
   This translation is made according to a context: only variables corresponding 
   to a real ML type are keeped *)
	
let renum_db ctx n = 
  let rec renum = function
    | (1, (Tmltype _,_)::_) -> 1
    | (n, (Tmltype _,_)::s) -> succ (renum (pred n, s))
    | (n,             _::s) -> renum (pred n, s)
    | _ -> assert false
  in
  renum (n, ctx)

(*s Tables to keep the extraction of inductive types and constructors. *)

type inductive_extraction_result = signature * identifier list

let inductive_extraction_table = 
  ref (Gmap.empty : (inductive_path, inductive_extraction_result) Gmap.t)

let add_inductive_extraction i e = 
  inductive_extraction_table := Gmap.add i e !inductive_extraction_table

let lookup_inductive_extraction i = Gmap.find i !inductive_extraction_table

type constructor_extraction_result = ml_type list * signature

let constructor_extraction_table = 
  ref (Gmap.empty : (constructor_path, constructor_extraction_result) Gmap.t)

let add_constructor_extraction c e = 
  constructor_extraction_table := Gmap.add c e !constructor_extraction_table

let lookup_constructor_extraction i = Gmap.find i !constructor_extraction_table

(*s Extraction of a type. *)

(* When calling [extract_type] we suppose that the type of [c] is an arity. 
   This is for example checked in [extract_constr]. 
   [c] might have $Prop$ as head symbol, or be of type an arity of sort $Prop$. 
   The context [ctx] is the extracted version of [env]. *)

let rec extract_type env ctx c =
  let genv = Global.env() in  (* QUESTION: inutile car env comme param? *)
  let rec extract_rec env ctx fl c args = 
    (* In [extract_rec] we accumulate the two contexts, the generated flexible 
       variables, and the arguments of c. *) 
    let ty = Typing.type_of env Evd.empty c in
    match get_arity env ty with 
      | None -> assert false (* Cf. precondition. *)
      | Some (Prop Null) ->
	  Tprop (* [c] is of type an arity of sort $Prop$. *)
      | Some _ -> 
	  (match kind_of_term (whd_betaiota c) with
	    | IsSort (Prop Null) ->
		assert (args = []); (* A sort can't be applied. *)
		Tprop (* [c] is $Prop$. *)
	    | IsSort _ ->
		assert (args = []); (* A sort can't be applied. *)
		Tarity 
	    | IsProd (n, t, d) ->
		assert (args = []); (* A product can't be applied. *)
		let id = id_of_name n in (* FIXME: capture problem *)
		let t' = extract_rec env ctx fl t [] in (* Extraction of [t]. *)
		let env' = push_rel (n,None,t) env in (* New context. *) 
		let ctx' = (t',id) :: ctx in (* New extracted context. *)
		let fl' = accum_flex t' fl in (* New flexible variables. *)
		let d' = extract_rec env' ctx' fl' d [] in (* Extraction of [d]. *)
		  (match d' with
		     | Tmltype (_, sign, fl'') -> 
			 Tmltype (ml_arrow (t',d'), (v_of_t t',id)::sign, fl'')
			   (* If [t] and [c] give ML types, we make an arrow type. *) 
		     | et -> et)
	    | IsLambda (n, t, d) ->
		assert (args = []); (* [c] is now in head normal form. *)
		let id = id_of_name n in (* FIXME: capture problem *)
		let t' = extract_rec env ctx fl t [] in (* Extraction of [t].*)
		let env' = push_rel (n,None,t) env in (* New context. *)
		let ctx' = (t',id) :: ctx in (* New extracted context. *)
		let fl' = accum_flex t' fl in (* New flexible variables. *)
		let d' = extract_rec env' ctx' fl' d [] in (* Extraction of [d]. *)
		  (match d' with
		     | Tmltype (ed, sign, fl'') ->
			 Tmltype (ed, (v_of_t t',id)::sign, fl'')
			   (* The extracted type is the extraction of [d], which may use a 
			      type variable corresponding to the lambda. *)
		     | et -> et)
	    | IsApp (d, args') ->
		extract_rec env ctx fl d (Array.to_list args' @ args)
		  (* We just accumulate the arguments. *)
	    | IsRel n ->
		(match List.nth ctx (pred n) with
		   | (Tprop | Tmltype _), _ -> assert false 
			 (* If head symbol is a variable, it must be of type an arity, 
			    and we already dealt with the case of an arity of sort $Prop$. *)
		   | Tarity, id -> Tmltype (Tvar id, [], fl)
			 (* A variable of type an arity gives an ML type variable. *))
	    | IsConst (sp,a) ->
		let cty = constant_type genv Evd.empty (sp,a) in 
		  (* QUESTION: env plutot que genv ? *)
		  if is_arity env Evd.empty cty then
		    (match extract_constant sp with
		       | Emltype (_, sc, flc) -> 
			   extract_type_app env ctx fl (ConstRef sp,sc,flc) args
		       | Eprop -> Tprop
		       | Emlterm _ -> assert false (* The head symbol must be of type an arity. *))
		  else 
		    (* We can't keep as ML type abbreviation a CIC constant which type is 
		       not an arity. So we reduce this constant. *)
		    let cvalue = constant_value env (sp,a) in
		      extract_rec env ctx fl (mkApp (cvalue, Array.of_list args)) []
	    | IsMutInd (spi,_) ->
		let (si,fli) = extract_inductive spi in
		  extract_type_app env ctx fl (IndRef spi,si,fli) args
	    | IsMutCase _ 
	    | IsFix _ ->
		let id = next_ident_away flexible_name fl in
		  Tmltype (Tvar id, [], id :: fl)
		    (* CIC type without counterpart in ML. We generate a fresh type variable and add
		       it in the "flexible" list. Cf Obj.magic mechanism *)
	    | IsCast (c, _) ->
		extract_rec env ctx fl c args
	    | _ -> 
		assert false)

 (* Auxiliary function dealing with type application. *)
		  
  and extract_type_app env ctx fl (r,sc,flc) args =
    let nargs = List.length args in
    assert (List.length sc >= nargs); 
      (* [r] is of type an arity, so it can't be applied to more than n args, 
	 where n is the number of products in this arity type. *)
    let (sign_args,sign_rest) = list_chop nargs sc in
      (* We split the signature in used and unused parts *)
    let (mlargs,fl') = 
      List.fold_right 
	(fun (v,a) ((args,fl) as acc) -> match v with
	   | (Vdefault | Vprop), _ -> acc (* Here we only keep arguments of type an arity. *)
	   | Varity,_ -> match extract_rec env ctx fl a [] with
	       | Tarity -> (Miniml.Tarity :: args, fl) 
		     (* we need to pass an argument, so we pass a dummy type [arity] *)
	       | Tprop -> (Miniml.Tprop :: args, fl)
	       | Tmltype (mla,_,fl') -> (mla :: args, fl'))
	(List.combine sign_args args) 
	([],fl)
    in
    let flc = List.map (fun i -> Tvar i) flc in
    Tmltype (Tapp ((Tglob r) :: mlargs @ flc), sign_rest, fl')

  in
  extract_rec env ctx [] c []


(*s Extraction of a term. *)

(* Preconditions: [c] has a type which is not an arity. 
   This is normaly checked in [extract_constr] *)

and extract_term c =
  let rec extract_rec env ctx c =
    let t = Typing.type_of env Evd.empty c in 
    let s = Typing.type_of env Evd.empty t in
      if is_Prop (whd_betadeltaiota env Evd.empty s) then
	Eprop (* Sort of [c] is $Prop$ *)
	  (* We needn't check whether type of [c] is informative because of the precondition *)
      else match kind_of_term c with
	| IsLambda (n, t, d) ->
	    let id = id_of_name n in
	    let t' = extract_type env ctx t in 
	    let env' = push_rel (n,None,t) env in
	    let ctx' = (t',id) :: ctx in
	    let d' = extract_rec env' ctx' d in 
	      (match t' with
		 | Tarity | Tprop -> d'
		 | Tmltype _ -> match d' with
		     | Emlterm a -> Emlterm (MLlam (id, a))
		     | Eprop -> Eprop
		     | Emltype _ -> assert false (* extract_type can't answer Emltype *))
	| IsRel n ->
	    (match List.nth ctx (pred n) with
	       | Tarity,_ -> assert false (* Cf. precondition *)
	       | Tprop,_ -> Eprop
	       | Tmltype _, _ -> Emlterm (MLrel (renum_db ctx n))) 
	    (* TODO : magic or not *) 
	| IsApp (f,a) ->
	    let tyf = Typing.type_of env Evd.empty f in
	    let tyf = 
	      if nb_prod tyf >= Array.length a then 
		tyf 
	      else 
		whd_betadeltaiota env Evd.empty tyf 
	    in
	      (match extract_type env ctx tyf with
		 | Tmltype (_,s,_) -> extract_app env ctx (f,s) (Array.to_list a) 
		 | Tarity -> assert false (* Cf. precondition *)
		 | Tprop -> Eprop)
	| IsConst (sp,_) ->
	    Emlterm (MLglob (ConstRef sp)) (* TODO eta-expansion *)
	| IsMutConstruct (cp,_) ->
	    Emlterm (MLglob (ConstructRef cp))
	| IsMutCase _ ->
	    failwith "todo"
	| IsFix _ ->
	    failwith "todo"
	| IsLetIn (n, c1, t1, c2) ->
	    failwith "todo"
	      (*i	  (match get_arity env t1 with
		| Some (Prop Null) -> *)
	| IsCast (c, _) ->
	    extract_rec env ctx c
	| IsMutInd _ | IsProd _ | IsSort _ | IsVar _ 
	| IsMeta _ | IsEvar _ | IsCoFix _ ->
	    assert false 

  and extract_app env ctx (f,sf) args =
    let nargs = List.length args in
    assert (List.length sf >= nargs);
    let mlargs = 
      List.fold_right 
	(fun (v,a) args -> match v with
	   | (Varity | Vprop), _ -> args
	   | Vdefault,_ -> match extract_rec env ctx a with
	       | Emltype _ -> assert false (* FIXME: et si !! *)
	       | Eprop -> MLprop :: args
	       | Emlterm mla -> mla :: args)
	(List.combine (list_firstn nargs sf) args)
	[]
    in
    match extract_rec env ctx f with
      | Emlterm f' -> Emlterm (MLapp (f', mlargs))
      | Emltype _ | Eprop -> assert false (* FIXME: to check *)

  in
  extract_rec (Global.env()) [] c

(*s Extraction of a constr. *)

and extract_constr_with_type c t =
  let genv = Global.env () in
  let s = Typing.type_of genv Evd.empty t in
  if is_Prop (whd_betadeltaiota genv Evd.empty s) then
      Eprop (* sort of [c] is $Prop$ *)
  else match get_arity genv t with
    | Some (Prop Null) -> 
	Eprop (* type of [c] is an arity of sort $Prop$ *) 
    | Some _ -> 
	(match extract_type genv [] c with
	   | Tprop -> Eprop (* [c] is an arity of sort $Prop$ *)
	   | Tarity -> Emltype(Miniml.Tarity, [], [])
	       (*i error "not an ML type"  *)
	       (* [c] is any other arity *)
	   | Tmltype (t, sign, fl) -> Emltype (t, sign, fl))
    | None -> 
	extract_term c
	    
and extract_constr c = 
  extract_constr_with_type c (Typing.type_of (Global.env()) Evd.empty c)

(*s Extraction of a constant. *)
		
and extract_constant sp =
  let cb = Global.lookup_constant sp in
  let typ = cb.const_type in
  let body = match cb.const_body with Some c -> c | None -> assert false in (* QUESTION: Axiomes ici ?*)
  extract_constr_with_type body typ
    
(*s Extraction of an inductive. *)
    
and extract_inductive ((sp,_) as i) =
  extract_mib sp;
  lookup_inductive_extraction i
			     
and extract_constructor (((sp,_),_) as c) =
  extract_mib sp;
  lookup_constructor_extraction c

and extract_mib sp =
  if not (Gmap.mem (sp,0) !inductive_extraction_table) then begin
    let mib = Global.lookup_mind sp in
    let genv = Global.env () in
    (* first pass: we store inductive signatures together with empty flex. *)
    Array.iteri
      (fun i ib -> add_inductive_extraction (sp,i) 
	   (signature_of_arity genv ib.mind_nf_arity, []))
      mib.mind_packets;
    (* second pass: we extract constructors arities and we accumulate
       all flexible variables. *)
    let fl = 
      array_foldi
	(fun i ib fl ->
	   let mis = build_mis ((sp,i),[||]) mib in
	   array_foldi
	     (fun j _ fl -> 
		let t = mis_constructor_type (succ j) mis in
		match extract_type genv [] t with
		  | Tarity | Tprop -> assert false
		  | Tmltype (mlt, s, f) -> 
		      let l = list_of_ml_arrows mlt in
		      (*i
			let (l,s) = extract_params mib.mind_nparams (l,s) in
		      i*)
		      add_constructor_extraction ((sp,i),succ j) (l,s);
		      f @ fl)
	     ib.mind_nf_lc fl)
	mib.mind_packets []
    in
    (* third pass: we update the inductive flexible variables. *)
    for i = 0 to mib.mind_ntypes - 1 do
      let (s,_) = lookup_inductive_extraction (sp,i) in
      add_inductive_extraction (sp,i) (s,fl)
    done
  end
    
(*s Extraction of a global reference i.e. a constant or an inductive. *)
    
and extract_inductive_declaration sp =
  extract_mib sp;
  let mib = Global.lookup_mind sp in
  let one_constructor ind j id = 
    let (t,_) = lookup_constructor_extraction (ind,succ j) in (id, t)
  in
  let one_inductive i ip =
    let (s,fl) = lookup_inductive_extraction (sp,i) in
    (params_of_sign s @ fl, ip.mind_typename, 
     Array.to_list (Array.mapi (one_constructor (sp,i)) ip.mind_consnames))
  in
  Dtype (Array.to_list (Array.mapi one_inductive mib.mind_packets))

(*s ML declaration from a reference. *)

let extract_declaration = function
  | ConstRef sp -> 
      let id = basename sp in (* FIXME *)
      (match extract_constant sp with
	 | Emltype (mlt, s, fl) -> Dabbrev (id, params_of_sign s @ fl, mlt)
	 | Emlterm t -> Dglob (id, t)
	 | Eprop -> Dglob (id, MLprop))
  | IndRef (sp,_) -> extract_inductive_declaration sp
  | ConstructRef ((sp,_),_) -> extract_inductive_declaration sp
  | VarRef _ -> assert false

(*s Registration of vernac commands for extraction. *)

module Pp = Ocaml.Make(struct let pp_global = Printer.pr_global end)

open Vernacinterp

let _ = 
  vinterp_add "Extraction"
    (function 
       | [VARG_CONSTR ast] ->
	   (fun () -> 
	      let c = Astterm.interp_constr Evd.empty (Global.env()) ast in
	      match kind_of_term c with
		(* If it is a global reference, then output the declaration *)
		| IsConst (sp,_) -> 
		    mSGNL (Pp.pp_decl (extract_declaration (ConstRef sp)))
		| IsMutInd (ind,_) ->
		    mSGNL (Pp.pp_decl (extract_declaration (IndRef ind)))
		| IsMutConstruct (cs,_) ->
		    mSGNL (Pp.pp_decl (extract_declaration (ConstructRef cs)))
		(* Otherwise, output the ML type or expression *)
		| _ ->
		    match extract_constr c with
		      | Emltype (t,_,_) -> mSGNL (Pp.pp_type t)
		      | Emlterm a -> mSGNL (Pp.pp_ast a)
		      | Eprop -> message "prop")
       | _ -> assert false)

