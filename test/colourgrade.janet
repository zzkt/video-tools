#!/usr/bin/env janet
# Basic tests for video tools

(use ./helpers)

(def input (string video-dir "/CEP144.mp4"))
(def clut (string (os/cwd) "/CEP144.mp4_clut.png"))
(def output (string output-dir "/CEP144_graded.mp4"))

(defn test-colourgrade-generate []
  (printf "\n* Testing colourgrade (generate)\n")
  (shell "sh" "-c"
         (string "janet " (os/cwd)
                 "/colourgrade.janet " input " 2>&1"))
  (if (file-exists? clut)
    (do
      (printf "  PASS: colourgrade generated CLUT")
      clut)
    (do
      (printf "  FAIL: colourgrade did not generate CLUT")
      nil)))


(defn test-colourgrade-apply []
  (printf "\n* Testing colourgrade (apply)\n")
  (def clut (test-colourgrade-generate))
  (if clut
    (do
      (shell "sh" "-c"
             (string "janet " (os/cwd)
                     "/colourgrade.janet --lut " clut
                     " " input " " output " 2>&1"))
      # (os/rm clut)
      (if (file-exists? output)
        (printf "  PASS: colourgrade applied CLUT")
        (printf "  FAIL: colourgrade did not apply CLUT")))
    (printf "  SKIP: colourgrade apply (generate failed)")))


(test-colourgrade-apply)
