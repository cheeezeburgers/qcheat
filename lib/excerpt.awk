# POSIX awk: rank short windows, not whole manuals. Environment variables
# preserve literal question data (awk -v would interpret backslash escapes).
BEGIN {
    query = ENVIRON["QCHEAT_DOC_QUERY"]
    source = ENVIRON["QCHEAT_DOC_SOURCE"]
    tag_count = split(ENVIRON["QCHEAT_DOC_TAGS"], tags, " ")
    stop = " a an and are as at be can command current do for from how i in is it me of on or please program qcheat the this to tool use using what with vim neovim nvim git gh "
    n = split(query, words, /[^a-z0-9_-]+/)
    for (i = 1; i <= n && count < 24; i++) {
        word = words[i]
        if (length(word) > 1 && !index(stop, " " word " ") && !seen[word]++) {
            terms[++count] = word
        }
    }
    # Small vocabulary expansions; these select documentation, not answers.
    if (query ~ /copy/) terms[++count] = "yank"
    if (query ~ /recurs/) terms[++count] = "recurs"
    if (query ~ /folder/) terms[++count] = "director"
    if (query ~ /delete/) terms[++count] = "remove"
}
{
    # Drain excess pipe input without SIGPIPE; bound retained text and scoring.
    bytes += length($0) + 1
    if (NR > 20000 || bytes > 1048576) next
    line = $0
    gsub(/\033\[[0-9;]*[mK]/, "", line)
    while (sub(/.\010/, "", line)) {}
    gsub(/[\001-\010\013-\037\177]/, "", line)
    if (length(line) > 240) line = substr(line, 1, 225) " [truncated]"
    text[++total] = line
    file[total] = FILENAME
    number[total] = FNR
    lower = tolower(line)
    for (i = 1; i <= count; i++) {
        if (index(lower, terms[i])) score[total]++
    }
    for (i = 1; i <= tag_count; i++) {
        if (tags[i] != "" && index(line, tags[i])) {
            score[total] += 100
            found_tag = 1
        }
    }
}
END {
    # Rank by matches across a window, retaining command headers and text
    # split over multiple lines. Strict > makes ties deterministic.
    for (i = 1; i <= total; i++) {
        for (j = i; j <= i + 5 && j <= total && file[j] == file[i]; j++) {
            rank[i] += score[j]
        }
        # Keep the invocation available alongside flags and examples, but
        # only when this document actually matches the question.
        if (text[i] ~ /^[[:space:]]*(USAGE|SYNOPSIS)[[:space:]]*$/) usage_at = i
    }
    output = ""
    for (part = 1; part <= 3; part++) {
        best = found_tag ? 99 : 0
        at = 0
        for (i = 1; i <= total; i++) {
            if (!used[i] && rank[i] > best) { best = rank[i]; at = i }
        }
        if (!at) break
        if (part == 1 && usage_at && !found_tag) at = usage_at
        start = at > 2 ? at - 2 : 1
        while (file[start] != file[at]) start++
        end = at + 11 < total ? at + 11 : total
        label = file[at] == "-" || file[at] == "" ? source : file[at]
        block = "[Source: " substr(label, 1, 240) "; line " number[start] "]\n"
        for (i = start; i <= end; i++) {
            if (file[i] == file[at] && !printed[i]++) block = block text[i] "\n"
        }
        for (i = start - 6; i <= end + 6; i++) {
            if (file[i] == file[at]) used[i] = 1
        }
        # Respect the output budget using whole retained lines.
        n = split(block, lines, "\n")
        for (i = 1; i < n; i++) {
            if (length(output) + length(lines[i]) + 1 > 6000) break
            output = output lines[i] "\n"
        }
        if (length(output) < 6000) output = output "\n"
    }
    if (output != "") printf "%s", output
}
