package main

import "fmt"

// repeatableFlag implements flag.Value for a flag that can be given more
// than once, appending to a slice each time -- the Go equivalent of
// argparse's action="append", which every --displaced, --replace,
// --default, --secret, --union-list, and --env-file flag in the Python
// originals relies on.
type repeatableFlag struct {
	values *[]string
}

func (r repeatableFlag) String() string {
	if r.values == nil {
		return ""
	}
	return fmt.Sprint(*r.values)
}

func (r repeatableFlag) Set(value string) error {
	*r.values = append(*r.values, value)
	return nil
}
