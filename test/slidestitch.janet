#!/usr/bin/env janet
# Basic tests for video tools

(use ./helpers)

# slidestitch

(defn test-slidestitch []
  (printf "\n* Testing slidestitch\n")
  (def input image-dir)
  (def output (string output-dir "/slidestitch_test.mp4"))
  (shell "sh" "-c" (string "janet " (os/cwd)
                           "/slidestitch.janet " input
                           " " output
                           " --duration 3 --fade 0.25 2>&1"))
  (if (file-exists? output)
    (printf "  PASS: slidestitch created video")
    (printf "  FAIL: slidestitch did not create video")))

(test-slidestitch)
