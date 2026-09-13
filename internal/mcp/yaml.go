package mcp

import (
	"regexp"
	"sort"
	"strconv"
	"strings"
)

// upsertYAMLMCPServerBlock is a Go port of the pinned Gentle AI fork's own
// hand-rolled filemerge.UpsertYAMLMCPServerBlock
// (internal/components/filemerge/yaml.go): it removes any existing
// <serverID>: block nested under the top-level mcp_servers: key and
// re-appends a fresh block with command/args (and optional env). If
// mcp_servers: is absent, it is created. Everything outside the managed
// server block -- other servers, top-level keys, and user comments -- is
// preserved.
//
// command/args/env are emitted with 2-space indentation:
//
//	mcp_servers:
//	  <serverID>:
//	    command: <command>
//	    args:
//	      - <arg0>
//	      - <arg1>
//	    env:
//	      KEY: value
//
// Idempotent: calling twice with the same arguments yields identical output.
// This is a deliberately narrow, faithful port (not a general YAML library)
// -- it is only ever asked to write the shape above, the same restriction
// the fork's own writer carried, which is why hermes MCP servers are
// stdio-only here too (see stdioOnlyAgents).
func upsertYAMLMCPServerBlock(content, serverID, command string, args []string, env map[string]string) string {
	content = strings.ReplaceAll(content, "\r\n", "\n")
	lines := strings.Split(content, "\n")

	block := buildYAMLServerBlock(serverID, command, args, env)

	mcpLineIdx := -1
	for i, line := range lines {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, "mcp_servers:") && !hasYAMLLeadingSpaces(line) {
			mcpLineIdx = i
			break
		}
	}

	if mcpLineIdx == -1 {
		base := strings.TrimRight(strings.Join(lines, "\n"), "\n")
		if base == "" {
			return "mcp_servers:\n" + block
		}
		return base + "\n\nmcp_servers:\n" + block
	}

	// Normalize an inline mcp_servers: value (e.g. "mcp_servers: {}" or
	// "mcp_servers: somevalue") to a bare block-form "mcp_servers:" so the
	// rest of the algorithm can treat it uniformly.
	if strings.TrimSpace(lines[mcpLineIdx]) != "mcp_servers:" {
		raw := lines[mcpLineIdx]
		rest := strings.TrimPrefix(raw, "mcp_servers:")
		if idx := strings.Index(rest, "#"); idx != -1 {
			comment := strings.TrimSpace(rest[idx:])
			lines[mcpLineIdx] = "mcp_servers:  # " + strings.TrimPrefix(comment, "# ")
		} else {
			lines[mcpLineIdx] = "mcp_servers:"
		}
	}

	// mcp_servers: is present -- find the region of its child lines: from
	// mcpLineIdx+1 to the next zero-indent non-blank non-comment line
	// (exclusive), or EOF.
	regionEnd := len(lines)
	for i := mcpLineIdx + 1; i < len(lines); i++ {
		line := lines[i]
		trimmed := strings.TrimSpace(line)
		if trimmed == "" {
			continue
		}
		if !hasYAMLLeadingSpaces(line) && !strings.HasPrefix(trimmed, "#") {
			regionEnd = i
			break
		}
	}

	// Within the region, strip any existing <serverID>: block. The server
	// key sits at exactly 2-space indent: "  <serverID>:".
	serverKey := "  " + serverID + ":"
	kept := append([]string{}, lines[:mcpLineIdx+1]...)

	region := lines[mcpLineIdx+1 : regionEnd]
	i := 0
	for i < len(region) {
		line := region[i]

		if isYAMLServerKeyLine(line, serverKey) {
			// Skip this server's sub-block: all lines that belong to the
			// removed server (indent > 2 spaces), until a sibling boundary.
			i++
			for i < len(region) {
				nextLine := region[i]
				nextTrimmed := strings.TrimSpace(nextLine)
				if nextTrimmed == "" {
					i++
					continue
				}
				if len(nextLine) >= 2 && nextLine[:2] == "  " {
					restAfterTwo := nextLine[2:]
					if len(restAfterTwo) > 0 && restAfterTwo[0] != ' ' {
						break // sibling server key or sibling comment
					}
				}
				if !hasYAMLLeadingSpaces(nextLine) && nextTrimmed != "" && !strings.HasPrefix(nextTrimmed, "#") {
					break // end of the mcp_servers region
				}
				i++
			}
			continue
		}

		kept = append(kept, line)
		i++
	}

	// Trim trailing blank lines at the end of the kept mcp_servers region
	// before appending the fresh block.
	for len(kept) > mcpLineIdx+1 && strings.TrimSpace(kept[len(kept)-1]) == "" {
		kept = kept[:len(kept)-1]
	}

	blockLines := strings.Split(strings.TrimRight(block, "\n"), "\n")
	kept = append(kept, blockLines...)

	if regionEnd < len(lines) {
		if strings.TrimSpace(lines[regionEnd]) != "" {
			kept = append(kept, "")
		}
		kept = append(kept, lines[regionEnd:]...)
	}

	result := strings.Join(kept, "\n")
	result = strings.TrimRight(result, "\n")
	return result + "\n"
}

