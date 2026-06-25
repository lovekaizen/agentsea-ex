# A minimal newline-delimited JSON-RPC "MCP server" for testing the stdio
# transport against a real subprocess. Reads one JSON request per line, writes
# one JSON response per line. Compact JSON (no spaces after ':') is assumed.
{
  id = "null"
  if (match($0, /"id":[0-9]+/)) {
    s = substr($0, RSTART, RLENGTH)
    gsub(/[^0-9]/, "", s)
    id = s
  }

  if ($0 ~ /"initialize"/) {
    printf("{\"jsonrpc\":\"2.0\",\"id\":%s,\"result\":{\"serverInfo\":{\"name\":\"echo\"}}}\n", id)
  } else if ($0 ~ /"tools\/list"/) {
    printf("{\"jsonrpc\":\"2.0\",\"id\":%s,\"result\":{\"tools\":[{\"name\":\"echo\",\"description\":\"Echo\",\"inputSchema\":{}}]}}\n", id)
  } else if ($0 ~ /"tools\/call"/) {
    text = ""
    if (match($0, /"text":"[^"]*"/)) {
      t = substr($0, RSTART, RLENGTH)
      sub(/^"text":"/, "", t)
      sub(/"$/, "", t)
      text = t
    }
    printf("{\"jsonrpc\":\"2.0\",\"id\":%s,\"result\":{\"content\":[{\"type\":\"text\",\"text\":\"echo: %s\"}]}}\n", id, text)
  } else {
    printf("{\"jsonrpc\":\"2.0\",\"id\":%s,\"error\":{\"code\":-32601,\"message\":\"method not found\"}}\n", id)
  }

  fflush()
}
