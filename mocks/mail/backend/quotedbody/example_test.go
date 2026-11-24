// SPDX-License-Identifier: GPL-3.0-or-later

package quotedbody_test

import (
	"fmt"
	"tacit.local/quotedbody"
)

func ExampleSplitText() {
	for _, part := range quotedbody.SplitText("Thanks!\n\nOn Tuesday, Alex wrote:\n> Hello") {
		fmt.Printf("%s: %q\n", part.Kind, part.Content)
	}
	// Output:
	// content: "Thanks!\n\n"
	// quotedHistory: "On Tuesday, Alex wrote:\n> Hello"
}
