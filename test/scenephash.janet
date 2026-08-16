#!/usr/bin/env janet
# Basic tests for video tools

(use ./helpers)

# scenephash

(defn test-scenephash []
  (printf "\n* Testing scenephash\n")
  (def input (string video-dir "/CEP144.mp4"))
  (def output (string output-dir "/phash_test"))
  (shell "sh" "-c" (string "janet " (os/cwd)
                           "/scenephash.janet " input
                           " --output " output
                           " 2>&1"))
  (def clip (string output "_001.mp4"))
  (if (file-exists? clip)
    (printf "  PASS: scenephash created clips")
    (printf "  FAIL: scenephash did not create clips")))


(test-scenephash)
