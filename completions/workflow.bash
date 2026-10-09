# Bash completion for workflow and all standalone workflow-* commands.
# Sourcing this file does not invoke workflow or require bash-completion.
_workflow_completion_words() {
  local candidate
  while IFS= read -r candidate; do
    COMPREPLY+=("$candidate")
  done < <(compgen -W "$1" -- "$cur")
}

_workflow_completion_efforts() {
  local root=$PWD file slug
  while [[ $root != / && ! -d $root/.workflow ]]; do
    root=${root%/*}
    [[ -n $root ]] || root=/
  done
  for file in "$root"/.workflow/efforts/*.md; do
    [[ -f $file ]] || continue
    slug=${file##*/}
    slug=${slug%.md}
    [[ $slug =~ ^[a-z0-9]+(-[a-z0-9]+)*$ && $slug == "$cur"* ]] && COMPREPLY+=("$slug")
  done
  return 0
}

_workflow_complete() {
  local cur=${COMP_WORDS[COMP_CWORD]} prev= command start=1
  local sub= word skip=0 i formats='text json' options candidate
  local -a positionals=()
  COMPREPLY=()
  (( COMP_CWORD > 0 )) && prev=${COMP_WORDS[COMP_CWORD-1]}
  command=${COMP_WORDS[0]##*/}
  if [[ $command == workflow ]]; then
    if (( COMP_CWORD == 1 )); then
      _workflow_completion_words 'init update doctor uninstall hook version tasks deps decisions effort debt hotfix-review validate next help --help -h --version -v'
      return 0
    fi
    command=${COMP_WORDS[1]:-}
    start=2
  else
    command=${command#workflow-}
  fi

  # Determine positional subcommand before offering context-sensitive values.
  for (( i=start; i<COMP_CWORD; i++ )); do
    word=${COMP_WORDS[i]}
    if (( skip )); then skip=0; continue; fi
    case $word in
      --format|--effort|--after|--before|--field|--priority|--title|--id|--location|--description-file|--problem|--impact|--solution|--cost|--resolution|--commit|--pr|--reason|--mark-resolved)
        skip=1 ;;
      -*) ;;
      *) positionals+=("$word") ;;
    esac
  done
  sub=${positionals[0]:-}
  case $command in
    deps) formats='mermaid dot text' ;;
    effort|init|update|doctor|uninstall|hook|version|help) formats= ;;
  esac
  if [[ $prev == --format ]]; then
    case $command:$sub in
      debt:list) formats='text json' ;;
      debt:*) formats= ;;
    esac
    if [[ -n $formats ]]; then
      _workflow_completion_words "$formats"
      return 0
    fi
  fi
  case $prev in
    --effort) _workflow_completion_efforts; return 0 ;;
    --priority) _workflow_completion_words 'fix-now worth-doing only-if-grows'; return 0 ;;
    --field)
      for candidate in Decided 'Instead of' Because Mine 'Revisit when' Date Title; do
        if [[ ${candidate,,} == "${cur,,}"* ]]; then
          printf -v candidate '%q' "$candidate"
          COMPREPLY+=("$candidate")
        fi
      done
      return 0 ;;
    --description-file)
      while IFS= read -r candidate; do
        printf -v candidate '%q' "$candidate"
        COMPREPLY+=("$candidate")
      done < <(compgen -f -- "$cur")
      [[ $cur == '' || $cur == - ]] && COMPREPLY+=('-')
      return 0 ;;
    --after|--before|--title|--id|--location|--problem|--impact|--solution|--cost|--resolution|--commit|--pr|--reason|--mark-resolved)
      return 0 ;;
  esac

  options='--help -h --no-color'
  case $command in
    tasks) options+=' --blocked --ready --effort --status --format' ;;
    deps) options+=' --format --effort --all --check' ;;
    decisions)
      options+=' --after --before --format --effort'
      case $sub in
        search) options+=' --field' ;;
        recent) ;;
        *) options+=' --fix --apply' ;;
      esac
      [[ -z $sub ]] && options+=' list search recent validate'
      ;;
    effort)
      case $sub in
        '') options+=' list status create rename complete --archived' ;;
        list) options+=' --archived' ;;
        status|complete|rename)
          if (( ${#positionals[@]} == 1 )) && [[ $cur != -* ]]; then
            _workflow_completion_efforts
            return 0
          fi ;;
      esac
      ;;
    debt)
      case $sub in
        '') options+=' init list add resolve accept' ;;
        list) options+=' --priority --by-file --age --format' ;;
        add) options+=' --title --id --location --priority --description-file --problem --impact --solution --cost' ;;
        resolve|resolved) options+=' --resolution --commit --pr' ;;
        accept|accepted) options+=' --reason' ;;
      esac
      ;;
    hotfix-review) options+=' --all --mark-resolved --format' ;;
    validate) options+=' --fix --strict --format' ;;
    next) options+=' --interactive --format' ;;
    init|update) options='--force --claude --no-claude --help -h' ;;
    hook)
      options='--help -h'
      if [[ -z $sub ]]; then options+=' install uninstall status'; elif [[ $sub == install ]]; then options+=' --force'; fi
      ;;
    doctor|uninstall|version|help) options='--help -h' ;;
    *) return 0 ;;
  esac
  _workflow_completion_words "$options"
  return 0
}

complete -F _workflow_complete workflow workflow-tasks workflow-deps workflow-decisions workflow-effort workflow-debt workflow-hotfix-review workflow-validate workflow-next
