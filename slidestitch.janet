#!/usr/bin/env janet
# slidestitch: Create video from crossfaded images

(import cmd)
(import spork/sh)

(math/seedrandom (string (os/clock)))

(defn shell [& args]
  (os/execute args :p))

(defn tmp []
  (string (or (os/getenv "TMPDIR") "/tmp")
          "/slst_" (math/random)))

(defn run-ffmpeg [cmd]
  (def t (os/clock))
  (shell "sh" "-c" cmd)
  (printf "Elapsed: %.1fs\n" (- (os/clock) t)))


(defn lavfi-safe [video t]
  (if (some (fn [c] (string/find (string/from-bytes c) video)) ":'\"?;&")
    (let [ln (string t ".ln.mp4")
          video-path (if (string/has-prefix? "/" video) video
                      (string (os/cwd) "/" video))]
      (when (os/stat ln) (os/rm ln))
      (os/symlink video-path ln)
      ln)
    video))


(defn find-images [dir]
  (def exts {"png" true "jpg" true "jpeg" true "avif" true
             "webp" true "tiff" true "tif" true "bmp" true})
  (defn image-file? [f]
    (def ext (last (string/split "." f)))
    (and ext (exts ext)))
  (def files (sort (filter image-file? (os/dir dir))))
  (map (fn [f] (string dir "/" f)) files))


(defn slide-timing [n-images lead-in lead-out fade-slope total-duration]
  (def n-fades (- n-images 1))
  (def total-fade-time (* n-fades fade-slope))
  (def slide-duration
    (if (> n-images 0)
      (/ (+ total-duration total-fade-time) n-images) 0))
  (when (< slide-duration 0)
    (error "Duration too short for given images and fade settings"))
  slide-duration)


(defn build-xfade-filter [n-images fade-slope slide-duration lead-in lead-out]
  (def filters @[])
  (for i 0 (- n-images 1)
    (def in1 (if (= i 0)
               (string "[sv0]") (string "[v" (- i 1) "]")))
    (def in2 (string "[sv" (+ i 1) "]"))
    (def out (if (= i (- n-images 2))
               "[vout]" (string "[v" i "]")))
    (def fade-offset (* (+ i 1) (- slide-duration fade-slope)))
    (array/push filters
                (string in1 in2
                        "xfade=transition=fade:duration=" fade-slope
                        ":offset=" fade-offset out)))
  (def filter-str (string/join filters ";"))
  (if (or (> lead-in 0) (> lead-out 0))
    (do
      (def total-xfade-duration
        (- (* n-images slide-duration) (* (- n-images 1) fade-slope)))
      (string filter-str
              ";[vout]fade=t=in:st=0:d=" lead-in
              ",fade=t=out:st=" (- total-xfade-duration lead-out)
              ":d=" lead-out "[vfinal]"))
    filter-str))


(defn build-displacement-filter [displacement-map]
  (when (nil? displacement-map) (break ""))
  (def map-path
    (if (string/has-prefix? "/" displacement-map)
      displacement-map
      (string (os/cwd) "/" displacement-map)))
  (string "[vout][1:v]displacement=xdisplace:10:ydisplace:10[vfinal]"))


(defn slidestitch [imgs output scale
                   lead-in lead-out fade-slope total-duration
                   displacement-map
                   fps]
  (def images (find-images imgs))
  (def n (length images))
  (when (= n 0) (error "No images found"))
  (printf "Found %d images" n)
  (def slide-duration (slide-timing n lead-in lead-out fade-slope total-duration))
  (printf "Slide duration: %.2fs" slide-duration)
  (printf "Total duration: %.2fs" total-duration)
  (def t (tmp))
  (os/mkdir t)
  (def input-args @[])
  (each img images
    (array/push input-args
                (string "-loop 1 -t " slide-duration
                        " -i " (sh/escape img))))
  (when displacement-map
    (def map-path (if (string/has-prefix? "/" displacement-map)
                   displacement-map
                   (string (os/cwd) "/" displacement-map)))
    (array/push input-args (string "-i " (sh/escape map-path))))
  (def filter-parts @[])
  # image scaling
  (defn scale-filter [idx]
    (case scale
      "stretch" (string
                 "[" idx ":v]scale=1920:1080[sv" idx "]")
      "contain" (string
                 "[" idx ":v]scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2:color=black[sv" idx "]")
      "cover" (string
               "[" idx ":v]scale=1920:1080:force_original_aspect_ratio=increase,crop=1920:1080[sv" idx "]")
      (string "[" idx ":v]scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2[sv" idx "]")))
  # build filters
  (if (> n 1)
    (do
      (def scale-filters @[])
      (for i 0 n
        (array/push scale-filters (scale-filter i)))
      (def scale-str (string/join scale-filters ";"))
      (array/push filter-parts scale-str)
      (def xfade-filter
        (if (or (> lead-in 0) (> lead-out 0))
          (build-xfade-filter n fade-slope slide-duration lead-in lead-out)
          (build-xfade-filter n fade-slope slide-duration 0 0)))
      (array/push filter-parts xfade-filter)
      (when displacement-map
        (def disp-filter (build-displacement-filter displacement-map))
        (array/push filter-parts disp-filter)))
    (do
      (def fade-filter
        (if (or (> lead-in 0) (> lead-out 0))
          (string (scale-filter 0)
                  ",fade=t=in:st=0:d="
                  lead-in ",fade=t=out:st="
                  (- total-duration lead-out)
                  ":d=" lead-out "[vout]")
          (string (scale-filter 0) "[vout]")))
      (array/push filter-parts fade-filter)))
  (def filter-str (string/join filter-parts ";"))
  (def map-flag
    (if (or displacement-map (> lead-in 0) (> lead-out 0))
      "-map \"[vfinal]\""
      "-map \"[vout]\""))
  (def input-str (string/join input-args " "))
  (def filter-escaped (string/replace-all "'" "'\\''" filter-str))
  (def out (if (= output "") "slidestitch.mp4" output))
  (printf "Building video...")
  (run-ffmpeg
   (string "ffmpeg -y -v error"
           " " input-str
           " -filter_complex " (sh/escape filter-str)
           " " map-flag
           " -r " fps
           " -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p"
           " " (sh/escape out)))
  (when (> n 0)
    (shell "sh" "-c" (string "rm -rf " (sh/escape t))))
  (printf "Saved: %s\n" out))


(cmd/main (cmd/fn ```Create video from crossfaded images.

Takes a directory of images and creates a video with crossfades
between them. Supports lead-in/out fades, fade duration, and
optional displacement map.

Example:
  slidestitch ./frames output.mp4 --duration 60 --fade 1.5
  slidestitch ./frames output.mp4 --lead-in 2 --lead-out 1 --fade 2 --duration 30
```
  [imgs :string
   "Directory containing images"
   output :string
   "Output video file"
   --scale (optional :string "contain")
   "Scale mode: stretch, contain, cover"
   --lead-in (optional :number 0)
   "Lead-in fade duration in seconds"
   --lead-out (optional :number 0)
   "Lead-out fade duration in seconds"
   --fade (optional :number 1.0)
   "Crossfade slope duration in seconds"
   --duration (optional :number 10)
   "Total video duration in seconds"
   --displacement (optional :string "")
   "Displacement map video for effects"
   --fps (optional :number 24)
   "Output video frame rate"]

  (def disp (if (= displacement "") nil displacement))
  (slidestitch imgs output scale lead-in lead-out fade duration disp fps)))
