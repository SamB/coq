
(* $Id$ *)

open Pp
open Util
open Names
open Sign
open Univ
open Generic
open Term
open Declarations
open Abstraction

(* The type of environments. *)

type checksum = int

type import = string * checksum

type global = Constant | Inductive | Abstraction

type globals = {
  env_constants : constant_body Spmap.t;
  env_inductives : mutual_inductive_body Spmap.t;
  env_abstractions : abstraction_body Spmap.t;
  env_locals : (global * section_path) list;
  env_imports : import list }

type context = {
  env_var_context : var_context;
  env_rel_context : rel_context }

type env = {
  env_context : context;
  env_globals : globals;
  env_universes : universes }

let empty_context = {
  env_var_context = empty_var_context;
  env_rel_context = empty_rel_context }
  
let empty_env = { 
  env_context = empty_context;
  env_globals = {
    env_constants = Spmap.empty;
    env_inductives = Spmap.empty;
    env_abstractions = Spmap.empty;
    env_locals = [];
    env_imports = [] };
  env_universes = initial_universes }

let universes env = env.env_universes
let context env = env.env_context
let var_context env = env.env_context.env_var_context
let rel_context env = env.env_context.env_rel_context

(* Construction functions. *)

let map_context f env =
  let context = env.env_context in
  { env with
      env_context = {
	context with
	  env_var_context = map_var_context f context.env_var_context ;
	  env_rel_context = map_rel_context f context.env_rel_context } }

let var_context_app f env =
  { env with
      env_context = { env.env_context with
			env_var_context = f env.env_context.env_var_context } }

let change_hyps = var_context_app

let push_var d   = var_context_app (add_var d)
let push_var_def def   = var_context_app (add_var_def def)
let push_var_decl decl = var_context_app (add_var_decl decl)
let pop_var id         = var_context_app (pop_var id)

let rel_context_app f env =
  { env with
      env_context = { env.env_context with
			env_rel_context = f env.env_context.env_rel_context } }

let reset_context env =
  { env with
      env_context = { env_var_context = empty_var_context;
		      env_rel_context = empty_rel_context} }

let fold_var_context f env a =
  snd (Sign.fold_var_context
	 (fun d (env,e) -> (push_var d env, f env d e))
         (var_context env) (reset_context env,a))

let process_var_context f env =
  Sign.fold_var_context
    (fun d env -> f env d) (var_context env) (reset_context env)

let process_var_context_both_sides f env =
  fold_var_context_both_sides f (var_context env) (reset_context env)

let push_rel d   = rel_context_app (add_rel d)
let push_rel_def def   = rel_context_app (add_rel_def def)
let push_rel_decl decl = rel_context_app (add_rel_decl decl)
let push_rels ctxt     = rel_context_app (concat_rel_context ctxt)

let push_rels_to_vars env =
  let sign0 = env.env_context.env_var_context in
  let (subst,_,sign) =
  List.fold_right
    (fun (na,c,t) (subst,avoid,sign) ->
       let na = if na = Anonymous then Name(id_of_string"_") else na in
       let id = next_name_away na avoid in
       ((VAR id)::subst,id::avoid,
	add_var (id,option_app (substl subst) c,typed_app (substl subst) t)
	  sign))
    env.env_context.env_rel_context ([],ids_of_var_context sign0,sign0)
  in subst, (var_context_app (fun _ -> sign) env)

let reset_rel_context env =
  { env with
      env_context = { env_var_context = env.env_context.env_var_context;
		      env_rel_context = empty_rel_context} }

let fold_rel_context f env a =
  snd (List.fold_right
	 (fun d (env,e) -> (push_rel d env, f env d e))
         (rel_context env) (reset_rel_context env,a))

let process_rel_context f env =
  List.fold_right (fun d env -> f env d)
    (rel_context env) (reset_rel_context env)

let instantiate_vars = instantiate_sign

let ids_of_context env = 
  (ids_of_rel_context env.env_context.env_rel_context)
  @ (ids_of_var_context env.env_context.env_var_context)

let names_of_rel_context env =
  names_of_rel_context env.env_context.env_rel_context

let set_universes g env =
  if env.env_universes == g then env else { env with env_universes = g }

let add_constraints c env =
  if c == Constraint.empty then 
    env 
  else 
    { env with env_universes = merge_constraints c env.env_universes }

let add_constant sp cb env =
  let new_constants = Spmap.add sp cb env.env_globals.env_constants in
  let new_locals = (Constant,sp)::env.env_globals.env_locals in
  let new_globals = 
    { env.env_globals with 
	env_constants = new_constants; 
	env_locals = new_locals } in
  { env with env_globals = new_globals }

