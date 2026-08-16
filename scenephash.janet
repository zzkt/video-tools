#!/usr/bin/env janet
# scenephash: Split video into scenes using perceptual hashing

(import cmd)
(import phash)
(import spork/sh)

(math/seedrandom (string (os/clock)))

(defn shell [& args]
  (os/execute args :p))

(defn tmp []
  (string (or (os/getenv "TMPDIR") "/tmp")
          "/snphsh_" (math/random)))

(defn shell-out [cmd]
  (def t (tmp))
  (shell "sh" "-c" (string cmd " > " (sh/escape t) " 2>&1"))
  (def result (try (string/trim (slurp t)) ([_] "")))
  (os/rm t)
  result)

(defn ffprobe-val [video key]
  (def video-path (if (string/has-prefix? "/" video) video
                   (string (os/cwd) "/" video)))
  (def raw (shell-out
            (string "ffprobe -v error "
                    " -of default=noprint_wrappers=1:nokey=1"
                    " -show_entries"
                    " format=" key " " (sh/escape video-path))))
  (when (and raw (not= raw "")) (scan-number raw)))


(defn extract-keyframes [video t]
  (def video-path (if (string/has-prefix? "/" video) video
                   (string (os/cwd) "/" video)))
  (def frames-dir (string t "/frames"))
  (if (os/mkdir t)
    (os/mkdir frames-dir)
    (os/mkdir t frames-dir))
  (shell "sh" "-c"
         (string "ffmpeg -y -v error -i " (sh/escape video-path)
                 " -vf \"select=eq(pict_type\\,I),scale=128:128\""
                 " -vsync vfr " frames-dir "/frame_%04d.png"))
  (def frames (sort
               (filter |(string/has-prefix? "frame_" $)
                       (os/dir frames-dir))))
  (map (fn [f] (string frames-dir "/" f)) frames))


(defn find-scenes [frames threshold]
  (printf "Computing perceptual hashes for %d keyframes..." (length frames))
  (def hashes @[])
  (each f frames
    (def h (phash/dct-image-hash f))
    (when h (array/push hashes h)))
  (printf "Got %d valid hashes" (length hashes))
  (def scenes @[])
  (when (> (length hashes) 1)
    (var prev-hash (first hashes))
    (for i 1 (length hashes)
      (def curr-hash (get hashes i))
      (def dist (phash/hamming-distance prev-hash curr-hash))
      (when (>= dist threshold)
        (array/push scenes i))
      (set prev-hash curr-hash)))
  scenes)


(defn get-keyframe-times [video tmp]
  (def video-path (if (string/has-prefix? "/" video) video
                   (string (os/cwd) "/" video)))
  (def raw (shell-out
            (string "ffprobe -v error -select_streams v:0"
                    " -show_entries frame=pts_time,pict_type"
                    " -of csv=p=0 " (sh/escape video-path))))
  (def times @[])
  (each line (string/split "\n" raw)
    (def trimmed (string/trim line))
    (when (and trimmed (not= trimmed ""))
      (def parts (string/split "," trimmed))
      (when (and (> (length parts) 1) (= (get parts 1) "I"))
        (try (array/push times (scan-number (get parts 0)))
             ([_] nil)))))
  times)


(defn split-video [video scenes-keyframes keyframe-times output]
  (def video-path (if (string/has-prefix? "/" video) video
                   (string (os/cwd) "/" video)))
  (def split-points @[])
  (each s scenes-keyframes
    (when (< s (length keyframe-times))
      (array/push split-points (get keyframe-times s))))
  (def duration (ffprobe-val video "duration"))
  (array/push split-points (or duration 0))
  (def n (length split-points))
  (printf "Splitting video into %d scenes..." n)
  (var start 0)
  (for i 0 n
    (def end (get split-points i))
    (def clip (string output "_" (string/format "%03d" (+ i 1)) ".mp4"))
    (file/write stdout (string "\r  [" (+ i 1) "/" n "] " clip))
    (file/flush stdout)
    (when (> end start)
      (shell "sh" "-c"
             (string "ffmpeg -y -v error -ss " start
                     " -i " (sh/escape video-path)
                     " -t " (- end start)
                     " -c copy " (sh/escape clip)))
      (set start end)))
  (file/write stdout "\n")
  n)


(defn scenephash [video output threshold]
  (printf "Analyzing: %s" video)
  (def t (tmp))
  (def frames (extract-keyframes video t))
  (when (= (length frames) 0)
    (printf "Error: no keyframes extracted")
    (break))
  (def keyframe-times (get-keyframe-times video t))
  (def scenes (find-scenes frames threshold))
  (printf "Found %d scene change points" (length scenes))
  (def n (split-video video scenes keyframe-times output))
  (printf "Created %d scene clips" n)
  (shell "sh" "-c" (string "rm -rf " (sh/escape t))))


(cmd/main
 (cmd/fn ```Split video into scenes using perceptual hashing.

Uses pHash DCT hashing on keyframes to detect scene changes and
split video at those points into separate files.```

  [video :string
   "Input video file"
   --output (optional :string "scenes")
   "Output file prefix"
   --threshold (optional :int+ 10)
   "Hamming distance threshold (0-64, lower = more scenes)"]

  (scenephash video output threshold)))
