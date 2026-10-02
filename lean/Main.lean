/-
Executable driver for the proved decision layer: read an ICF fixture, verify its
FNV-1a checksum, run `Icarus.decide` from Ready over the recorded flag masks, and
print the canonical M and H lines (spec/ICF.md). The mode and health logic is the
function the theorems in Icarus/Decision.lean are about; only the string handling
here is outside the proofs.
-/
import Icarus.Decision
open Icarus

def fnvStep (h : UInt32) (c : Char) : UInt32 := (h ^^^ c.toNat.toUInt32) * 16777619

def fnvLine (h : UInt32) (line : String) : UInt32 := fnvStep (line.foldl fnvStep h) '\n'

def modeCode : Mode → Nat
  | .boot => 0 | .selfTest => 1 | .calibrating => 2 | .ready => 3
  | .running => 4 | .degraded => 5 | .safe => 6 | .fault => 7

def healthCode (h : Health) : Nat := h.rank

structure Scan where
  hash : UInt32
  masks : Option (List Int)
  checked : Option Bool

def words (line : String) : List String := (line.splitOn " ").filter (· ≠ "")

def scanLine (acc : Scan) (line : String) : Scan :=
  match words line with
  | ["Z", v] => { acc with checked := some (v.toInt? == some (Int.ofNat acc.hash.toNat)) }
  | "G" :: rest => { acc with hash := fnvLine acc.hash line, masks := rest.mapM String.toInt? }
  | _ => { acc with hash := fnvLine acc.hash line }

def simulate (masks : List Nat) : List Nat × List Nat :=
  let rec go (s : Monitor) : List Nat → List Nat → List Nat → List Nat × List Nat
    | [], ms, hs => ((modeCode s.mode :: ms).reverse, hs.reverse)
    | m :: rest, ms, hs =>
      let f := ofMask m
      let h := classify f
      go (decide s h f.timing) rest (modeCode s.mode :: ms) (healthCode h :: hs)
  go initial masks [] []

def render (tag : String) (xs : List Nat) : String :=
  tag ++ " " ++ " ".intercalate (xs.map toString)

def reject (why : String) : IO UInt32 := do
  IO.println s!"REJECT {why}"
  pure 3

def run (path : String) : IO UInt32 := do
  let content ← try IO.FS.readFile path catch _ => return (← reject "unreadable fixture")
  let lines := (content.splitOn "\n").filter (· ≠ "")
  let r := lines.foldl scanLine { hash := 2166136261, masks := none, checked := none }
  match r.checked, r.masks with
  | some true, some ms =>
    if ms.any (fun m => m < 0 || m ≥ 32) then reject "flag mask out of range"
    else
      let (modes, healths) := simulate (ms.map Int.toNat)
      IO.println (render "M" modes)
      IO.println (render "H" healths)
      pure 0
  | some false, _ => reject "checksum mismatch"
  | none, _ => reject "missing Z checksum line"
  | _, none => reject "missing or malformed G record"

def main (args : List String) : IO UInt32 :=
  match args with
  | [path] => run path
  | _ => do IO.eprintln "usage: icarus <fixture.icf>"; pure 2
