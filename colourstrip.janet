#!/usr/bin/env janet
# colourstrip: Create a colour strip visualization from a video

(import cmd)
(import spork/sh)

(math/seedrandom (string (os/clock)))

(defn shell [& args]
  (os/execute args :p))

(defn basename [p]
  (last (string/split "/" p)))

(defn tmp []
  (string (or (os/getenv "TMPDIR") "/tmp")
          "/cstrip_" (math/random)))

(defn lavfi-safe [video t]
  (if (some (fn [c] (string/find (string/from-bytes c) video)) ":'\"?;&")
    (let [ln (string t ".ln.mp4")
          abs-video (if (string/has-prefix? "/" video) video
                      (string (os/cwd) "/" video))]
      (when (os/stat ln) (os/rm ln))
      (os/symlink abs-video ln)
      ln)
    video))


(defn colourstrip [video output frame-skip blur]
  (def t (tmp))
  (def lavfi-video (lavfi-safe video t))
  (def px-dir (string t "_px"))
  (os/mkdir px-dir)
  (printf "Extracting pixel columns (1 frame per %d frames)..." frame-skip)
  (shell "sh" "-c"
         (string "ffmpeg -y -v error"
                 " -i " (sh/escape lavfi-video)
                 " -vf tblend=all_mode=average,scale=1:1,fps=1/" frame-skip
                 " " px-dir "/pixel-%04d.png"))
  (def px-count (length (filter |(string/has-prefix? "pixel-" $) (os/dir px-dir))))
  (printf "Got %d pixel columns" px-count)
  (printf "Combining into strip...")
  (def blur-filter (if (> blur 0) (string ",avgblur=sizeX=" blur) ""))
  (shell "sh" "-c"
         (string "ffmpeg -y -v error"
                 " -i " px-dir "/pixel-%04d.png"
                 " -filter_complex \"scale=3:75,tile=" px-count "x1" blur-filter "\""
                 " " (sh/escape output)))
  (each f (os/dir px-dir)
    (os/rm (string px-dir "/" f)))
  (os/rm px-dir)
  (when (not= lavfi-video video)
    (os/rm (string t ".ln.mp4")))
  (try (os/rm t) ([_] nil))
  (printf "Saved: %s" output))


(cmd/main (cmd/fn ```Create a colour strip visualization from a video.

Extracts a single pixel column from averaged frames and combines them
into a horizontal strip showing the colour progression of the video.```
  [video :string
   --output (optional :string "strip.png")
   --frame-skip (optional :int++ 15)
   --blur (optional :int+ 3)]
  (colourstrip video output frame-skip blur)))
