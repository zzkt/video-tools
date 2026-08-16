#!/usr/bin/env janet
# Basic tests for video tools

(use ./helpers)

# scenesplit

(defn test-scenesplit []
  (printf "\n* Testing scenesplit\n")
  (def input (string video-dir "/CEP144.mp4"))
  (def output (string output-dir "/scenesplit_test"))
  (ensure-dir output)
  (shell "sh" "-c" (string "janet " (os/cwd) "/scenesplit.janet --input " input " --output " output " 2>&1"))
  (def html-file (string output "/scenes.html"))
  (if (file-exists? html-file)
    (printf "  PASS: scenesplit created HTML report")
    (printf "  FAIL: scenesplit did not create HTML report")))


(test-scenesplit)
