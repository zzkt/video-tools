#!/usr/bin/env janet
# Basic tests for video tools

(use ./helpers)

(defn test-colourstrip []
  (printf "\n* Testing colourstrip\n")
  (def input (string video-dir "/CEP144.mp4"))
  (def output (string output-dir "/strip.png"))
  (shell "sh" "-c" (string "janet " (os/cwd) "/colourstrip.janet " input " --output " output " 2>&1"))
  (if (file-exists? output)
    (printf "  PASS: colourstrip created strip")
    (printf "  FAIL: colourstrip did not create strip")))

(test-colourstrip)