// buildYAMLServerBlock builds the 2-space-indented YAML block for a single
// MCP server. The block does not include mcp_servers: -- it starts at
// "  <serverID>:".
//
// command, args and env values are always emitted as double-quoted YAML
// scalars, and an env key is quoted whenever it is not a plain identifier
// -- unlike the pinned fork's own filemerge.UpsertYAMLMCPServerBlock
// (yaml.go's own package doc), which writes every one of these as a bare
// plain scalar. That is a deliberate deviation, not a missed port: a plain
// scalar starting with a YAML indicator character (@, *, &, !, %, {, [, a
// backtick, or a quote) fails to parse at all, one containing ": " or " #"
// is truncated or silently re-keyed, and "true", "8080" or "" is retyped as
// a bool, int or null instead of staying the string gentle-nix wrote --
// every one of those is a realistic env value or command argument (a token
// placeholder such as "@TOKEN@" is the common case). serverID itself is
// left unquoted: it also doubles as the literal removal key
// upsertYAMLMCPServerBlock matches against on re-run (see serverKey there),
// so quoting it here without teaching that matching logic the same quoting
// would break idempotency; Gentle AI's own MCP server names are
// identifiers already, so this is not the shape the finding this deviation
// exists for was ever about.
func buildYAMLServerBlock(serverID, command string, args []string, env map[string]string) string {
	var sb strings.Builder
	sb.WriteString("  " + serverID + ":\n")
	sb.WriteString("    command: " + yamlQuotedScalar(command) + "\n")
	if len(args) > 0 {
		sb.WriteString("    args:\n")
		for _, arg := range args {
			sb.WriteString("      - " + yamlQuotedScalar(arg) + "\n")
		}
	}
	if len(env) > 0 {
		sb.WriteString("    env:\n")
		keys := make([]string, 0, len(env))
		for k := range env {
			keys = append(keys, k)
		}
		sort.Strings(keys)
		for _, k := range keys {
			sb.WriteString("      " + yamlKeyScalar(k) + ": " + yamlQuotedScalar(env[k]) + "\n")
		}
	}
	return sb.String()
}

// yamlQuotedScalar renders s as a YAML double-quoted scalar. Go's
// strconv.Quote escapes (\\, \", \n, \t, \r, \xXX, \uXXXX, ...) are a
// subset of the escapes YAML's own double-quoted style defines (YAML spec
// 5.7), so its output is valid YAML as well as valid Go -- there is no
// separate YAML-specific escaper to maintain.
func yamlQuotedScalar(s string) string {
	return strconv.Quote(s)
}

// plainYAMLKeyPattern matches an unquoted YAML mapping key gentle-nix is
// willing to write bare: a plain identifier, never a YAML indicator
// character, a colon-space or hash-space sequence, or something a parser
// would retype (a boolean/null word, a number).
var plainYAMLKeyPattern = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_-]*$`)

// yamlKeyScalar renders k as a bare YAML key when it is a plain identifier,
// and as a double-quoted scalar otherwise (see yamlQuotedScalar).
func yamlKeyScalar(k string) string {
	if plainYAMLKeyPattern.MatchString(k) {
		return k
	}
	return yamlQuotedScalar(k)
}

// hasYAMLLeadingSpaces reports whether line starts with a space or tab.
func hasYAMLLeadingSpaces(line string) bool {
	return len(line) > 0 && (line[0] == ' ' || line[0] == '\t')
}

// isYAMLServerKeyLine reports whether line matches the given serverKey
// prefix, allowing for an optional trailing inline comment (e.g.
// "  engram: # managed"). serverKey has the form "  <serverID>:".
func isYAMLServerKeyLine(line, serverKey string) bool {
	if strings.TrimRight(line, " \t") == serverKey || line == serverKey {
		return true
	}
	if strings.HasPrefix(line, serverKey) {
		rest := line[len(serverKey):]
		rest = strings.TrimLeft(rest, " \t")
		if strings.HasPrefix(rest, "#") {
			return true
		}
	}
	return false
}
