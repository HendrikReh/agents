(lang dune 3.20)

(name agents)

(generate_opam_files true)

(source
 (github username/reponame))

(authors "Author Name <author@example.com>")

(maintainers "Maintainer Name <maintainer@example.com>")

(license MIT)

(documentation https://url/to/documentation)

(package
 (name agents)
 (synopsis "Planner-style agent PoC")
 (description "LangGraph-inspired planner/executor agent implemented in OCaml using Lwt.")
 (depends
  (ocaml (>= 5.1))
  lwt
  cohttp-lwt-unix
  uri
  yojson
  cmdliner)
 (tags
  ("agent" "planner" "langgraph")))

; See the complete stanza docs at https://dune.readthedocs.io/en/stable/reference/dune-project/index.html
