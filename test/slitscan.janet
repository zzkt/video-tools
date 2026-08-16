#!/usr/bin/env janet
# Basic tests for video tools

(use ./helpers)

# slitscan

(defn test-slitscan []
  (printf "\n* Testing slitscan\n")
  (def input (string video-dir "/CEP144.mp4"))
  (def output (string output-dir "/slitscan_test"))
  (shell "sh" "-c" (string "janet " (os/cwd) "/slitscan.janet " input " --output " output " 2>&1"))
  (def horz (string output "_horizontal-smear.mkv"))
  (def vert (string output "_vertical-smear.mkv"))
  (if (and (file-exists? horz) (file-exists? vert))
    (printf "  PASS: slitscan created output files")
    (printf "  FAIL: slitscan did not create output files")))


(test-slitscan)
