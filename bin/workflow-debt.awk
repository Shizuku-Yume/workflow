# Shared parser for workflow-debt. Keep fenced entry templates out of real records.
function trim(s) { sub(/^[ \t\r]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
function fail(message, line) {
    printf "Error: workflow debt: %s:%d: %s\n", FILENAME, line, message > "/dev/stderr"
    invalid = 1
}
function leap(y) { return y % 4 == 0 && (y % 100 != 0 || y % 400 == 0) }
# Gregorian civil date -> days since 1970-01-01, without platform-specific date parsing.
function civil(y, m, d, era, yoe, doy, doe) {
    y -= (m <= 2)
    era = int(y / 400)
    yoe = y - era * 400
    doy = int((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + d - 1
    doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
    return era * 146097 + doe - 719468
}
function timestamp(s, y, m, d, maxday, tail, clock, zone, h, minute, second, offset, parts) {
    valid_date = 0
    if (substr(s, 1, 10) !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) return -1
    y = substr(s, 1, 4) + 0; m = substr(s, 6, 2) + 0; d = substr(s, 9, 2) + 0
    maxday = (m == 2 ? 28 + leap(y) : (m == 4 || m == 6 || m == 9 || m == 11 ? 30 : 31))
    if (y < 1 || m < 1 || m > 12 || d < 1 || d > maxday) return -1
    tail = substr(s, 11)
    if (tail == "") { valid_date = 1; return civil(y, m, d) * 86400 }
    if (tail !~ /^T[0-9][0-9]:[0-9][0-9](:[0-9][0-9](\.[0-9]+)?)?(Z|[+-][0-9][0-9]:[0-9][0-9])$/) return -1
    h = substr(tail, 2, 2) + 0; minute = substr(tail, 5, 2) + 0
    second = (substr(tail, 7, 1) == ":" ? substr(tail, 8, 2) + 0 : 0)
    if (h > 23 || minute > 59 || second > 59) return -1
    offset = 0
    if (substr(tail, length(tail), 1) != "Z") {
        zone = substr(tail, length(tail) - 5)
        if (substr(zone, 2, 2) + 0 > 23 || substr(zone, 5, 2) + 0 > 59) return -1
        offset = (substr(zone, 2, 2) * 3600 + substr(zone, 5, 2) * 60) * (substr(zone, 1, 1) == "+" ? 1 : -1)
    }
    valid_date = 1
    return civil(y, m, d) * 86400 + h * 3600 + minute * 60 + second - offset
}
function finish(last, key, j) {
    if (!current) return
    ends[current] = last
    for (j = 1; j <= 4; j++) {
        key = (j == 1 ? "Where" : j == 2 ? "Added" : j == 3 ? "Priority" : "Status")
        if (fields[current, key] == "") fail("[" ids[current] "] missing " key " field", starts[current])
    }
    key = fields[current, "Priority"]
    if (key != "fix-now" && key != "worth-doing" && key != "only-if-grows") fail("[" ids[current] "] invalid priority: " key, starts[current])
    key = fields[current, "Status"]
    if (key != "active" && key != "resolved" && key != "accepted") fail("[" ids[current] "] invalid status: " key, starts[current])
    key = fields[current, "Added"]
    timestamp(key)
    if (key != "" && !valid_date) fail("[" ids[current] "] invalid ISO 8601 Added date: " key, starts[current])
    for (j = 1; j <= 5; j++) {
        key = (j == 1 ? "Problem" : j == 2 ? "Impact" : j == 3 ? "Solution" : j == 4 ? "Cost" : "Resolution")
        sub(/^[ \t\r\n]+/, "", fields[current, key])
        sub(/\n---[ \t\r\n]*$/, "", fields[current, key])
        sub(/[ \t\r\n]+$/, "", fields[current, key])
    }
    field_key = ""
    current = 0
}
function marker(i, p, s) {
    p = fields[i, "Priority"]; s = fields[i, "Status"]
    if (s == "resolved") return dim "[resolved]" off
    if (s == "accepted") return dim "[accepted]" off
    return (p == "fix-now" ? red : p == "worth-doing" ? yellow : green) "[active]" off
}
function display(i, days) {
    printf "  %s %s[%s]%s %s\n", marker(i), bold, ids[i], off, titles[i]
    printf "    Priority: %s | Location: %s", fields[i, "Priority"], fields[i, "Where"]
    if (age) {
        days = int((now - timestamp(fields[i, "Added"])) / 86400)
        if (days < 0) days = 0
        printf " | Age: %d days", days
    }
    printf "\n"
}
function append_body(line) {
    if (current && (field_key == "Problem" || field_key == "Impact" || field_key == "Solution" || field_key == "Cost" || field_key == "Resolution")) {
        fields[current, field_key] = fields[current, field_key] "\n" line
    }
}
function json_string(s, out, c, i, code) {
    out = "\""
    for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (c == "\"") out = out "\\\""
        else if (c == "\\") out = out "\\\\"
        else if (c == "\n") out = out "\\n"
        else if (c == "\r") out = out "\\r"
        else if (c == "\t") out = out "\\t"
        else {
            code = control[c]
            out = out (code ? sprintf("\\u%04x", code) : c)
        }
    }
    return out "\""
}
function json_item(i, days) {
    printf "%s{\"id\":%s,\"title\":%s,\"location\":%s,\"added\":%s,\"priority\":%s,\"status\":%s", json_count++ ? "," : "", json_string(ids[i]), json_string(titles[i]), json_string(fields[i, "Where"]), json_string(fields[i, "Added"]), json_string(fields[i, "Priority"]), json_string(fields[i, "Status"])
    printf ",\"problem\":%s,\"impact\":%s,\"solution\":%s,\"cost\":%s,\"resolution\":%s,\"commit\":%s,\"pr\":%s", json_string(fields[i, "Problem"]), json_string(fields[i, "Impact"]), json_string(fields[i, "Solution"]), json_string(fields[i, "Cost"]), json_string(fields[i, "Resolution"]), json_string(fields[i, "Commit"]), json_string(fields[i, "PR"])
    if (age) {
        days = int((now - timestamp(fields[i, "Added"])) / 86400)
        printf ",\"age_days\":%d", days < 0 ? 0 : days
    }
    printf "}"
}
BEGIN { for (code = 1; code < 32; code++) control[sprintf("%c", code)] = code }
function print_entry(    line) {
    while ((getline line < entry_file) > 0) print line
    close(entry_file)
    print ""
}
{
    lines[NR] = $0
    if ($0 ~ /[^ \t\r]/) nonempty = 1
    if ($0 == "# Technical Debt" || $0 == "# Technical Debt\r") heading = 1
    if ($0 ~ /^[ \t]*```/ || $0 ~ /^[ \t]*~~~/) {
        delimiter = ($0 ~ /^[ \t]*```/ ? "`" : "~")
        if (!fenced) { fenced = 1; fence_delimiter = delimiter }
        else if (delimiter == fence_delimiter) fenced = 0
        append_body($0)
        next
    }
    if (fenced) { append_body($0); next }
    if ($0 ~ /^## Status: / || $0 ~ /^## Entry Template/ || $0 ~ /^### (Fix Now|Worth Doing|Only If It Grows)[ \t\r]*$/) {
        if (destination_group) { insertion = NR; destination_group = 0 }
    }
    if ($0 ~ /^## / || $0 ~ /^### (Fix Now|Worth Doing|Only If It Grows)[ \t\r]*$/) finish(NR - 1)
    if ($0 ~ /^## Status: /) {
        section = trim(substr($0, 12))
        if (section == "Active" || section == "Resolved" || section == "Accepted") {
            sections[section] = NR
            if (mode == "mutate" && section == destination) { insertion = NR + 1; destination_group = 1 }
        }
    }
    if ($0 ~ /^### (Fix Now|Worth Doing|Only If It Grows)[ \t\r]*$/ && section == "Active" && mode == "mutate" && priority_heading == trim(substr($0, 5))) { insertion = NR + 1; destination_group = 1 }
    if ($0 ~ /^## \[/) {
        text = substr($0, 5)
        bracket = index(text, "]")
        if (!bracket) { fail("malformed debt item heading", NR); next }
        id = substr(text, 1, bracket - 1)
        title = trim(substr(text, bracket + 1))
        if (id !~ /^[A-Za-z0-9][A-Za-z0-9._-]*$/ || title == "") { fail("debt heading requires a valid ID and title", NR); next }
        if (seen[id]) fail("duplicate debt ID: " id, NR)
        seen[id] = 1
        current = ++count; ids[current] = id; titles[current] = title; starts[current] = NR
        if (id == target) target_index = current
        next
    }
    if (!current && $0 ~ /^\*\*(Where|Location|Added|Priority|Status):\*\*/) fail("debt metadata outside an item heading", NR)
    if (current && $0 ~ /^\*\*[A-Za-z ]+:\*\*/) {
        text = $0; sub(/^\*\*/, "", text); sub(/:\*\*.*/, "", text)
        key = (text == "Location" ? "Where" : text)
        value = $0; sub(/^\*\*[A-Za-z ]+:\*\*[ \t]*/, "", value); value = trim(value)
        if ((key == "Where" || key == "Added" || key == "Priority" || key == "Status" || key == "Commit" || key == "PR") && present[current, key]++) fail("[" ids[current] "] duplicate " key " field", NR)
        fields[current, key] = value
        field_key = key
        next
    }
    append_body($0)
}
END {
    finish(NR)
    if (destination_group) insertion = NR + 1
    if (fenced) fail("unclosed Markdown code fence", NR)
    if (nonempty && !heading) fail("expected # Technical Debt heading", 1)
    if (invalid) exit 1
    if (mode == "nonempty") exit (nonempty ? 0 : 1)
    if (mode == "validate") exit 0
    if (mode == "id") {
        suggestion = target
        suffix = 2
        while (seen[suggestion]) suggestion = target "-" suffix++
        print suggestion
        exit 0
    }
    if (mode == "get") {
        if (!target_index) { fail("debt item not found: " target, 1); exit 1 }
        if (field == "entry") for (i = starts[target_index]; i <= ends[target_index]; i++) print lines[i]
        else print fields[target_index, field]
        exit 0
    }
    if (mode == "mutate") {
        if (target != "" && !target_index) { fail("debt item not found: " target, 1); exit 1 }
        if (target == "" && seen[new_id]) { fail("duplicate debt ID: " new_id, 1); exit 1 }
        if (!insertion) { fail("missing destination section: " destination, 1); exit 1 }
        for (i = 1; i <= NR + 1; i++) {
            if (i == insertion) print_entry()
            if (i <= NR && (!target_index || i < starts[target_index] || i > ends[target_index])) print lines[i]
        }
        exit 0
    }
    if (mode == "list") {
        selected = 0
        if (format == "json") printf "["
        for (i = 1; i <= count; i++) if (priority == "" || fields[i, "Priority"] == priority) {
            selected++
            if (format == "json") json_item(i)
        }
        if (format == "json") { print "]"; exit 0 }
        print bold "Technical Debt:" off
        for (i = 1; i <= count; i++) if (priority == "" || fields[i, "Priority"] == priority) {
            if (!by_file) display(i)
            else if (!groups[fields[i, "Where"]]++) locations[++location_count] = fields[i, "Where"]
        }
        if (by_file) for (j = 1; j <= location_count; j++) {
            print "\n" bold "Location: " locations[j] off
            for (i = 1; i <= count; i++) if (fields[i, "Where"] == locations[j] && (priority == "" || fields[i, "Priority"] == priority)) display(i)
        }
        if (!selected) print "No debt items found"
    }
}
