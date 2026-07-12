#!/usr/bin/env janet
# colourstrip: Create a colour strip visualization from a video

(import cmd)

(defn shell [& args]
  (os/execute args :p))

(defn shell-quote [s]
  (string "'" (string/replace "'" "'\\''" s) "'"))

(defn basename [p]
  (last (string/split "/" p)))

(def lavfi-chars ["'" ":" ";" "?" "&"])

(defn lavfi-has-special [s]
  (or (string/find "'" s) (string/find ":" s) (string/find ";" s)
      (string/find "?" s) (string/find "&" s)))

(defn lavfi-sanitize [s]
  (reduce (fn [acc c] (string/replace-all c "_" acc)) s lavfi-chars))

(defn make-lavfi-safe [video tmp]
  (if (lavfi-has-special video)
    (do (def safe-name (lavfi-sanitize (basename video)))
        (def ln (string tmp "_" safe-name "_ln.mp4"))
        (try (os/rm ln) ([_] nil))
        (os/symlink video ln)
        ln)
    video))


(defn colourstrip [video output frame-skip blur]
  (def tmp (string (or (os/getenv "TMPDIR") "/tmp") "/cstrip_" (math/random)))
  (def lavfi-video (make-lavfi-safe video tmp))
  (def px-dir (string tmp "_px"))
  (os/mkdir px-dir)
  (printf "Extracting pixel columns (1 frame per %d frames)...\n" frame-skip)
  (shell "sh" "-c" (string "ffmpeg -y -v error"
                           " -i " (shell-quote lavfi-video)
                           " -vf tblend=all_mode=average,scale=1:1,fps=1/" frame-skip
                           " " px-dir "/pixel-%04d.png"))
  (def px-count (length (filter |(string/has-prefix? "pixel-" $) (os/dir px-dir))))
  (printf "Got %d pixel columns\n" px-count)
  (printf "Combining into strip...\n")
  (def blur-filter (if (> blur 0) (string ",avgblur=sizeX=" blur) ""))
  (shell "sh" "-c" (string "ffmpeg -y -v error"
                           " -i " px-dir "/pixel-%04d.png"
                           " -filter_complex \"scale=3:75,tile=" px-count "x1" blur-filter "\""
                           " " (shell-quote output)))
  (each f (os/dir px-dir) (os/rm (string px-dir "/" f)))
  (os/rm px-dir)
  (when (lavfi-has-special video)
    (def safe-name (lavfi-sanitize (basename video)))
    (os/rm (string tmp "_" safe-name "_ln.mp4")))
  (try (os/rm tmp) ([_] nil))
  (printf "Saved: %s\n" output))


(cmd/main (cmd/fn ```Create a colour strip visualization from a video.

Extracts a single pixel column from averaged frames and combines them
into a horizontal strip showing the colour progression of the video.```

  [video :string
   --output (optional :string "strip.png")
   --frame-skip (optional :int++ 15)
   --blur (optional :int+ 3)]

  (colourstrip video output frame-skip blur)))