let add_mind sp mib env =
  let new_inds = Spmap.add sp mib env.env_globals.env_inductives in
  let new_locals = (Inductive,sp)::env.env_globals.env_locals in
  let new_globals = 
    { env.env_globals with 
	env_inductives = new_inds;
	env_locals = new_locals } in
  { env with env_globals = new_globals }

let add_abstraction sp ab env =
  let new_abs = Spmap.add sp ab env.env_globals.env_abstractions in
  let new_locals = (Abstraction,sp)::env.env_globals.env_locals in
  let new_globals = 
    { env.env_globals with 
	env_abstractions = new_abs;
	env_locals = new_locals } in
  { env with env_globals = new_globals }

let meta_ctr=ref 0;;

let new_meta ()=incr meta_ctr;!meta_ctr;;

(* Access functions. *)
  
let lookup_var_type id env =
  lookup_id_type id env.env_context.env_var_context

let lookup_var_value id env =
  lookup_id_value id env.env_context.env_var_context

let lookup_var id env = lookup_id id env.env_context.env_var_context

let lookup_rel_type n env =
  Sign.lookup_rel_type n env.env_context.env_rel_context

let lookup_rel_value n env =
  Sign.lookup_rel_value n env.env_context.env_rel_context

let lookup_constant sp env =
  Spmap.find sp env.env_globals.env_constants

let lookup_mind sp env =
  Spmap.find sp env.env_globals.env_inductives

let lookup_abst sp env =
  Spmap.find sp env.env_globals.env_abstractions

(* First character of a constr *)

let lowercase_first_char id = String.lowercase (first_char id)

(* id_of_global gives the name of the given sort oper *)
let id_of_global env = function
  | Const sp -> 
      basename sp
  | Evar ev ->
      id_of_string ("?" ^ string_of_int ev)
  | MutInd (sp,tyi) -> 
      (* Does not work with extracted inductive types when the first 
	 inductive is logic : if tyi=0 then basename sp else *)
      let mib = lookup_mind sp env in
      let mip = mind_nth_type_packet mib tyi in
      mip.mind_typename
  | MutConstruct ((sp,tyi),i) ->
      let mib = lookup_mind sp env in
      let mip = mind_nth_type_packet mib tyi in
      assert (i <= Array.length mip.mind_consnames && i > 0);
      mip.mind_consnames.(i-1)
  | _ -> 
      assert false

let hdchar env c = 
  let rec hdrec k = function
    | DOP2((Prod|Lambda),_,DLAM(_,c))     -> hdrec (k+1) c
    | DOP2(Cast,c,_)             -> hdrec k c
    | DOPN(AppL,cl)              -> hdrec k (array_hd cl)
    | DOPN(Const _,_) as x ->
	let c = lowercase_first_char (basename (path_of_const x)) in
	if c = "?" then "y" else c
    | DOPN(Abst _,_) as x ->
	lowercase_first_char (basename (path_of_abst x))
    | DOPN(MutInd (sp,i) as x,_) ->
	if i=0 then 
	  lowercase_first_char (basename sp)
	else 
	  let na = id_of_global env x in lowercase_first_char na
    | DOPN(MutConstruct(sp,i) as x,_) ->
	let na = id_of_global env x in String.lowercase(List.hd(explode_id na))
    | VAR id  -> lowercase_first_char id
    | DOP0(Sort s) -> sort_hdchar s
    | Rel n ->
	(if n<=k then "p" (* the initial term is flexible product/function *)
	 else
	   try match lookup_rel_type (n-k) env with
	     | Name id,_ -> lowercase_first_char id
	     | Anonymous,t -> hdrec 0 (lift (n-k) (body_of_type t))
	   with Not_found -> "y")
    | _ -> "y"
  in 
  hdrec 0 c

let id_of_name_using_hdchar env a = function
  | Anonymous -> id_of_string (hdchar env a) 
  | Name id   -> id

let named_hd env a = function
  | Anonymous -> Name (id_of_string (hdchar env a)) 
  | x         -> x

let prod_name   env (n,a,b) = mkProd (named_hd env a n) a b
let lambda_name env (n,a,b) = mkLambda (named_hd env a n) a b

let it_prod_name   env = List.fold_left (fun c (n,t) ->prod_name env (n,t,c)) 
let it_lambda_name env = List.fold_left (fun c (n,t) ->lambda_name env (n,t,c))

let prod_create   env (a,b) = mkProd (named_hd env a Anonymous) a b
let lambda_create env (a,b) =  mkLambda (named_hd env a Anonymous) a b

let name_assumption env (na,c,t) =
  match c with
    | None      -> (named_hd env (body_of_type t) na, None, t)
    | Some body -> (named_hd env body na, c, t)

let prod_assum_name env b d = mkProd_or_LetIn (name_assumption env d) b 
let lambda_assum_name env b d = mkLambda_or_LetIn (name_assumption env d) b 

