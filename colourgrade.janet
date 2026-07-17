#!/usr/bin/env janet
# colourgrade: Generate HaldCLUT or apply it to a video

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

(defn basename [p]
  (last (string/split "/" p)))

(defn hald-generate [video]
  (def tmp (string (or (os/getenv "TMPDIR") "/tmp") "/hald_" (math/random)))
  (def lavfi-video (make-lavfi-safe video tmp))
  (def output (string (basename video) "_clut.png"))
  (printf "Generating HaldCLUT identity image with frame at 0:00:04...\n")
  (shell "sh" "-c" (string "ffmpeg -y -v error"
                           " -f lavfi -i haldclutsrc=8"
                           " -i " (shell-quote lavfi-video)
                           " -ss 0:00:04 -frames:v 1"
                           " -filter_complex \"[1]scale=-1:512[b];[0][b]hstack\""
                           " " (shell-quote output)))
  (when (lavfi-has-special video) (os/rm (string tmp "_ln.mp4")))
  (printf "Saved: %s\n" output)
  (print "\nEdit the PNG to apply your colour grading, then apply with ffmpeg:")
  (printf "  colourgrade --lut %s INPUT OUTPUT\n" output))

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

Generate a HaldCLUT identity image from a video:
  colourgrade video.mp4

Apply an edited CLUT to a video:
  colourgrade --lut clut.png input.mp4 output.mp4```

  [video :string "Input video file"
   output (optional :string "") "Output file (apply mode only)"
   --lut (optional :string "")
   "HaldCLUT PNG file (if provided, applies grading)"]

  (if (= lut "")
    (hald-generate video)
    (do
      (when (= output "")
        (printf "Error: output file required when using --lut\n")
        (break))
      (hald-apply video lut output)))))
