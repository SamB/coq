(******************************************************************************)
(*                                                                            *)
(*                               PROJECT HELM                                 *)
(*                                                                            *)
(*                     A tactic to print Coq objects in XML                   *)
(*                                                                            *)
(*                Claudio Sacerdoti Coen <sacerdot@cs.unibo.it>               *)
(*                                 02/12/1999                                 *)
(*                                                                            *)
(* This module defines the functions that implements the new commands         *)
(*                                                                            *)
(******************************************************************************)


(* CONFIGURATION PARAMETERS *)

let dtdname = "http://localhost:8081/getdtd?url=cic.dtd";;
let verbose = ref true;; (* always set to true during a "Print XML All" *)

(* UTILITY FUNCTIONS *)

let print_if_verbose s = if !verbose then print_string s;;

type tag =
   Constant
 | Inductive
 | Variable
;;

(* Next exception is used only inside print_object and tag_of_string_tag *)
exception Uninteresting;;

let tag_of_string_tag =
 function
    "CONSTANT"
  | "PARAMETER"       -> Constant
  | "INDUCTIVE"       -> Inductive
  | "VARIABLE"        -> Variable
  | _                 -> raise Uninteresting
;;

let ext_of_tag =
 function
    Constant  -> "con"
  | Inductive -> "ind"
  | Variable  -> "var"
;;

