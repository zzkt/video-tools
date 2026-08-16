#!/usr/bin/env janet
# slitscan: Create temporal smear slitscans from a video.

(import cmd)
(import spork/sh)

(math/seedrandom (string (os/clock)))

(defn shell [& args]
  (os/execute args :p))

(defn shell-out [cmd]
  (def tmp (string (or (os/getenv "TMPDIR") "/tmp") "/slit_" (math/random)))
  (shell "sh" "-c" (string cmd " > " (sh/escape tmp) " 2>&1"))
  (def result (try (string/trim (slurp tmp)) ([_] "")))
  (os/rm tmp)
  result)

(defn ffprobe-val [video key loglevel]
  (def video-path
    (if (string/has-prefix? "/" video) video
        (string (os/cwd) "/" video)))
  (def raw
    (shell-out
     (string
      "ffprobe -v " loglevel
      " -of default=noprint_wrappers=1:nokey=1 -show_entries stream="
      key " " (sh/escape video-path))))
  (when (and raw (not= raw ""))
    (def line (first (string/split "\n" raw)))
    (def parts (string/split "/" line))
    (if (= (length parts) 2)
      (/ (scan-number (parts 0)) (scan-number (parts 1)))
      (scan-number line))))

(defn last-slash [s]
  (var idx nil)
  (for i 0 (length s)
    (when (= (string/slice s i (+ i 1)) "/") (set idx i))) idx)


(defn slitscan [video output
                width height
                cleanup
                verbose loglevel]
  (let [video-path (if (string/has-prefix? "/" video)
                     video
                     (string (os/cwd) "/" video))
        sep (last-slash output)
        out-dir (if sep (string/slice output 0 sep) ".")]
    (shell-out (string "mkdir -p " (sh/escape out-dir)))
    (def tmp (if (= loglevel "")
               (shell-out (string "mktemp -d " (sh/escape out-dir) "/slit_XXXX"))
               (string out-dir "/slit_tmp")))
    (when verbose (printf "using folder '~s' for input\n" tmp))
    (let [resized (string tmp "/resized.mkv")
          duration (ffprobe-val video "duration" loglevel)
          fps (ffprobe-val video "r_frame_rate" loglevel)
          frames-raw (ffprobe-val video "nb_frames" loglevel)
          frames (if frames-raw
                   frames-raw
                   (math/ceil (* (or duration 0) (or fps 24))))]
      (when verbose
        (do (printf "duration: %g seconds" (or duration 0))
            (printf "fps: %g" (or fps 24))
            (printf "frames: %d" frames)
            (printf "transform dimensions: %dx%d" width height)))
      (printf "Resizing video...")
      (def logflag (if (= loglevel "") "" (string " -loglevel " loglevel)))
      (def devnull (if (= loglevel "") " 2>/dev/null" ""))
      (shell "sh" "-c"
             (string "ffmpeg" logflag
                     " -y -i " (sh/escape video-path)
                     " -vf scale=" width ":" height
                     " -crf 10 " (sh/escape resized) devnull))
      (printf "Extracting slices...")
      (for i 0 frames
        (file/write stdout (string "\r  Frame " (+ i 1) " of " frames))
        (file/flush stdout)
        (let [sel (string "select=gte(n\\," i "),format=yuv444p,split[horz][vert]")
              horz-f (string "[horz]crop=in_w:1:0:" i ",tile=1x" height "[horz]")
              vert-f (string "[vert]crop=1:in_h:" i ":0,tile=" width "x1[vert]")]
          (shell "sh" "-c"
                 (string "ffmpeg -y" devnull
                         " -i " (sh/escape resized)
                         " -filter_complex \""
                         sel ";" horz-f ";" vert-f "\""
                         " -map '[horz]' -vframes 1 "
                         tmp "/horz_frame" (string/format "%05d" i) ".png"
                         " -map '[vert]' -vframes 1 " tmp
                         "/vert_frame" (string/format "%05d" i) ".png"))
          (file/write stdout "\n")
          (printf "Assembling output...\n")
          (def out-h (string output "_horizontal-smear.mkv"))
          (def out-v (string output "_vertical-smear.mkv"))
          (def cmd-h (string "ffmpeg" logflag
                             " -y -r " fps
                             " -i " tmp
                             "/horz_frame%05d.png"
                             " -crf 10 " (sh/escape out-h)))
          (def cmd-v (string "ffmpeg" logflag
                             " -y -r " fps
                             " -i " tmp
                             "/vert_frame%05d.png"
                             " -crf 10 " (sh/escape out-v)))
          (printf "Running: %s" cmd-h)
          (shell "sh" "-c" cmd-h)
          (printf "Running: %s" cmd-v)
          (shell "sh" "-c" cmd-v)
          (when cleanup
            (shell "sh" "-c" (string "rm -rf " (sh/escape tmp)))
            (printf "Removed temp files"))
          (printf "Saved: %s" out-h)
          (printf "Saved: %s" out-v))))))


(cmd/main
 (cmd/fn ```Create slitscan temporal smear videos from a video.

Extracts vertical and horizontal slices from each frame and stacks them
into two videos showing temporal progression across the image.
```
    [video :string
     --output (optional :string "slitscan")
     --width (optional :int++ 640)
     --height (optional :int++ 360)
     --cleanup (flag)
     --verbose (flag)
     --loglevel (optional :string "")]

    (slitscan video output width height cleanup verbose loglevel)))
