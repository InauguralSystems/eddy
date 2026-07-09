// check.go — the EXTERNAL linearizability oracle for eddy.
//
// Reads a JSON history (emitted by the EigenScript DST) on stdin, pairs each
// client's invoke/ok events into porcupine Operations, and grades them against
// a single-register model with Porcupine (Wing-Gong linearizability check).
// eddy's store never grades itself; this independent Go program is the judge.
//
//   OK       -> exit 0, prints "OK"
//   ILLEGAL  -> exit 1, prints "ILLEGAL"
//   UNKNOWN  -> exit 2 (checker timed out)
//
// History event: {"proc":N,"type":"invoke"|"ok","f":"put"|"get","value":V|null,"index":T}
package main

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"sort"

	"github.com/anishathalye/porcupine"
)

type event struct {
	Proc  int      `json:"proc"`
	Type  string   `json:"type"`
	F     string   `json:"f"`
	Value *float64 `json:"value"`
	Index int64    `json:"index"`
}

type regInput struct {
	op  string
	val int
}

// A single-register model: put(v) always succeeds and sets the register to v;
// get() is legal iff it returned the current register value. Init = 0.
var registerModel = porcupine.Model{
	Init: func() interface{} { return 0 },
	Step: func(state, input, output interface{}) (bool, interface{}) {
		st := state.(int)
		in := input.(regInput)
		if in.op == "put" {
			return true, in.val
		}
		return output.(int) == st, st // get
	},
}

func main() {
	raw, err := io.ReadAll(os.Stdin)
	if err != nil {
		fmt.Fprintln(os.Stderr, "read:", err)
		os.Exit(3)
	}
	var evs []event
	if err := json.Unmarshal(raw, &evs); err != nil {
		fmt.Fprintln(os.Stderr, "parse:", err)
		os.Exit(3)
	}
	sort.SliceStable(evs, func(i, j int) bool { return evs[i].Index < evs[j].Index })

	// Pair each proc's invoke with its following ok into one Operation.
	open := map[int]event{}
	var ops []porcupine.Operation
	for _, e := range evs {
		if e.Type == "invoke" {
			open[e.Proc] = e
			continue
		}
		inv, ok := open[e.Proc]
		if !ok {
			fmt.Fprintf(os.Stderr, "ok without invoke for proc %d\n", e.Proc)
			os.Exit(3)
		}
		delete(open, e.Proc)
		var in regInput
		out := 0
		if e.F == "put" {
			in = regInput{op: "put", val: int(*inv.Value)}
		} else {
			in = regInput{op: "get"}
			if e.Value != nil {
				out = int(*e.Value)
			}
		}
		ops = append(ops, porcupine.Operation{
			ClientId: e.Proc,
			Input:    in,
			Call:     inv.Index,
			Output:   out,
			Return:   e.Index,
		})
	}

	switch porcupine.CheckOperations(registerModel, ops) {
	case true:
		fmt.Println("OK")
		os.Exit(0)
	default:
		fmt.Println("ILLEGAL")
		os.Exit(1)
	}
}
