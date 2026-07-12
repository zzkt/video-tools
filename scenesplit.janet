#!/usr/bin/env janet
# scenesplit: Split video(s) into scenes and generate an HTML overview.

(import cmd)

# ffmpeg logging verbosity
(def loglevel "error")

# Shell
(defn shell [& args]
  (os/execute args :p))

(defn shell-quote [s]
  (string "'" (string/replace "'" "'\\''" s) "'"))

# File helpers
(defn ensure-dir [p]
  (unless (= (os/stat p :mode) :directory) (os/mkdir p)))

(defn basename [p]
  (first (string/split "." (last (string/split "/" p)))))

# Video files are recognised by extension
(def video-exts
  (tabseq [e :in ["mp4" "avi" "mov" "mkv" "webm" "flv" "wmv" "m4v"]]
    e true))

(defn video-file? [p]
  (def ext (last (string/split "." p)))
  (and ext (video-exts ext)))

(defn find-videos [input]
  (case (os/stat input :mode)
    :file (if (video-file? input) [input] (do (printf "Warning: %s not a supported video\n" input) []))
    :directory (map (fn [f] (string input "/" f)) (filter video-file? (os/dir input)))
    (do (printf "Warning: %s does not exist\n" input) [])))


# Filename and path sanitisation
(def lavfi-chars ["'" ":" ";" "?" "&"])

(defn lavfi-has-special [s]
  (or (string/find "'" s) (string/find ":" s) (string/find ";" s)
      (string/find "?" s) (string/find "&" s)))

(defn lavfi-sanitize [s]
  (reduce (fn [acc c] (string/replace-all c "_" acc)) s lavfi-chars))

(defn lavfi-escape-filter [s]
  (reduce (fn [acc c] (string/replace-all c (string "\\" c) acc)) s ["," ";" "[" "]"]))

(defn make-lavfi-safe [video tmp]
  (if (lavfi-has-special video)
    (do (def safe-name (lavfi-sanitize (basename video)))
        (def ln (string tmp "_" safe-name "_ln.mp4"))
        (try (os/rm ln) ([_] nil))
        (os/symlink video ln)
        ln)
    video))


# ffmpeg wrapping
(defn scene-timestamps [video threshold]
  (def tmp (string (or (os/getenv "TMPDIR") "/tmp") "/ffprobe_" (math/random)))
  (def lavfi-video (lavfi-escape-filter (make-lavfi-safe video tmp)))
  (shell "sh" "-c" (string "ffprobe -v " loglevel " -show_entries frame=pts_time -of csv=p=0 "
                           "-f lavfi \"movie=" lavfi-video ",select=gt(scene\\," threshold ")\""
                           " > " (shell-quote tmp)))
  (when (lavfi-has-special video)
    (def safe-name (lavfi-sanitize (basename video)))
    (os/rm (string tmp "_" safe-name "_ln.mp4")))
  (def result (try (slurp tmp) ([_] "")))
  (os/rm tmp)
  (filter |(not= $ "") (map string/trim (string/split "\n" result))))

(defn extract-thumb [video ts idx out]
  (def ss (if (> idx 0) ts "0"))
  (def dst (string out "/scene_" (string/format "%03d" idx) ".jpg"))
  (shell "sh" "-c"
         (string "ffmpeg -v " loglevel
                 " -y -ss " ss " -i " (shell-quote video)
                 " -vframes 1 -q:v 2 " (shell-quote dst)))
  dst)

(defn cut-clip [video ts dur idx out ext]
  (def ss (if (> idx 0) ts "0"))
  (def dst (string out "/scene_" (string/format "%03d" idx) ext))
  (shell "sh" "-c"
         (string "ffmpeg -v " loglevel
                 " -y -ss " ss " -i " (shell-quote video)
                 (if dur (string " -t " dur) "")
                 " -c copy " (shell-quote dst)))
  dst)


