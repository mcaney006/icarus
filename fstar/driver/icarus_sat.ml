let () =
  match Sys.argv with
  | [| _; path |] -> (
      match In_channel.with_open_bin path In_channel.input_all with
      | content -> exit (Z.to_int (Icarus_SatCheck.run content))
      | exception Sys_error reason ->
          prerr_endline reason;
          exit 3)
  | _ ->
      prerr_endline "usage: icarus_sat <operations file>";
      exit 2
