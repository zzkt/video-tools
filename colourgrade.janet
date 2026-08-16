#!/usr/bin/env janet
# colourgrade: Generate HaldCLUT or apply it to a video.

(import cmd)
(import spork/sh)

(math/seedrandom (string (os/clock)))

(defn basename [p]
  (last (string/split "/" p)))

(defn tmp []
  (string (or (os/getenv "TMPDIR") "/tmp")
          "/cg_" (math/random) ".txt"))

(defn lavfi-safe [video t]
  (if (some (fn [c] (string/find (string/from-bytes c) video)) ":'\"?;&")
    (let [ln (string t ".ln.mp4")
          video-path (if (string/has-prefix? "/" video) video
                      (string (os/cwd) "/" video))]
      (when (os/stat ln) (os/rm ln))
      (os/symlink video-path ln)
      ln)
    video))

(defn run-ffmpeg [cmd]
  (def t (os/clock))
  (os/execute ["sh" "-c" cmd] :p)
  (printf "Elapsed: %.1fs" (- (os/clock) t)))


(defn hald-generate [video frame-time]
  "Generate a HaldCLUT image from VIDEO at FRAME-TIME."
  (def t (tmp))
  (def lavfi (lavfi-safe video t))
  (def out (string (basename video) "_clut.png"))
  (printf "Generating HaldCLUT with frame at %s..." frame-time)
  (run-ffmpeg (string "ffmpeg -y -v error"
                      " -f lavfi -i haldclutsrc=8"
                      " -i " (sh/escape lavfi)
                      " -ss " frame-time " -frames:v 1"
                      " -filter_complex \"[1]scale=-1:512[b];[0][b]hstack\""
                      " " (sh/escape out)))
  (when (not= lavfi video)
    (os/rm (string t ".ln.mp4")))
  (printf "Saved: %s" out)
  (printf "Edit the PNG to apply your colour grading then run:")
  (printf "    colourgrade --lut '%s' INPUT OUTPUT\n" out))


(defn hald-apply [video lut output]
  "Apply a LUT image to VIDEO and write to OUTPUT file."
  (printf "Applying HaldCLUT from %s..." lut)
  (run-ffmpeg (string "ffmpeg -y -v error"
                      " -i " (sh/escape video)
                      " -i " (sh/escape lut)
                      " -filter_complex haldclut"
                      " -pix_fmt yuv420p"
                      " -c:v libx264 -preset slow -crf 18"
                      " -c:a copy " (sh/escape output)))
  (printf "Saved: %s" output))


(defn compare-videos [v1 v2 output]
  "Generate side-by-side comparison OUTPUT video from V1 and V2."
  (printf "Stacking '%s' and '%s'..." v1 v2)
  (run-ffmpeg (string "ffmpeg -y -v error"
                      " -i " (sh/escape v1)
                      " -i " (sh/escape v2)
                      " -filter_complex hstack " (sh/escape output)))
  (printf "Saved: %s" output))


(defn usage []
  (print "Automated colour grading using HaldCLUT with ffmpeg.")
  (print)
  (print "Usage:")
  (print "  colourgrade video.mp4                            Generate CLUT")
  (print "  colourgrade --lut clut.png input.mp4 output.mp4  Apply CLUT")
  (print "  colourgrade --compare clip1.mov clip2.mov        Side-by-side"))


(cmd/main (cmd/fn "Automated colour grading using HaldCLUT with ffmpeg."
  [video (optional :string "") "Input video file"
   output (optional :string "") "Output file"
   --lut (optional :string "")
   "HaldCLUT PNG file (if provided applies grading)"
   --frame-time (optional :string "0:00:04")
   "Timestamp for reference frame (generate only)"
   --compare (optional :string "")
   "Videos for side-by-side comparison"]

  (cond
    # compare
    (not (empty? compare))
    (compare-videos compare video
                    (if (= output "") "side-by-side.mp4" output))
    # apply lut
    (not (empty? lut))
    (if (= output "")
      (printf "Error: --output required with --lut")
      (hald-apply video lut output))
    # help
    (empty? video) (do (usage) (break))
    # generate
    (hald-generate video frame-time))))
