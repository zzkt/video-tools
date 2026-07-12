#!/usr/bin/env janet
# slitscan: Create temporal smear slitscans from a video.

(import cmd)

(defn shell [& args]
  (os/execute args :p))

(defn shell-quote [s]
  (string "'" (string/replace "'" "'\\''" s) "'"))

(defn shell-out [cmd]
  (def tmp (string (or (os/getenv "TMPDIR") "/tmp") "/slit_" (math/random)))
  (shell "sh" "-c" (string cmd " > " (shell-quote tmp) " 2>&1"))
  (def result (try (string/trim (slurp tmp)) ([_] "")))
  (os/rm tmp)
  result)

(defn ffprobe-val [video key]
  (def raw (shell-out (string "ffprobe -v error -of default=noprint_wrappers=1:nokey=1 -show_entries stream=" key " " (shell-quote video))))
  (when (and raw (not= raw ""))
    (def line (first (string/split "\n" raw)))
    (def parts (string/split "/" line))
    (if (= (length parts) 2)
      (/ (scan-number (parts 0)) (scan-number (parts 1)))
      (scan-number line))))

(defn slitscan [video output width height cleanup verbose loglevel]
  (defn last-slash [s] (var idx nil) (for i 0 (length s) (when (= (string/slice s i (+ i 1)) "/") (set idx i))) idx)
  (def sep (last-slash output))
  (def out-dir (if sep (string/slice output 0 sep) "."))
  (shell-out (string "mkdir -p " (shell-quote out-dir)))
  (def tmp (if (= loglevel "") (shell-out (string "mktemp -d " (shell-quote out-dir) "/slit_XXXX")) (string out-dir "/slit_tmp")))
  (when verbose (printf "using folder '~s' for input\n" tmp))
  (def resized (string tmp "/resized.mkv"))
  (def duration (ffprobe-val video "duration"))
  (def fps (ffprobe-val video "r_frame_rate"))
  (def frames-raw (ffprobe-val video "nb_frames"))
  (def frames (if frames-raw frames-raw (math/ceil (* (or duration 0) (or fps 24)))))
  (when verbose (printf "duration: %g seconds\n" (or duration 0)))
  (when verbose (printf "fps: %g\n" (or fps 24)))
  (when verbose (printf "frames: %d\n" frames))
  (when verbose (printf "transform dimensions: %dx%d\n" width height))
  (printf "Resizing video...\n")
  (def logflag (if (= loglevel "") "" (string " -loglevel " loglevel)))
  (def devnull (if (= loglevel "") " 2>/dev/null" ""))
  (shell "sh" "-c" (string "ffmpeg" logflag " -y -i " (shell-quote video)
                           " -vf scale=" width ":" height " -crf 10 " (shell-quote resized) devnull))
  (printf "Extracting slices...\n")
  (for i 0 frames
    (file/write stdout (string "\r  Frame " (+ i 1) " of " frames))
    (file/flush stdout)
    (def sel (string "select=gte(n\\," i "),format=yuv444p,split[horz][vert]"))
    (def horz-f (string "[horz]crop=in_w:1:0:" i ",tile=1x" height "[horz]"))
    (def vert-f (string "[vert]crop=1:in_h:" i ":0,tile=" width "x1[vert]"))
    (shell "sh" "-c" (string "ffmpeg -y" devnull " -i " (shell-quote resized)
                             " -filter_complex \"" sel ";" horz-f ";" vert-f "\""
                             " -map '[horz]' -vframes 1 " tmp "/horz_frame" (string/format "%05d" i) ".png"
                             " -map '[vert]' -vframes 1 " tmp "/vert_frame" (string/format "%05d" i) ".png")))
  (file/write stdout "\n")
  (printf "Assembling output...\n")
  (def out-h (string output "_horizontal-smear.mkv"))
  (def out-v (string output "_vertical-smear.mkv"))
  (def cmd-h (string "ffmpeg" logflag " -y -r " fps " -i " tmp "/horz_frame%05d.png"
                     " -crf 10 " (shell-quote out-h)))
  (def cmd-v (string "ffmpeg" logflag " -y -r " fps " -i " tmp "/vert_frame%05d.png"
                     " -crf 10 " (shell-quote out-v)))
  (printf "Running: %s\n" cmd-h)
  (shell "sh" "-c" cmd-h)
  (printf "Running: %s\n" cmd-v)
  (shell "sh" "-c" cmd-v)
  (when cleanup
    (shell "sh" "-c" (string "rm -rf " (shell-quote tmp)))
    (printf "Removed temp files\n"))
  (printf "Saved: %s\n" out-h)
  (printf "Saved: %s\n" out-v))

(cmd/main (cmd/fn ```Create slitscan temporal smear videos from a video.

Extracts vertical and horizontal slices from each frame and stacks them
into two videos showing temporal progression across the image.

Based on https://github.com/zzkt/slitscan```

  [video :string
   --output (optional :string "slitscan")
   --width (optional :int++ 640)
   --height (optional :int++ 360)
   --cleanup (flag)
   --verbose (flag)
   --loglevel (optional :string "")]

  (slitscan video output width height cleanup verbose loglevel)))
