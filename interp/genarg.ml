(***********************************************************************)
(*  v      *   The Coq Proof Assistant  /  The Coq Development Team    *)
(* <O___,, *        INRIA-Rocquencourt  &  LRI-CNRS-Orsay              *)
(*   \VV/  *************************************************************)
(*    //   *      This file is distributed under the terms of the      *)
(*         *       GNU Lesser General Public License Version 2.1       *)
(***********************************************************************)

(* $Id$ *)

open Util
open Names
open Nametab
open Rawterm
open Topconstr
open Term

type argument_type =
  (* Basic types *)
  | BoolArgType
  | IntArgType
  | IntOrVarArgType
  | StringArgType
  | PreIdentArgType
  | IdentArgType
  | RefArgType
  (* Specific types *)
  | SortArgType
  | ConstrArgType
  | ConstrMayEvalArgType
  | QuantHypArgType
  | TacticArgType
  | CastedOpenConstrArgType
  | ConstrWithBindingsArgType
  | RedExprArgType
  | List0ArgType of argument_type
  | List1ArgType of argument_type
  | OptArgType of argument_type
  | PairArgType of argument_type * argument_type
  | ExtraArgType of string

type 'a or_var = ArgArg of 'a | ArgVar of identifier located
type 'a and_short_name = 'a * identifier located option
type rawconstr_and_expr = rawconstr * constr_expr option

(* Dynamics but tagged by a type expression *)

type ('a,'b) generic_argument = argument_type * Obj.t

let dyntab = ref ([] : string list)

type ('a,'b,'c) abstract_argument_type = argument_type

let create_arg s =
  if List.mem s !dyntab then
    anomaly ("Genarg.create: already declared generic argument " ^ s);
  dyntab := s :: !dyntab;
  let t = ExtraArgType s in
  (t,t,t)

let exists_argtype s = List.mem s !dyntab

type open_constr = Evd.evar_map * Term.constr
type open_constr_expr = constr_expr
type open_rawconstr = rawconstr_and_expr

let rawwit_bool = BoolArgType
let globwit_bool = BoolArgType
let wit_bool = BoolArgType

let rawwit_int = IntArgType
let globwit_int = IntArgType
let wit_int = IntArgType

let rawwit_int_or_var = IntOrVarArgType
let globwit_int_or_var = IntOrVarArgType
let wit_int_or_var = IntOrVarArgType

let rawwit_string = StringArgType
let globwit_string = StringArgType
let wit_string = StringArgType

let rawwit_ident = IdentArgType
let globwit_ident = IdentArgType
let wit_ident = IdentArgType

let rawwit_pre_ident = PreIdentArgType
let globwit_pre_ident = PreIdentArgType
let wit_pre_ident = PreIdentArgType

let rawwit_ref = RefArgType
let globwit_ref = RefArgType
let wit_ref = RefArgType

let rawwit_quant_hyp = QuantHypArgType
let globwit_quant_hyp = QuantHypArgType
let wit_quant_hyp = QuantHypArgType

let rawwit_sort = SortArgType
let globwit_sort = SortArgType
let wit_sort = SortArgType

let rawwit_constr = ConstrArgType
let globwit_constr = ConstrArgType
let wit_constr = ConstrArgType

let rawwit_constr_may_eval = ConstrMayEvalArgType
let globwit_constr_may_eval = ConstrMayEvalArgType
let wit_constr_may_eval = ConstrMayEvalArgType

let rawwit_tactic = TacticArgType
let globwit_tactic = TacticArgType
let wit_tactic = TacticArgType

let rawwit_casted_open_constr = CastedOpenConstrArgType
let globwit_casted_open_constr = CastedOpenConstrArgType
let wit_casted_open_constr = CastedOpenConstrArgType

let rawwit_constr_with_bindings = ConstrWithBindingsArgType
let globwit_constr_with_bindings = ConstrWithBindingsArgType
let wit_constr_with_bindings = ConstrWithBindingsArgType

let rawwit_red_expr = RedExprArgType
let globwit_red_expr = RedExprArgType
let wit_red_expr = RedExprArgType

let wit_list0 t = List0ArgType t

let wit_list1 t = List1ArgType t

let wit_opt t = OptArgType t

let wit_pair t1 t2 = PairArgType (t1,t2)

let in_gen t o = (t,Obj.repr o)
let out_gen t (t',o) = if t = t' then Obj.magic o else failwith "out_gen"
let genarg_tag (s,_) = s

let fold_list0 f = function
  | (List0ArgType t as u, l) ->
      List.fold_right (fun x -> f (in_gen t x)) (Obj.magic l)
  | _ -> failwith "Genarg: not a list0"

let fold_list1 f = function
  | (List1ArgType t as u, l) ->
      List.fold_right (fun x -> f (in_gen t x)) (Obj.magic l)
  | _ -> failwith "Genarg: not a list1"

let fold_opt f a = function
  | (OptArgType t as u, l) ->
      (match Obj.magic l with
	| None -> a
	| Some x -> f (in_gen t x))
  | _ -> failwith "Genarg: not a opt"

let fold_pair f = function
  | (PairArgType (t1,t2) as u, l) ->
      let (x1,x2) = Obj.magic l in
      f (in_gen t1 x1) (in_gen t2 x2)
  | _ -> failwith "Genarg: not a pair"

let app_list0 f = function
  | (List0ArgType t as u, l) ->
      let o = Obj.magic l in
      (u, Obj.repr (List.map (fun x -> out_gen t (f (in_gen t x))) o))
  | _ -> failwith "Genarg: not a list0"

let app_list1 f = function
  | (List1ArgType t as u, l) ->
      let o = Obj.magic l in
      (u, Obj.repr (List.map (fun x -> out_gen t (f (in_gen t x))) o))
  | _ -> failwith "Genarg: not a list1"

let app_opt f = function
  | (OptArgType t as u, l) ->
      let o = Obj.magic l in
      (u, Obj.repr (option_app (fun x -> out_gen t (f (in_gen t x))) o))
  | _ -> failwith "Genarg: not an opt"

let app_pair f1 f2 = function
  | (PairArgType (t1,t2) as u, l) ->
      let (o1,o2) = Obj.magic l in
      let o1 = out_gen t1 (f1 (in_gen t1 o1)) in
      let o2 = out_gen t2 (f2 (in_gen t2 o2)) in
      (u, Obj.repr (o1,o2))
  | _ -> failwith "Genarg: not a pair"

let unquote x = x

type an_arg_of_this_type = Obj.t

let in_generic t x = (t, Obj.repr x)
