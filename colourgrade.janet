#!/usr/bin/env janet
# colourgrade: Automated colour grading using HaldCLUT

(import cmd)

(defn shell [& args]
  (os/execute args :p))

(defn shell-quote [s]
  (string "'" (string/replace "'" "'\\''" s) "'"))

(defn lavfi-has-special [s]
  (or (string/find "'" s) (string/find ":" s) (string/find ";" s)
      (string/find "?" s) (string/find "&" s)))

(defn make-lavfi-safe [video tmp]
  (if (lavfi-has-special video)
    (do (def ln (string tmp "_ln.mp4")) (os/symlink video ln) ln)
    video))


(defn hald-generate [video output frame-time]
  (def tmp (string (or (os/getenv "TMPDIR") "/tmp") "/hald_" (math/random)))
  (def lavfi-video (make-lavfi-safe video tmp))
  (printf "Generating HaldCLUT identity image with frame at %s...\n" frame-time)
  (shell "sh" "-c" (string "ffmpeg -y -v error"
                           " -f lavfi -i haldclutsrc=8"
                           " -i " (shell-quote lavfi-video)
                           " -ss " frame-time " -frames:v 1"
                           " -filter_complex \"[1]scale=-1:512[b];[0][b]hstack\""
                           " " (shell-quote output)))
  (when (lavfi-has-special video) (os/rm (string tmp "_ln.mp4")))
  (printf "Saved: %s\n" output)
  (print "\nEdit the PNG to apply your colour grading, then run:")
  (printf "  colour_grading apply --input VIDEO --lut %s --output OUTPUT\n" output))


(defn hald-apply [video lut output]
  (printf "Applying HaldCLUT from %s...\n" lut)
  (shell "sh" "-c" (string "ffmpeg -y -v error"
                           " -i " (shell-quote video)
                           " -i " (shell-quote lut)
                           " -filter_complex haldclut"
                           " -pix_fmt yuv420p"
                           " -c:v libx264 -preset slow -crf 18"
                           " -c:a copy"
                           " " (shell-quote output)))
  (printf "Saved: %s\n" output))


(cmd/main (cmd/fn ```Automated colour grading using HaldCLUT with ffmpeg.

Generate a HaldCLUT identity image with a reference frame from your video,
edit the PNG to apply colour grading, then apply it back to the video.```

  [command :string
   --input (required :string)
   "Input video file"
   --output (required :string)
   "Output file path"
   --lut (optional :string "")
   "HaldCLUT PNG file (required for apply)"
   --frame-time (optional :string "0:00:04")
   "Timestamp for reference frame (generate only)"]

  (case command
    "generate" (hald-generate input output frame-time)
    "apply" (do
      (when (= lut "") (print "Error: --lut required for apply") (break))
      (hald-apply input lut output))
    (printf "Error: unknown command '%s' (use generate or apply)\n" command))))