(* could_have_namesakes sp = true iff o is an object that could be cooked and *)
(* than that could exists in cooked form with the same name in a super        *)
(* section of the actual section                                              *)
let could_have_namesakes o sp =      (* namesake = omonimo in italian *)
 let module D = Declare in
  let tag = Libobject.object_tag o in
   print_if_verbose ("Object tag: " ^ tag ^ "\n") ;
   match tag with
      "CONSTANT" ->
        (match D.constant_strength sp with
            D.DischargeAt _  -> false (* a local definition *)
          | D.NeverDischarge -> true  (* a non-local one    *)
        )
    | "PARAMETER"                 (* axioms and                               *)
    | "INDUCTIVE"       -> true   (* mutual inductive types are never local   *)
    | "VARIABLE"        -> false  (* variables are local, so no namesakes     *)
    | _                 -> false  (* uninteresting thing that won't be printed*)
;;

(*V7*)
exception Not_match
let trim_wrong_uri_prefix pref {System.relative_subdir=rs ; System.directory=d} =
(*
 let map =
  [(".","/prove");
   ("/home/pauillac/coq3/sacerdot/V7/theories/Arith","/coq/Arith");
   ("/home/pauillac/coq3/sacerdot/V7/theories/Bool","/coq/Bool");
   ("/home/pauillac/coq3/sacerdot/V7/theories/Init","/coq/Init");
   ("/home/pauillac/coq3/sacerdot/V7/theories/Lists","/coq/Lists");
   ("/home/pauillac/coq3/sacerdot/V7/theories/Logic","/coq/Logic");
   ("/home/pauillac/coq3/sacerdot/V7/theories/Reals","/coq/Reals");
   ("/home/pauillac/coq3/sacerdot/V7/theories/Relations","/coq/Relations");
   ("/home/pauillac/coq3/sacerdot/V7/theories/Sets","/coq/Sets");
   ("/home/pauillac/coq3/sacerdot/V7/theories/Zarith","/coq/Zarith");
   ("/home/pauillac/coq3/sacerdot/V7/contrib/ring","/coq/contrib/ring");
   ("/home/pauillac/coq3/sacerdot/V7/contrib/omega","/coq/contrib/omega")
  ] in
 let try_trim (inp,out) =
  for i = 0 to String.length inp - 1 do
   if inp.[i] <> pref.[i] then raise Not_match
  done ;
  out
 in
 let rec trim =
  function
     [] -> assert false (*V7 WHAT NOW? *)
   | he::tl ->
      try
       try_trim he
      with
       _ -> trim tl
 in
  trim map
*)
  "/" ^ rs
;;


(* uri_of_path sp is a broken (wrong) uri pointing to the object whose        *)
(* section path is sp                                                         *)
let uri_of_path sp tag =
 let module N = Names in
  let ext_of_sp sp = ext_of_tag tag in
   let (sl,id,_) = N.repr_path sp in
    let module_path =
     match sl with
        []             -> assert false (*V7 WHAT NOW? *)
      | module_name::_ ->
	  let (prefix,file) = Library.module_filename module_name in
          trim_wrong_uri_prefix file prefix
   in
    "cic:" ^ module_path ^ "/" ^ (String.concat "/" sl) ^ "/" ^
     (N.string_of_id id) ^ "." ^ (ext_of_sp sp)
;;

let string_of_sort =
 let module T = Term in
  function
     T.Prop(T.Pos)  -> "Set"
   | T.Prop(T.Null) -> "Prop"
   | T.Type(_)      -> "Type"
;;

let string_of_name =
 let module N = Names in
  function
     N.Name id -> N.string_of_id id
   | _         -> Util.anomaly "this should not happen"
;;

(* A SIMPLE DATA STRUCTURE AND SOME FUNCTIONS TO MANAGE THE CURRENT *)
(* ENVIRONMENT (= [l1, ..., ln] WHERE li IS THE LIST OF VARIABLES   *)
(* DECLARED IN THE i-th SUPER-SECTION OF THE CURRENT SECTION        *)

(*CSC: commento sbagliato ed obsoleto *)
(* list of variables availables in the actual section *)
let pvars = ref ([[]] : string list list);;
let cumenv = ref Environ.empty_env;;

let string_of_vars_list =
 let add_prefix n s = string_of_int n ^ ": " ^ s in
 let rec aux =
  function
     [n,v] -> (n,v)
   | (n,v)::tl ->
      let (k,s) = aux tl in
       if k = n then (k, v ^ " " ^ s) else (n, v ^ " " ^ add_prefix k s)
   | [] -> assert false
 in
  function
     [] -> ""
   | vl -> let (k,s) = aux vl in add_prefix k s
;;

(*
let string_of_pvars pvars hyps =
 let rec aux =
  function
     [] -> (0, "")
   | he::tl -> 
      let (n,s) = aux tl in
       (n + 1,
        string_of_int n ^ ": " ^ (String.concat " ") (List.rev he) ^
         match s with "" -> "" | _ -> " " ^ s 
       )
 in
  snd (aux (List.rev pvars))
;;
*)

let string_of_pvars pvars hyps =
 let find_depth pvars v =
  let rec aux n =
   function
      [] -> assert false
(* (-1,"?") For Print XML *)
(*
print_string "\nPVARS:" ;
List.iter (List.iter print_string) pvars ;
print_string "\nHYPS:" ;
List.iter print_string hyps ;
print_string "\n" ;
flush stdout ;
assert false
*)
    | l::_ when List.mem v l -> (n,v)
    | _::tl -> aux (n+1) tl
  in
   aux 0 pvars
 in
  string_of_vars_list (List.map (find_depth pvars) (List.rev hyps))
;;

type variables_type = 
   Definition of string * Term.constr * Term.types
 | Assumption of string * Term.constr
;;

let add_to_pvars x =
 let module E = Environ in
  let v =
   match x with
      Definition (v, bod, typ) ->
       cumenv := E.push_named_def (Names.id_of_string v, bod, typ) !cumenv ;
       v
    | Assumption (v, typ) ->
       cumenv := E.push_named_assum (Names.id_of_string v, typ) !cumenv ;
       v
  in
   match !pvars with
      []       -> assert false
    | (he::tl) -> pvars := (v::he)::tl
;;

let get_depth_of_var v =
 let rec aux n =
  function
     [] -> None
   | (he::tl) -> if List.mem v he then Some n else aux (n + 1) tl
 in
  aux 0 !pvars
;;

(* FUNCTIONS TO CREATE IDENTIFIERS *)

(* seed to create the next identifier *)
let next_id = ref 0;;

(* reset_id () reset the identifier seed to 0 *)
let reset_id () =
 next_id := 0
;;

(* get_next_id () returns fresh identifier *)
let get_next_id () =
 let res = 
  "i" ^ string_of_int !next_id
 in
  incr next_id ;
  res
;;

(* FUNCTION TO PRINT A SINGLE TERM OF CIC *)
(* print_term t l where t is a term of Cic returns a stream of XML tokens *)
(* suitable to be printed via the pretty printer Xml.pp. l is the list of *)
(* bound names                                                            *)
let print_term inner_types l env csr =
 let module N = Names in
 let module E = Environ in
 let module T = Term in
 let module X = Xml in
 let module R = Retyping in
  let rec names_to_ids =
   function
      [] -> []
    | (N.Name id)::l -> id::(names_to_ids l)
    | _ -> names_to_ids l
  in

  let rec inner_type_display l env term =
   let type_of_term = R.get_type_of env (Evd.empty) term in
   match R.get_sort_of env (Evd.empty) type_of_term with
      T.Prop (T.Null) -> Some (term_display l env type_of_term)
    | _               -> None

  and term_display l env cstr =
   let xmlinnertype = inner_type_display l env cstr in
   let next_id = get_next_id () in
    inner_types := (next_id, xmlinnertype)::!inner_types ;
   (* kind_of_term helps doing pattern matching hiding the lower level of *)
   (* coq coding of terms (the one of the logical framework)              *)
   match T.kind_of_term cstr with
     T.IsRel n  ->
      (match List.nth l (n - 1) with
          N.Name id ->
            X.xml_empty "REL"
             ["value",(string_of_int n) ;
              "binder",(N.string_of_id id) ;
              "id", next_id]
        | N.Anonymous ->
(*V7Local assert false*)
X.xml_empty "REL" ["binder","BUG"]
     )
   | T.IsVar id ->
      let depth =
       match get_depth_of_var (N.string_of_id id) with
          None -> "?" (* when printing via Show XML Proof or Print XML id *)
                      (* no infos about variables uri are known           *)
        | Some n -> string_of_int n
      in
       X.xml_empty "VAR"
        ["relUri",depth ^ "," ^ (N.string_of_id id) ;
         "id", next_id]
   | T.IsMeta n ->
      X.xml_empty "META" ["no",(string_of_int n) ; "id", next_id]
   | T.IsSort s ->
      X.xml_empty "SORT" ["value",(string_of_sort s) ; "id", next_id]
   | T.IsCast (t1,t2) ->
      X.xml_nempty "CAST" ["id", next_id]
       [< X.xml_nempty "term" [] (term_display l env t1) ;
          X.xml_nempty "type" [] (term_display l env t2)
       >]
   | T.IsLetIn (nid,s,t,d)->
      let nid' = N.next_name_away nid (names_to_ids l) in
       X.xml_nempty "LETIN" ["id", next_id]
        [< X.xml_nempty "term" [] (term_display l env s) ;
           X.xml_nempty "target" ["binder",(N.string_of_id nid')]
            (term_display
             ((N.Name nid')::l)
             (E.push_rel_def (N.Name nid', s, t) env)
             d
            )
        >]
   | T.IsProd (N.Name _ as nid, t1, t2) ->
      let nid' = N.next_name_away nid (names_to_ids l) in
       X.xml_nempty "PROD" ["id", next_id]
        [< X.xml_nempty "source" [] (term_display l env t1) ;
           X.xml_nempty "target" ["binder",(N.string_of_id nid')]
            (term_display
             ((N.Name nid')::l)
             (E.push_rel_assum (N.Name nid', t1) env)
             t2
            )
        >]
   | T.IsProd (N.Anonymous as nid, t1, t2) ->
      X.xml_nempty "PROD" ["id", next_id]
       [< X.xml_nempty "source" [] (term_display l env t1) ;
          X.xml_nempty "target" []
           (term_display
            (nid::l)
            (E.push_rel_assum (nid, t1) env)
            t2
           )
       >]
   | T.IsLambda (N.Name _ as nid, t1, t2) ->
      let nid' = N.next_name_away nid (names_to_ids l) in
       X.xml_nempty "LAMBDA" ["id", next_id]
        [< X.xml_nempty "source" [] (term_display l env t1) ;
           X.xml_nempty "target" ["binder",(N.string_of_id nid')]
            (term_display
             ((N.Name nid')::l)
             (E.push_rel_assum (N.Name nid', t1) env)
             t2
            )
        >]
   | T.IsLambda (N.Anonymous as nid, t1, t2) ->
      X.xml_nempty "LAMBDA" ["id", next_id]
       [< X.xml_nempty "source" [] (term_display l env t1) ;
          X.xml_nempty "target" []
           (term_display
            (nid::l)
            (E.push_rel_assum (nid, t1) env)
            t2
          )
       >]
   | T.IsApp (h,t) ->
      X.xml_nempty "APPLY" ["id", next_id]
       [< (term_display l env h) ;
          (Array.fold_right (fun x i -> [< (term_display l env x); i >]) t [<>])
       >]
   | T.IsConst (sp,_) ->
      X.xml_empty "CONST"
       ["uri",(uri_of_path sp Constant) ; "id", next_id]
   | T.IsMutInd ((sp,i),_) ->
      X.xml_empty "MUTIND"
       ["uri",(uri_of_path sp Inductive) ;
        "noType",(string_of_int i) ;
        "id", next_id]
   | T.IsMutConstruct (((sp,i),j),_) ->
      X.xml_empty "MUTCONSTRUCT"
       ["uri",(uri_of_path sp Inductive) ;
        "noType",(string_of_int i) ;
        "noConstr",(string_of_int j) ;
        "id", next_id]
   | T.IsMutCase ((_,((sp,i),_,_,_,_)),ty,term,a) ->
      let (uri, typeno) = (uri_of_path sp Inductive),i in
       X.xml_nempty "MUTCASE"
        ["uriType",uri ; "noType",(string_of_int typeno) ; "id",next_id]
        [< X.xml_nempty "patternsType" [] [< (term_display l env ty) >] ;
	   X.xml_nempty "inductiveTerm" [] [< (term_display l env term) >] ;
	   Array.fold_right
            (fun x i ->
              [< X.xml_nempty "pattern" [] [< term_display l env x >] ; i>]
            ) a [<>]
        >]
   | T.IsFix ((ai,i),((t,f,b) as rec_decl)) ->
      X.xml_nempty "FIX" ["noFun", (string_of_int i) ; "id",next_id]
       [< Array.fold_right
           (fun (fi,ti,bi,ai) i ->
             [< X.xml_nempty "FixFunction"
                 ["name", (string_of_name fi); "recIndex", (string_of_int ai)]
	         [< X.xml_nempty "type" [] [< term_display l env ti >] ;
	            X.xml_nempty "body" [] [<
                     term_display
                      ((List.rev f)@l)
                      (E.push_rec_types rec_decl env)
                      bi
                    >]
	         >] ;
                i
             >]
           )
	   (Array.mapi (fun j x -> (x,t.(j),b.(j),ai.(j)) ) (Array.of_list f) )
           [<>]
       >]
   | T.IsCoFix (i,((t,f,b) as rec_decl)) ->
      X.xml_nempty "COFIX" ["noFun", (string_of_int i) ; "id",next_id]
       [< Array.fold_right
           (fun (fi,ti,bi) i ->
            [< X.xml_nempty "CofixFunction" ["name", (string_of_name fi)]
	        [< X.xml_nempty "type" [] [< term_display l env ti >] ;
	           X.xml_nempty "body" [] [<
                    term_display
                     ((List.rev f)@l)
                     (E.push_rec_types rec_decl env)
                     bi
                   >]
	        >] ;
               i
            >]
	   )
	   (Array.mapi (fun j x -> (x,t.(j),b.(j)) ) (Array.of_list f) ) [<>]
       >]
   | T.IsXtra _ ->
      Util.anomaly "Xtra node in a term!!!"
   | T.IsEvar _ ->
      Util.anomaly "Evar node in a term!!!"
  in
    (*CSC: ad l vanno andrebbero aggiunti i nomi da non *)
    (*CSC: mascherare (costanti? variabili?)            *)
    term_display l env csr
;;

(* FUNCTIONS TO PRINT A SINGLE OBJECT OF COQ *)

(* print_current_proof term type id conjectures                            *)
(*  where term        is the term of the proof in progress p               *)
(*  and   type        is the type of p                                     *)
(*  and   id          is the identifier (name) of p                        *)
(*  and   conjectures is the list of conjectures (cic terms)               *)
(* returns a stream of XML tokens suitable to be pretty printed via Xml.pp *)
let print_current_proof c typ id mv =
 let module X = Xml in
  reset_id () ;
  let inner_types = ref [] in
  let env = (Safe_typing.env_of_safe_env (Global.safe_env ())) in
   [< X.xml_cdata "<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?>\n" ;
      X.xml_cdata ("<!DOCTYPE CurrentProof SYSTEM \"" ^ dtdname ^ "\">\n\n") ;
      X.xml_nempty "CurrentProof" ["name",id ; "id", get_next_id ()]
        [< List.fold_right
            (fun (j,t) i ->
              [< X.xml_nempty "Conjecture" ["no",(string_of_int j)]
                  [< print_term inner_types [] env t >] ; i >])
            mv [<>] ;
           X.xml_nempty "body" [] [< print_term inner_types [] env c >] ;
           X.xml_nempty "type"  [] [< print_term inner_types [] env typ >]
        >]
   >]
;;

(* print_axiom id type params                                              *)
(*  where type        is the type of an axiom a                            *)
(*  and   id          is the identifier (name) of a                        *)
(*  and   params      is the list of formal params for a                   *)
(* returns a stream of XML tokens suitable to be pretty printed via Xml.pp *)
let print_axiom id typ fv hyps env =
 let module X = Xml in
 let module N = Names in
  reset_id () ;
  let inner_types = ref [] in
   [< X.xml_cdata "<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?>\n" ;
      X.xml_cdata ("<!DOCTYPE Axiom SYSTEM \"" ^ dtdname ^ "\">\n\n") ;
      X.xml_nempty "Axiom"
       ["name",(N.string_of_id id) ;
         "id", get_next_id () ;
         "params",(string_of_pvars fv hyps)]
       [< X.xml_nempty "type" [] (print_term inner_types [] env typ) >]
   >]
;;

(* print_definition id term type params hyps                               *)
(*  where id          is the identifier (name) of a definition d           *)
(*  and   term        is the term (body) of d                              *)
(*  and   type        is the type of d                                     *)
(*  and   params      is the list of formal params for d                   *)
(* returns a stream of XML tokens suitable to be pretty printed via Xml.pp *)
let print_definition id c typ fv hyps env =
 let module X = Xml in
 let module N = Names in
  reset_id () ;
  let inner_types = ref [] in
   [< X.xml_cdata "<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?>\n" ;
      X.xml_cdata ("<!DOCTYPE Definition SYSTEM \"" ^ dtdname ^ "\">\n\n") ;
      X.xml_nempty "Definition"
       ["name",(N.string_of_id id) ;
        "id", get_next_id () ;
        "params",(string_of_pvars fv hyps)]
       [< X.xml_nempty "body" [] (print_term inner_types [] env c) ;
          X.xml_nempty "type"  [] (print_term inner_types [] env typ) >]
   >]
;;

(* print_variable id type                                                  *)
(*  where id          is the identifier (name) of a variable v             *)
(*  and   type        is the type of v                                     *)
(* returns a stream of XML tokens suitable to be pretty printed via Xml.pp *)
let print_variable id body typ env =
 let module X = Xml in
 let module N = Names in
  reset_id () ;
  let inner_types = ref [] in
   [< X.xml_cdata "<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?>\n" ;
      X.xml_cdata ("<!DOCTYPE Variable SYSTEM \"" ^ dtdname ^ "\">\n\n") ;
      X.xml_nempty "Variable" ["name",(N.string_of_id id); "id", get_next_id ()]
       [< (match body with
              None -> [<>]
            | Some body ->
               X.xml_nempty "body" [] (print_term inner_types [] env body)
          ) ;
          X.xml_nempty "type" [] (print_term inner_types [] env typ)
       >]
   >]
;;

(* print_mutual_inductive_packet p                                           *)
(*  where p is a mutual inductive packet (an inductive definition in a block *)
(*          of mutual inductive definitions)                                 *)
(* returns a stream of XML tokens suitable to be pretty printed via Xml.pp   *)
(* Used only by print_mutual_inductive                                       *)
let print_mutual_inductive_packet inner_types names env p =
 let module D = Declarations in
 let module N = Names in
 let module T = Term in
 let module X = Xml in
  let {D.mind_consnames=consnames ;
       D.mind_typename=typename ;
       D.mind_nf_lc=lc ;
       D.mind_nf_arity=arity ;
       D.mind_finite=finite} = p
  in
   [< X.xml_nempty "InductiveType"
       ["name",(N.string_of_id typename) ;
        "inductive",(string_of_bool finite)
       ]
       [<
          X.xml_nempty "arity" []
           (print_term inner_types [] env (T.body_of_type arity)) ;
          (Array.fold_right
           (fun (name,lc) i ->
             [< X.xml_nempty "Constructor" ["name",(N.string_of_id name)]
                 (print_term inner_types names env lc) ;
                i
             >])
	   (Array.mapi (fun j x -> (x,T.body_of_type lc.(j)) ) consnames )
           [<>]
          )
       >]
   >]
;;

(* print_mutual_inductive packs params nparams                             *)
(*  where packs       is the list of inductive definitions in the block of *)
(*                    mutual inductive definitions b                       *)
(*  and   params      is the list of formal params for b                   *)
(*  and   nparams     is the number of "parameters" in the arity of the    *)
(*                    mutual inductive types                               *)
(* returns a stream of XML tokens suitable to be pretty printed via Xml.pp *)
let print_mutual_inductive packs fv hyps nparams env =
 let module D = Declarations in
 let module E = Environ in
 let module X = Xml in
 let module N = Names in
  let inner_types = ref [] in
  let names =
   List.map
    (fun p -> let {D.mind_typename=typename} = p in N.Name(typename))
    (Array.to_list packs)
  in
  let env =
   List.fold_right
    (fun {D.mind_typename=typename ; D.mind_nf_arity=arity} env ->
     E.push_rel_assum (N.Name typename, arity) env)
    (Array.to_list packs)
    env
  in
   reset_id () ;
   [< X.xml_cdata "<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?>\n" ;
      X.xml_cdata ("<!DOCTYPE InductiveDefinition SYSTEM \"" ^
       dtdname ^ "\">\n\n") ;
      X.xml_nempty "InductiveDefinition"
       ["noParams",string_of_int nparams ;
        "id",get_next_id () ;
        "params",(string_of_pvars fv hyps)]
       [< (Array.fold_right
            (fun x i ->
             [< print_mutual_inductive_packet inner_types names env x ; i >]
            ) packs [< >]
          )
       >]
   >]
;;

let string_list_of_named_context_list =
 List.map
  (function (n,_,_) -> Names.string_of_id n)
;;

(* print id dest                                                          *)
(*  where sp   is the qualified identifier (section path) of a            *)
(*             definition/theorem, variable or inductive definition       *)
(*  and   dest is either None (for stdout) or (Some filename)             *)
(* pretty prints via Xml.pp the object whose identifier is id on dest     *)
(* Note: it is printed only (and directly) the most cooked available      *)
(*       form of the definition (all the parameters are                   *)
(*       lambda-abstracted, but the object can still refer to variables)  *)
let print sp fn =
 let module D = Declarations in
 let module G = Global in
 let module N = Names in
 let module T = Term in
 let module X = Xml in
  let (_,str) = N.repr_qualid sp in
  let id = Names.id_of_string str in
  let glob_ref = Nametab.locate sp in
  let env = (Safe_typing.env_of_safe_env (G.safe_env ())) in
  let pp_cmds =
   match glob_ref with
      T.VarRef sp ->
       let (body,typ) = G.lookup_named id in
        print_variable id body (T.body_of_type typ) env
    | T.ConstRef sp ->
       let {D.const_body=val0 ; D.const_type = typ ; D.const_hyps = hyps} =
        G.lookup_constant sp in
       let hyps = string_list_of_named_context_list hyps in
       let typ = T.body_of_type typ in
        begin
         match val0 with
            None -> print_axiom id typ [] hyps env
          | Some c -> print_definition id c typ [] hyps env
        end
    | T.IndRef (sp,_) ->
       let {D.mind_packets=packs ; D.mind_nparams=nparams ; D.mind_hyps=hyps} =
        G.lookup_mind sp
       in
        let hyps = string_list_of_named_context_list hyps in
         print_mutual_inductive packs [] hyps nparams env
    | T.ConstructRef _
    | T.EvarRef _ ->
       Util.anomaly ("print: this should not happen")
  in
   Xml.pp pp_cmds fn
;;
 
(* show dest                                                  *)
(*  where dest is either None (for stdout) or (Some filename) *)
(* pretty prints via Xml.pp the proof in progress on dest     *)
let show fn =
 let pftst = Pfedit.get_pftreestate () in
 let id = Pfedit.get_current_proof_name () in
 let pf = Tacmach.proof_of_pftreestate pftst in
 let typ = (Proof_trees.goal_of_proof pf).Evd.evar_concl in
 let val0,mv = Tacmach.extract_open_pftreestate pftst in
  Xml.pp (print_current_proof val0 typ (Names.string_of_id id) mv) fn
;;

(* FUNCTIONS TO PRINT AN ENTIRE SECTION OF COQ *)

(* list of (name, uncooked sp, most cooked sp, uncooked leaf object,  *)
(*          list of possible variables, directory name)               *)
(* used to collect informations on the uncooked and most cooked forms *)
(* of objects that could be cooked (have namesakes)                   *)
let printed = ref [];;

(* makes a filename from a directory name, a section path and an extension *)
let mkfilename dn sp ext =
 let dir_list_of_dirpath s =
  let rec aux n =
   try
    let pos = String.index_from s n '/' in
    let head = String.sub s n (pos - n) in
     head::(aux (pos + 1))
   with
    Not_found -> [String.sub s n (String.length s - n)]
  in
   aux 0
 in
 let rec join_dirs cwd =
   function
      [] -> ""
    | he::tail ->
       let newcwd = cwd ^ "/" ^ he in
        (try
          Unix.mkdir newcwd 0o775
         with _ -> () (* Let's ignore the errors on mkdir *)
        ) ;
        he ^ "/" ^ join_dirs newcwd tail
 in
  let module L = Library in
  let module S = System in
  let module N = Names in
   match dn with
      None         -> None
    | Some basedir ->
       match N.repr_path sp with
          (module_name::_ as dirs, filename, _) ->
           let dirs = 
             (dir_list_of_dirpath
              (fst (L.module_filename module_name)).S.relative_subdir
             ) @ dirs
           in
            Some (basedir ^ "/" ^ join_dirs basedir dirs ^
                  N.string_of_id filename ^ "." ^ ext ^ ".xml")
        | _ -> assert false
;;

(* print_object leaf_object id section_path directory_name formal_vars      *)
(*  where leaf_object    is a leaf object                                   *)
(*  and   id             is the identifier (name) of the definition/theorem *)
(*                       or of the inductive definition o                   *)
(*  and   section_path   is the section path of o                           *)
(*  and   directory_name is the base directory in which putting the print   *)
(*  and   formal_vars    is the list of parameters (variables) of o         *)
(* pretty prints via Xml.pp the object o in the right directory deduced     *)
(* from directory_name and section_path                                     *)
(* Note: it is printed only the uncooked available form of the object plus  *)
(*       the list of parameters of the object deduced from it's most cooked *)
(*       form                                                               *)
let print_object lobj id sp dn fv env =
 let module D = Declarations in
 let module E = Environ in
 let module G = Global in
 let module N = Names in
 let module T = Term in
 let module X = Xml in
  let tag = Libobject.object_tag lobj in
  let pp_cmds () =
   match tag with
      "CONSTANT"  (* = Definition, Theorem *)
    | "PARAMETER" (* = Axiom *) ->
        let {D.const_body=val0 ; D.const_type = typ ; D.const_hyps = hyps} =
         G.lookup_constant sp
        in
         let hyps = string_list_of_named_context_list hyps in
         let typ = T.body_of_type typ in
          begin
           match val0 with
              None -> print_axiom id typ fv hyps env
            | Some c -> print_definition id c typ fv hyps env
          end
    | "INDUCTIVE" ->
         let
          {D.mind_packets=packs ;
           D.mind_nparams=nparams ;
           D.mind_hyps = hyps
          } = G.lookup_mind sp
         in
          let hyps = string_list_of_named_context_list hyps in
           print_mutual_inductive packs fv hyps nparams env
    | "VARIABLE" ->
        let (_,(varentry,_,_)) = Declare.out_variable lobj in
         begin
          match varentry with
             Declare.SectionLocalDef body ->
              let typ = Retyping.get_type_of env Evd.empty body in
               add_to_pvars (Definition (N.string_of_id id, body, typ)) ;
               print_variable id (Some body) typ env
           | Declare.SectionLocalAssum typ ->
              add_to_pvars (Assumption (N.string_of_id id, typ)) ;
              print_variable id None (T.body_of_type typ) env
         end
    | "CLASS"
    | "COERCION"
    | _ -> raise Uninteresting
  and fileext () = ext_of_tag (tag_of_string_tag tag)
  in
   try
    Xml.pp (pp_cmds ()) (mkfilename dn sp (fileext ()))
   with
    Uninteresting -> ()
;;

(* print_library_segment state bprintleaf directory_name                      *)
(*  where state          is a list of (section-path, node)                    *)
(*  and   bprintleaf     is true iff the leaf objects should be printed       *)
(*  and   directory_name is the name of the base directory in which to print  *)
(*                       the files                                            *)
(* print via print_node all the nodes (leafs excluded if bprintleaf is false) *)(* in state                                                                   *)
let rec print_library_segment state bprintleaf dn =
  List.iter
   (function (sp, node) ->
     print_if_verbose (Names.string_of_path sp ^ "\n") ;
     print_node node (Names.basename sp) sp bprintleaf dn ;
     print_if_verbose "\n"
   ) (List.rev state)
(* print_node node id section_path bprintleaf directory_name             *)
(* prints a single node (and all it's subnodes via print_library_segment *)
and print_node n id sp bprintleaf dn =
 let module L = Lib in
  match n with
     L.Leaf o ->
      print_if_verbose "LEAF\n" ;
      if bprintleaf then
       begin
         if not (List.mem id !printed) then
          (* this is an uncooked term or a local (with no namesakes) term *)
          begin
           if could_have_namesakes o sp then
            begin
             (* this is an uncooked term *)
             print_if_verbose ("OK, stampo solo questa volta " ^ Names.string_of_id id ^ "\n") ;
             print_object o id sp dn !pvars !cumenv ;
             printed := id::!printed
            end
           else
            begin
             (* this is a local term *)
             print_if_verbose ("OK, stampo " ^ Names.string_of_id id ^ "\n") ;
             print_object o id sp dn !pvars !cumenv
            end
          end
         else
          begin
           (* update the least cooked sp *)
           print_if_verbose ("Suppongo gia' stampato " ^ Names.string_of_id id ^ "\n")
          end
       end
   | L.OpenedSection (s,_) -> print_if_verbose ("OpenDir " ^ s ^ "\n")
   | L.ClosedSection (_,s,state) ->
      print_if_verbose("ClosedDir " ^ s ^ "\n") ;
      if bprintleaf then
       begin
        (* open a new scope *)
        pvars := []::!pvars ;
        print_library_segment state bprintleaf dn ;
        (* close the scope *)
        match !pvars with
           [] -> assert false
         | he::tl -> pvars := tl
       end ;
      print_if_verbose "/ClosedDir\n"
   | L.Module s ->
      print_if_verbose ("Module " ^ (Names.string_of_dirpath s) ^ "\n")
   | L.FrozenState _ ->
      print_if_verbose ("FrozenState\n")
;;

(* print_closed_section module_name node directory_name                      *)
(*  where module_name is the name of a module                                *)
(*  and   node is the library segment of the module                          *)
(*  and   directory_name is the base directory in which to put the xml files *)
(* prints all the leaf objects of the tree rooted in node using              *)
(* print_library_segment on all its sons                                     *)
let print_closed_section s ls dn =
 let module L = Lib in
  printed := [] ;
  pvars := [[]] ;
  cumenv := Safe_typing.env_of_safe_env (Global.safe_env ()) ;
  print_if_verbose ("Module " ^ s ^ ":\n") ;
  print_library_segment ls true dn ;
  print_if_verbose "\n/Module\n" ;
;;

(* printModule identifier directory_name                                     *)
(*  where identifier     is the name of a module (section) d                 *)
(*  and   directory_name is the directory in which to root all the xml files *)
(* prints all the xml files and directories corresponding to the subsections *)
(* and terms of the module d                                                 *)
(* Note: the terms are printed in their uncooked form plus the informations  *)
(* on the parameters of their most cooked form                               *)
let printModule id dn =
 let module L = Library in
 let module N = Names in
 let module X = Xml in
  let str = N.string_of_id id in 
  let sp = Lib.make_path id N.OBJ in
  let ls = L.module_segment (Some str) in
   print_if_verbose ("MODULE_BEGIN " ^ str ^ " " ^ N.string_of_path sp ^ " " ^
    (snd (L.module_filename str)) ^ "\n") ;
   print_closed_section str (List.rev ls) dn ;
   print_if_verbose ("MODULE_END " ^ str ^ " " ^ N.string_of_path sp ^ " " ^
    (snd (L.module_filename str)) ^ "\n")
;;

(* printSection identifier directory_name                                    *)
(*  where identifier     is the name of a closed section d                   *)
(*  and   directory_name is the directory in which to root all the xml files *)
(* prints all the xml files and directories corresponding to the subsections *)
(* and terms of the closed section d                                         *)
(* Note: the terms are printed in their uncooked form plus the informations  *)
(* on the parameters of their most cooked form                               *)
let printSection id dn =
 let module L = Library in
 let module N = Names in
 let module X = Xml in
  let str = N.string_of_id id in 
  let sp = Lib.make_path id N.OBJ in
  let ls =
   let rec find_closed_section =
    function
       [] -> raise Not_found
     | (_,Lib.ClosedSection (_,str',ls))::_ when str' = str -> ls
     | _::t -> find_closed_section t
   in
    print_string ("Searching " ^ Names.string_of_path sp ^ "\n") ;
    find_closed_section (Lib.contents_after None)
  in
   print_if_verbose ("SECTION_BEGIN " ^ str ^ " " ^ N.string_of_path sp ^ "\n");
   print_closed_section str ls dn ;
   print_if_verbose ("SECTION_END " ^ str ^ " " ^ N.string_of_path sp ^ "\n")
;;

(* print All () prints what is the structure of the current environment of *)
(* Coq. No terms are printed. Useful only for debugging                    *)
let printAll () =
 let state = Library.module_segment None in
  let oldverbose = !verbose in
   verbose := true ;
   print_library_segment state false None ;
(*
   let ml = Library.loaded_modules () in
    List.iter (function i -> printModule (Names.id_of_string i) None) ml ;
*)
    verbose := oldverbose
;;
