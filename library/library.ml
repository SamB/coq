
(* $Id$ *)

open Pp
open Util
open System
open Names
open Environ
open Libobject
open Lib

(*s Load path. *)

let load_path = ref ([] : load_path)

let get_load_path () = !load_path

let add_load_path_entry lpe = load_path := lpe :: !load_path

let add_path dir = 
  add_load_path_entry { directory = dir; root_dir = dir; relative_subdir = "" }

let remove_path dir =
  load_path := List.filter (fun lpe -> lpe.directory <> dir) !load_path

let rec_add_path dir = 
  load_path := (all_subdirs dir) @ !load_path

(*s Modules on disk contain the following informations (after the magic 
    number, and before the digest). *)

type module_disk = { 
  md_name : string;
  md_compiled_env : compiled_env;
  md_declarations : library_segment;
  md_deps : (string * Digest.t * bool) list }

(*s Modules loaded in memory contain the following informations. They are
    kept in the global table [modules_table]. *)

type module_t = {
  module_name : string;
  module_filename : load_path_entry * string;
  module_compiled_env : compiled_env;
  module_declarations : library_segment;
  mutable module_opened : bool;
  mutable module_exported : bool;
  module_deps : (string * Digest.t * bool) list;
  module_digest : Digest.t }

let modules_table = ref Stringmap.empty

let _ = 
  Summary.declare_summary "MODULES"
    { Summary.freeze_function = (fun () -> !modules_table);
      Summary.unfreeze_function = (fun ft -> modules_table := ft);
      Summary.init_function = (fun () -> modules_table := Stringmap.empty) }

let find_module s =
  try
    Stringmap.find s !modules_table
  with Not_found ->
    error ("Unknown module " ^ s)

let module_is_loaded s =
  try let _ = Stringmap.find s !modules_table in true with Not_found -> false

let module_is_opened s = (find_module s).module_opened

let loaded_modules () =
  Stringmap.fold (fun s _ l -> s :: l) !modules_table []

let opened_modules () =
  Stringmap.fold 
    (fun s m l -> if m.module_opened then s :: l else l) 
    !modules_table []

let module_segment = function
  | None -> contents_after None
  | Some m -> (find_module m).module_declarations

let module_filename m = (find_module m).module_filename

let vo_magic_number = 0700

let (raw_extern_module, raw_intern_module) =
  System.raw_extern_intern vo_magic_number ".vo"

let segment_rec_iter f =
  let rec apply = function
    | sp,Leaf obj -> f (sp,obj)
    | _,OpenedSection _ -> assert false
    | _,ClosedSection (_,seg) -> iter seg
    | _,(FrozenState _ | Module _) -> ()
  and iter seg =
    List.iter apply seg
  in
  iter

let segment_iter f =
  let rec apply = function
    | sp,Leaf obj -> f (sp,obj)
    | _,OpenedSection _ -> assert false
    | _,ClosedSection (_,seg) -> ()
    | _,(FrozenState _ | Module _) -> ()
  and iter seg =
    List.iter apply seg
  in
  iter

(*s [open_module s] opens a module. The module [s] and all modules needed by
    [s] are assumed to be already loaded. When opening [s] we recursively open
    all the modules needed by [s] and tagged [exported]. *) 

let open_objects decls =
  segment_iter open_object decls

let rec open_module s =
  let m = find_module s in
  if not m.module_opened then begin
    List.iter (fun (m,_,exp) -> if exp then open_module m) m.module_deps;
    open_objects m.module_declarations;
    m.module_opened <- true
  end


(*s [load_module s] loads the module [s] from the disk, and [find_module s]
   returns the module of name [s], loading it if necessary. 
   The boolean [doexp] specifies if we open the modules which are declared
   exported in the dependencies (it is [true] at the highest level;
   then same value as for caller is reused in recursive loadings). *)

let load_objects decls =
  segment_rec_iter load_object decls

let rec load_module_from s f =
  let (lpe,fname,ch) = raw_intern_module (get_load_path ()) f in
  let md = System.marshal_in ch in
  let digest = System.marshal_in ch in
  close_in ch;
  let m = { module_name = md.md_name;
	    module_filename = (lpe,fname);
	    module_compiled_env = md.md_compiled_env;
	    module_declarations = md.md_declarations;
	    module_opened = false;
	    module_exported = false;
	    module_deps = md.md_deps;
	    module_digest = digest } in
  if s <> md.md_name then
    error ("The file " ^ fname ^ " does not contain module " ^ s);
  List.iter (load_mandatory_module s) m.module_deps;
  Global.import m.module_compiled_env;
  load_objects m.module_declarations;
  modules_table := Stringmap.add s m !modules_table;
  m

and load_mandatory_module caller (s,d,_) =
  let m = find_module s s in
  if d <> m.module_digest then
    error ("module "^caller^" makes inconsistent assumptions over module "^s)

and find_module s f =
  try 
    Stringmap.find s !modules_table 
  with Not_found -> 
    load_module_from s f

let load_module s = function
  | None -> let _ = load_module_from s s in ()
  | Some f -> let _ = load_module_from s f in ()


(*s [require_module] loads and opens a module. *)

let require_module spec name fileopt export =
  let file = match fileopt with
    | None -> name
    | Some f -> f in
  let m = load_module_from name file in
  open_module name;
  if export then m.module_exported <- true


(*s [save_module s] saves the module [m] to the disk. *)

let current_imports () =
  Stringmap.fold
    (fun _ m l -> (m.module_name, m.module_digest, m.module_exported) :: l)
    !modules_table []

let save_module_to s f =
  let seg = export_module () in
  let md = { 
    md_name = s;
    md_compiled_env = Global.export s;
    md_declarations = seg;
    md_deps = current_imports () } in
  let (f',ch) = raw_extern_module f in
  System.marshal_out ch md;
  flush ch;
  let di = Digest.file f' in
  System.marshal_out ch di;
  close_out ch


(*s Pretty-printing of modules state. *)

let fmt_modules_state () =
  let opened = opened_modules ()
  and loaded = loaded_modules () in
  [< 'sTR "Imported (open) Modules: " ;
     prlist_with_sep pr_spc (fun s -> [< 'sTR s >]) opened ; 'fNL ;
     'sTR "Loaded Modules: " ;
     prlist_with_sep pr_spc (fun s -> [< 'sTR s >]) loaded ; 'fNL >]
