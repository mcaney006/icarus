(* Supplies the fixture bytes and the process exit code; all parsing, checksum
   verification and decisions are in the verified F* modules. *)
let () =
  match Sys.argv with
  | [| _; path |] ->
    (match In_channel.with_open_bin path In_channel.input_all with
     | content -> exit (Z.to_int (Icarus_Decide.run content))
     | exception Sys_error _ -> print_string "REJECT unreadable fixture\n"; exit 3)
  | _ -> prerr_string "usage: icarus_decide <fixture.icf>\n"; exit 2
