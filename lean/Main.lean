import Icarus.Decision

open Icarus

def fnvOffset : UInt32 := 2166136261
def fnvPrime : UInt32 := 16777619

def fnv (hash : UInt32) (c : Char) : UInt32 := (hash ^^^ c.toNat.toUInt32) * fnvPrime

def fnvLine (hash : UInt32) (line : String) : UInt32 := fnv (line.foldl fnv hash) '\n'

structure Scan where
  hash : UInt32 := fnvOffset
  masks : Option (List Int) := none
  sealed : Option Bool := none

def Scan.feed (scan : Scan) (line : String) : Scan :=
  match line.splitOn " " |>.filter (· ≠ "") with
  | ["Z", digest] => { scan with sealed := some (digest.toNat? == some scan.hash.toNat) }
  | "G" :: masks => { scan with hash := fnvLine scan.hash line, masks := masks.mapM String.toInt? }
  | _ => { scan with hash := fnvLine scan.hash line }

def render (tag : String) (codes : List Nat) : String :=
  " ".intercalate (tag :: codes.map toString)

def replay (masks : List Nat) : List Nat × List Nat :=
  let flags := masks.map ofMask
  let modes := flags.scanl (fun s f => s.next (classify f) f.timing) Monitor.initial
  (modes.map (·.mode.ctorIdx), flags.map (classify · |>.ctorIdx))

def reject (reason : String) : IO UInt32 := do
  IO.println s!"REJECT {reason}"
  return 3

def run (path : String) : IO UInt32 := do
  let some content ← (some <$> IO.FS.readFile path).catchExceptions fun _ => pure none
    | reject "unreadable fixture"
  let scan := (content.splitOn "\n").filter (· ≠ "") |>.foldl Scan.feed {}
  match scan.sealed, scan.masks with
  | none, _ => reject "missing Z checksum line"
  | some false, _ => reject "checksum mismatch"
  | some true, none => reject "missing or malformed G record"
  | some true, some masks =>
    if masks.any (fun m => m < 0 || 32 ≤ m) then reject "flag mask out of range" else
    let (modes, healths) := replay (masks.map Int.toNat)
    IO.println (render "M" modes)
    IO.println (render "H" healths)
    return 0

def main : List String → IO UInt32
  | [path] => run path
  | _ => do IO.eprintln "usage: icarus <fixture.icf>"; return 2