let it_mkProd_or_LetIn_name   env = List.fold_left (prod_assum_name env)
let it_mkLambda_or_LetIn_name env = List.fold_left (lambda_assum_name env)

let it_mkProd_or_LetIn   = List.fold_left (fun c d -> mkProd_or_LetIn d c)
let it_mkLambda_or_LetIn = List.fold_left (fun c d -> mkLambda_or_LetIn d c)

let it_mkNamedProd_or_LetIn = it_var_context_quantifier mkNamedProd_or_LetIn
let it_mkNamedLambda_or_LetIn = it_var_context_quantifier mkNamedLambda_or_LetIn

let make_all_name_different env =
  let avoid = ref (ids_of_var_context (var_context env)) in
  process_rel_context
    (fun newenv (na,c,t) -> 
       let id = next_name_away na !avoid in
       avoid := id::!avoid;
       push_rel (Name id,c,t) newenv)
    env

(* Abstractions. *)

let evaluable_abst env = function
  | DOPN (Abst _,_) -> true
  | _ -> invalid_arg "evaluable_abst"

let translucent_abst env = function
  | DOPN (Abst _,_) -> false
  | _ -> invalid_arg "translucent_abst"

let abst_value env = function
  | DOPN(Abst sp, args) ->
      contract_abstraction (lookup_abst sp env) args
  | _ -> invalid_arg "abst_value"

let defined_constant env = function
  | DOPN (Const sp, _) -> is_defined (lookup_constant sp env)
  | _ -> invalid_arg "defined_constant"

let opaque_constant env = function
  | DOPN (Const sp, _) -> is_opaque (lookup_constant sp env)
  | _ -> invalid_arg "opaque_constant"

(* A const is evaluable if it is defined and not opaque *)
let evaluable_constant env k =
  try 
    defined_constant env k && not (opaque_constant env k)
  with Not_found -> 
    false

(*s Modules (i.e. compiled environments). *)

type compiled_env = {
  cenv_id : string;
  cenv_stamp : checksum;
  cenv_needed : import list;
  cenv_constants : (section_path * constant_body) list;
  cenv_inductives : (section_path * mutual_inductive_body) list;
  cenv_abstractions : (section_path * abstraction_body) list }

let exported_objects env =
  let gl = env.env_globals in
  let separate (cst,ind,abs) = function
    | (Constant,sp) -> (sp,Spmap.find sp gl.env_constants)::cst,ind,abs
    | (Inductive,sp) -> cst,(sp,Spmap.find sp gl.env_inductives)::ind,abs
    | (Abstraction,sp) -> cst,ind,(sp,Spmap.find sp gl.env_abstractions)::abs
  in
  List.fold_left separate ([],[],[]) gl.env_locals

let export env id = 
  let (cst,ind,abs) = exported_objects env in
  { cenv_id = id;
    cenv_stamp = 0;
    cenv_needed = env.env_globals.env_imports;
    cenv_constants = cst;
    cenv_inductives = ind;
    cenv_abstractions = abs }

let check_imports env needed =
  let imports = env.env_globals.env_imports in
  let check (id,stamp) =
    try
      let actual_stamp = List.assoc id imports in
      if stamp <> actual_stamp then
	error ("Inconsistent assumptions over module " ^ id)
    with Not_found -> 
      error ("Reference to unknown module " ^ id)
  in
  List.iter check needed

let import_constraints g sp cst =
  try
    merge_constraints cst g
  with UniverseInconsistency ->
    errorlabstrm "import_constraints"
      [< 'sTR "Universe Inconsistency during import of"; 'sPC; print_sp sp >]

let import cenv env =
  check_imports env cenv.cenv_needed;
  let add_list t = List.fold_left (fun t (sp,x) -> Spmap.add sp x t) t in
  let gl = env.env_globals in
  let new_globals = 
    { env_constants = add_list gl.env_constants cenv.cenv_constants;
      env_inductives = add_list gl.env_inductives cenv.cenv_inductives;
      env_abstractions = add_list gl.env_abstractions cenv.cenv_abstractions;
      env_locals = gl.env_locals;
      env_imports = (cenv.cenv_id,cenv.cenv_stamp) :: gl.env_imports }
  in
  let g = universes env in
  let g = List.fold_left 
	    (fun g (sp,cb) -> import_constraints g sp cb.const_constraints) 
	    g cenv.cenv_constants in
  let g = List.fold_left 
	    (fun g (sp,mib) -> import_constraints g sp mib.mind_constraints) 
	    g cenv.cenv_inductives in
  { env with env_globals = new_globals; env_universes = g }

(*s Judgments. *)

type unsafe_judgment = { 
  uj_val : constr;
  uj_type : typed_type }

type unsafe_type_judgment = { 
  utj_val : constr;
  utj_type : sorts }