# Scene processing
(defn process-video [video out-dir threshold cut ext]
  (ensure-dir out-dir)
  (def timestamps (scene-timestamps video threshold))
  (def n (+ (length timestamps) 1))
  (def clips (when cut
    (map (fn [i]
           (def ts (scan-number (or (get timestamps i) "0")))
           (def next-ts (scan-number (or (get timestamps (+ i 1)) "0")))
           (file/write stdout
                       (string "\r  [" (+ i 1) "/" n "] Cutting scene_"
                               (string/format "%03d" i) ext))
           (file/flush stdout)
           (cut-clip video ts (when (< (+ i 1) n) (- next-ts ts)) i out-dir ext))
         (range n))))
  (when clips (file/write stdout "\n"))
  (def result (map (fn [i]
         (def ts (or (get timestamps i) "0"))
         (file/write stdout (string "\r  [" (+ i 1) "/" n "] Extracting scene_"
                                    (string/format "%03d" i) ".jpg"))
         (file/flush stdout)
         @{:index i
           :timestamp ts
           :image (extract-thumb video ts i out-dir)
           :clip (when clips (get clips i))})
       (range n)))
  (file/write stdout "\n")
  result)


# HTML generation
(def css-dark
  "* {margin 0;padding 0;box-sizing:border-box}
body {font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;background:#1a1a2e;color:#eee;padding:2rem}
h1 {text-align:center;margin-bottom:2rem;color:#e94560}
.video-section {margin-bottom:3rem;background:#16213e;border-radius:12px;padding:1.5rem}
.video-title {font-size:1.4rem;margin-bottom:1rem;color:#0f3460;background:#e94560;display:inline-block;padding:.3rem 1rem;border-radius:6px}
.scenes-grid {display:grid;grid-template-columns:repeat(auto-fill,minmax(200px,1fr));gap:1rem}
.scene-card {background:#0f3460;border-radius:8px;overflow:hidden;transition:transform .2s}
.scene-card:hover {transform:scale(1.03)}
.scene-card img {width:100%;aspect-ratio:16/9;object-fit:cover;display:block}
.scene-info {padding:.5rem .7rem;font-size:.85rem}
.scene-num {color:#e94560;font-weight:bold}
.scene-time {color:#a8a8b3;float:right}
.scene-link {color:#e94560;font-size:.8rem;margin-left:.5rem}")

(def css-light
  "* {margin 0;padding 0;box-sizing:border-box}
body {font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;background:#f5f5f5;color:#222;padding:2rem}
h1 {text-align:center;margin-bottom:2rem;color:#c0392b}
.video-section {margin-bottom:3rem;background:#fff;border-radius:12px;padding:1.5rem;box-shadow:0 2px 8px rgba(0,0,0,.1)}
.video-title {font-size:1.4rem;margin-bottom:1rem;color:#fff;background:#c0392b;display:inline-block;padding:.3rem 1rem;border-radius:6px}
.scenes-grid {display:grid;grid-template-columns:repeat(auto-fill,minmax(200px,1fr));gap:1rem}
.scene-card {background:#fff;border-radius:8px;overflow:hidden;transition:transform .2s;box-shadow:0 1px 4px rgba(0,0,0,.15)}
.scene-card:hover {transform:scale(1.03)}
.scene-card img {width:100%;aspect-ratio:16/9;object-fit:cover;display:block}
.scene-info {padding:.5rem .7rem;font-size:.85rem}
.scene-num {color:#c0392b;font-weight:bold}
.scene-time {color:#888;float:right}
.scene-link {color:#c0392b;font-size:.8rem;margin-left:.5rem}")

(defn esc [s]
  (->> s (string/replace "&" "&amp;") (string/replace "<" "&lt;")
       (string/replace ">" "&gt;") (string/replace "\"" "&quot;")))

(defn url-encode [s]
  (def len (length s))
  (var i 0)
  (var r "")
  (while (< i len)
    (def c (string/slice s i (+ i 1)))
    (case c
      "?" (set r (string r "%3F"))
      "&" (set r (string r "%26"))
      "#" (set r (string r "%23"))
      "%" (set r (string r "%25"))
      " " (set r (string r "%20"))
      (set r (string r c)))
    (set i (+ i 1)))
  r)

(defn fmt-time [ts]
  (def s (scan-number ts))
  (def h (math/floor (/ s 3600)))
  (def m (math/floor (/ (mod s 3600) 60)))
  (def s (- s (* h 3600) (* m 60)))
  (if (> h 0) (string/format "%d:%02d:%05.2f" h m s) (string/format "%d:%05.2f" m s)))


(defn write-html [videos path theme]
  (def b (buffer/new 4096))
  (buffer/push b
    "<!DOCTYPE html>\n<html lang=\"en\"><head>\n"
    "<meta charset=\"UTF-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">\n"
    "<title>Video Scene index</title>\n<style>\n"
    (if (= theme "light") css-light css-dark)
    "</style></head><body>")
    (each video videos
    (buffer/push b (string/format "<div class=\"video-section\"><div class=\"video-title\">%s</div>\n<div class=\"scenes-grid\">\n" (esc (video :name))))
    (each scene (video :scenes)
      (buffer/push b (string/format "<div class=\"scene-card\"><img src=\"%s\" alt=\"Scene %d\">\n<div class=\"scene-info\"><span class=\"scene-num\">Scene %d</span><span class=\"scene-time\">%s</span>"
        (url-encode (scene :rel-path)) (+ (scene :index) 1) (+ (scene :index) 1) (fmt-time (scene :timestamp))))
      (when (scene :rel-clip)
        (buffer/push b (string/format "<a class=\"scene-link\" href=\"%s\">video</a>" (url-encode (scene :rel-clip)))))
      (buffer/push b "</div></div>\n"))
    (buffer/push b "</div></div>\n"))
  (buffer/push b "</body></html>\n")
  (spit path (string b)))


# CLI
(cmd/main (cmd/fn ```Split video(s) into scenes and generate an HTML overview.

Scans a directory or single video file, detects scene changes using ffmpeg,
extracts a JPEG thumbnail for each scene, and produces an HTML overview.

When --cut is passed, each scene is saved as a separate video file
alongside the thumbnails (uses stream copy for speed).```

  [--input (optional :string ".")
   "Single video file or directory containing videos"
   --output (optional :string "scenes_output")
   "Output directory for thumbnails, clips, and the HTML report"
   --cut (flag)
   "Cut each scene into a separate video file"
   --ext (optional :string ".mp4")
   "File extension for cut scene clips"
   --threshold (optional :number 0.3)
   "Scene detection threshold 0.0-1.0, lower => more sensitive"
   --light (flag)
   "Use light theme for HTML report"]

  # strip trailing slash from output to avoid double-slash in paths
  (def output (string/trimr output "/"))
  (printf "Input:  %s\nOutput: %s\nThreshold: %g\n" input output threshold)
  (when cut (printf "Cut mode: ON (ext: %s)\n" ext))
  (ensure-dir output)
  (def videos (find-videos input))
  (when (empty? videos) (print "No video files found.") (break))
  (printf "Found %d video file(s)\n\n" (length videos))
  (def results @[])
  (def total (length videos))
  (var idx 0)
  (each video videos
    (++ idx)
    (def name (basename video))
    (def dir (string output "/" name))
    (printf "Processing file [%d/%d]: %s\n" idx total name)
    (def scenes (process-video video dir threshold cut ext))
    (printf "  %d scene(s) detected\n" (length scenes))
    (each s scenes
      (put s :rel-path (string name "/" (last (string/split "/" (s :image)))))
      (when (s :clip) (put s :rel-clip (string name "/" (last (string/split "/" (s :clip)))))))
    (array/push results {:name name :scenes scenes}))
  (write-html results (string output "/scenes.html") (if light "light" "dark"))
  (printf "\nDone! HTML report: %s/scenes.html\n" output)))
